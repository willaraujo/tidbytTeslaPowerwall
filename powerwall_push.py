#!/usr/bin/env python3
"""Orchestrator: fetch Powerwall data from HA + weather, render via Pixlet,
push to Tidbyt. Supports polling (REST) or real-time (WebSocket) modes.
Weather via Pirate Weather API or Home Assistant weather entities
(e.g. Met.no / Meteorologisk institutt)."""

import asyncio
import base64
import json
import logging
import os
import random
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import requests
import yaml

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

SCRIPT_DIR = Path(__file__).parent
STAR_FILE = SCRIPT_DIR / "powerwall_tidbyt.star"
WEBP_OUTPUT = SCRIPT_DIR / "powerwall_tidbyt.webp"
TIDBYT_API_BASE = "https://api.tidbyt.com/v0/devices"
PIRATE_WEATHER_URL = "https://api.pirateweather.net/forecast"

# Default weather data returned when weather fetch fails or is unavailable
DEFAULT_WEATHER = {"icon": "clear-day", "temperature": "", "is_night": "false", "cloud_cover": "0", "sun_elevation": "45"}


def load_config():
    """Load config from YAML file. Path can be overridden via CONFIG_PATH env var."""
    config_path = os.environ.get("CONFIG_PATH", str(SCRIPT_DIR / "config.yaml"))
    logger.info("Loading config from %s", config_path)

    with open(config_path) as f:
        config = yaml.safe_load(f)

    # Allow env var overrides for sensitive values
    if os.environ.get("HA_URL"):
        config.setdefault("home_assistant", {})["url"] = os.environ["HA_URL"]
    if os.environ.get("HA_TOKEN"):
        config.setdefault("home_assistant", {})["token"] = os.environ["HA_TOKEN"]
    if os.environ.get("TIDBYT_DEVICE_ID"):
        config.setdefault("tidbyt", {})["device_id"] = os.environ["TIDBYT_DEVICE_ID"]
    if os.environ.get("TIDBYT_API_TOKEN"):
        config.setdefault("tidbyt", {})["api_token"] = os.environ["TIDBYT_API_TOKEN"]
    if os.environ.get("PIRATE_WEATHER_API_KEY"):
        config.setdefault("weather", {})["api_key"] = os.environ["PIRATE_WEATHER_API_KEY"]

    return config


def _build_ha_session(config):
    """Build a requests.Session with HA auth headers pre-configured."""
    ha_config = config["home_assistant"]
    session = requests.Session()
    session.headers.update({
        "Authorization": f"Bearer {ha_config['token']}",
        "Content-Type": "application/json",
    })
    session.ha_url = ha_config["url"].rstrip("/")
    return session


def fetch_ha_entity(session, entity_id):
    """Fetch a single entity state from Home Assistant REST API."""
    resp = session.get(f"{session.ha_url}/api/states/{entity_id}", timeout=10)
    resp.raise_for_status()
    return resp.json()


def fetch_all_sensors(session, config):
    """Fetch all Powerwall sensors from HA. Returns dict of metric -> value."""
    sensors = config["home_assistant"]["sensors"]
    results = {}

    for metric, entity_id in sensors.items():
        try:
            data = fetch_ha_entity(session, entity_id)
            state = data.get("state", "unavailable")
            if state in ("unavailable", "unknown"):
                logger.warning("Sensor %s is %s", entity_id, state)
                results[metric] = "0"
            else:
                results[metric] = state
        except requests.RequestException as e:
            logger.error("Failed to fetch %s (%s): %s", metric, entity_id, e)
            results[metric] = "0"

    return results


# Map Home Assistant weather conditions to Pirate Weather icon names
# used by the Starlark renderer.
HA_CONDITION_MAP = {
    "sunny": "clear-day",
    "clear-night": "clear-night",
    "partlycloudy": "partly-cloudy-day",
    "cloudy": "cloudy",
    "rainy": "rain",
    "pouring": "rain",
    "snowy": "snow",
    "snowy-rainy": "sleet",
    "hail": "sleet",
    "fog": "fog",
    "windy": "wind",
    "windy-variant": "wind",
    "lightning": "thunderstorm",
    "lightning-rainy": "thunderstorm",
    "exceptional": "cloudy",
}


def fetch_weather(session, config):
    """Fetch weather using the configured provider."""
    weather_config = config.get("weather", {})
    provider = weather_config.get("provider", "pirateweather")

    if provider == "homeassistant":
        return fetch_weather_ha(session, config)
    return fetch_weather_pirate(config)


# HA conditions that should flip to their night variant when sun is below horizon
HA_NIGHT_OVERRIDES = {
    "sunny": "clear-night",
    "partlycloudy": "partly-cloudy-night",
}


def fetch_weather_ha(session, config):
    """Fetch current weather from a Home Assistant weather entity (e.g. Met.no).
    Also fetches sun.sun for is_night and sun_elevation."""
    entity_id = config.get("weather", {}).get("entity_id", "weather.home")

    try:
        data = fetch_ha_entity(session, entity_id)
        condition = data.get("state", "sunny")

        if condition in ("unavailable", "unknown"):
            logger.warning("Weather entity %s is %s", entity_id, condition)
            return dict(DEFAULT_WEATHER)

        # Fetch sun.sun for is_night + elevation
        is_night = False
        sun_elevation = 45.0
        try:
            sun_data = fetch_ha_entity(session, "sun.sun")
            is_night = sun_data.get("state") == "below_horizon"
            sun_elevation = float(sun_data.get("attributes", {}).get("elevation", 0))
            logger.info("Sun state: %s (is_night=%s, elevation=%.1f)", sun_data.get("state"), is_night, sun_elevation)
        except requests.RequestException:
            logger.warning("Could not fetch sun.sun, assuming daytime")

        attrs = data.get("attributes", {})
        temp = attrs.get("temperature")

        # Use night override if applicable, otherwise fall back to standard map
        if is_night and condition in HA_NIGHT_OVERRIDES:
            icon = HA_NIGHT_OVERRIDES[condition]
        else:
            icon = HA_CONDITION_MAP.get(condition, "cloudy")

        if temp is not None:
            temp = str(int(round(float(temp))))
        else:
            temp = ""

        cloud_cover = attrs.get("cloud_coverage", attrs.get("cloudiness", 0))
        if cloud_cover is None:
            cloud_cover = 0

        logger.info("HA weather: condition=%s icon=%s temp=%s is_night=%s cloud_cover=%s elevation=%.1f",
                     condition, icon, temp, is_night, cloud_cover, sun_elevation)
        return {
            "icon": icon, "temperature": temp, "is_night": str(is_night).lower(),
            "cloud_cover": str(int(cloud_cover)), "sun_elevation": str(round(sun_elevation, 1)),
        }
    except requests.RequestException as e:
        logger.error("Failed to fetch HA weather (%s): %s", entity_id, e)
        return dict(DEFAULT_WEATHER)


def fetch_weather_pirate(config):
    """Fetch current weather from Pirate Weather API."""
    weather_config = config.get("weather", {})
    api_key = weather_config.get("api_key", "")
    lat = weather_config.get("latitude", 0)
    lon = weather_config.get("longitude", 0)

    if not api_key:
        logger.warning("No Pirate Weather API key configured, skipping weather")
        return dict(DEFAULT_WEATHER)

    url = f"{PIRATE_WEATHER_URL}/{api_key}/{lat},{lon}"
    params = {"units": "us", "exclude": "minutely,hourly,daily,alerts"}

    try:
        resp = requests.get(url, params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        currently = data.get("currently", {})
        icon = currently.get("icon", "clear-day")
        temp = currently.get("temperature", "")
        if temp != "":
            temp = str(int(round(float(temp))))
        # Pirate Weather encodes day/night in the icon name
        is_night = "night" in icon
        cloud_cover = currently.get("cloudCover", 0)
        return {"icon": icon, "temperature": temp, "is_night": str(is_night).lower(), "cloud_cover": str(int(cloud_cover * 100)), "sun_elevation": "0"}
    except requests.RequestException as e:
        logger.error("Failed to fetch weather: %s", e)
        return dict(DEFAULT_WEATHER)


# ---------------------------------------------------------------------------
# Game Engine: Persistent survival simulation
# ---------------------------------------------------------------------------

GAME_STATE_FILE = SCRIPT_DIR / "game_state.json"

# Game area: ONLY col1 (x=0-19) bottom half. Col2/col3 bottom have info displays.
# Characters, threats, crops, pets must all stay within x=0-19 to avoid overlapping
# text, numbers, and battery bar readouts.
GAME_X_MIN = 0         # Left edge
GAME_X_MAX = 19        # Right edge (col1 boundary)
HOME_X = 10            # "Home" position in the game area (center of col1)
POND_X = 4             # Fishing pond x-position
POND_Y = 25            # Fishing pond y-position
POWER_ZERO_W = 50      # Below this, solar panel text not shown

# Crop slots: (x, y) positions in the bottom half of the display
# Spread across col1 (x=0-19). Further from HOME_X = better yield.
CROP_SLOTS = [
    (2, 24),   # far left — best yield (distance 28 from house)
    (6, 22),   # left
    (10, 26),  # mid-left
    (14, 24),  # mid col1
    (17, 22),  # right edge of col1 — lowest yield (distance 13)
]
MAX_CROPS = len(CROP_SLOTS)
MAX_FOOD = 100

# Crop growth ticks per stage (base values, modified by growth_rate)
CROP_STAGE_TICKS = [10, 15, 20]  # seed->sprout, sprout->grown, grown->harvestable

# Character templates for initial state
CHAR_TEMPLATES = [
    {"id": "parent1", "shirt": "#4488cc", "max_hp": 10, "trait": "brave", "home_offset": -3},
    {"id": "parent2", "shirt": "#cc4444", "max_hp": 10, "trait": "cautious", "home_offset": 0},
    {"id": "kid", "shirt": "#44cc44", "max_hp": 6, "trait": "fast", "home_offset": 3},
]
PET_TEMPLATES = [
    {"id": "dog"},
    {"id": "cat"},
]


class GameEngine:
    """Persistent survival simulation driven by real Powerwall data."""

    def __init__(self):
        self.state = self._load_or_init()

    def _load_or_init(self):
        """Load state from disk or create initial state."""
        if GAME_STATE_FILE.exists():
            try:
                with open(GAME_STATE_FILE) as f:
                    state = json.load(f)
                if state.get("version") == 1:
                    # Backfill home_offset for saves from older versions
                    offset_map = {t["id"]: t["home_offset"] for t in CHAR_TEMPLATES}
                    for char in state.get("characters", []):
                        if "home_offset" not in char:
                            char["home_offset"] = offset_map.get(char["id"], 0)
                    logger.info("Loaded game state: tick=%d day=%d", state["tick"], state["day_number"])
                    return state
                logger.warning("Game state version mismatch, reinitializing")
            except (json.JSONDecodeError, KeyError) as e:
                logger.warning("Corrupt game state (%s), reinitializing", e)
        return self._init_state()

    def _init_state(self):
        """Create fresh game state."""
        chars = []
        for t in CHAR_TEMPLATES:
            home_x = max(GAME_X_MIN, min(GAME_X_MAX, HOME_X + t["home_offset"]))
            chars.append({
                "id": t["id"], "shirt": t["shirt"],
                "hp": t["max_hp"], "max_hp": t["max_hp"],
                "x": home_x, "state": "idle", "target_x": home_x,
                "alive": True, "trait": t["trait"], "revive_timer": 0,
                "home_offset": t["home_offset"],
            })
        pets = [{"id": t["id"], "x": HOME_X, "alive": True, "deployed": False} for i, t in enumerate(PET_TEMPLATES)]
        return {
            "version": 1, "tick": 0, "day_number": 1,
            "world": {
                "food": 50, "prosperity": 50,
                "crops": [], "threat_cooldown": 0, "last_event": "",
                "pond_active": False,
            },
            "characters": chars,
            "pets": pets,
            "threats": [],
            "was_night": False,
        }

    def _save(self):
        """Atomic save: write to .tmp then rename."""
        tmp = GAME_STATE_FILE.with_suffix(".tmp")
        with open(tmp, "w") as f:
            json.dump(self.state, f, separators=(",", ":"))
        tmp.rename(GAME_STATE_FILE)

    # --- Main tick ---

    def tick(self, sensor_data, weather_data):
        """Run one game tick. Returns dict of pixlet render params."""
        is_night = weather_data.get("is_night", "false") == "true"
        battery_pct = int(sensor_data.get("battery_pct", "0"))
        solar_power = float(sensor_data.get("solar_power", "0"))
        grid_status = sensor_data.get("grid_status", "on")
        weather_icon = weather_data.get("icon", "clear-day")

        # Track day transitions
        if self.state["was_night"] and not is_night:
            self.state["day_number"] += 1
        self.state["was_night"] = is_night

        # Pond: forms during rain, but NOT when solar panel text occupies col1
        show_panel = (not is_night) and solar_power > POWER_ZERO_W
        is_raining = weather_icon in ("rain", "sleet", "thunderstorm")
        self.state["world"]["pond_active"] = is_raining and not show_panel

        # Phase 1: Environment
        self._grow_crops(is_night, battery_pct)
        self._decay_food()

        # Phase 2: Threats
        self._spawn_threats(is_night, battery_pct, grid_status)
        self._move_threats()

        # Phase 3: Character AI
        alive_chars = [c for c in self.state["characters"] if c["alive"]]
        for char in alive_chars:
            self._character_decide(char, is_night, battery_pct, weather_icon)

        # Phase 4: Pet deployment (only one out at a time)
        self._deploy_pets()

        # Phase 5: Combat
        self._resolve_combat()

        # Phase 6: Pet abilities (dog barks at yeti, cat scratches alien)
        self._pet_abilities()

        # Phase 7: Movement
        self._move_characters()
        self._move_pets()

        # Phase 8: Revival
        self._check_revivals(battery_pct)

        # Phase 9: Starvation
        self._check_starvation()

        # Phase 10: Prosperity
        self._update_prosperity(battery_pct, solar_power)

        self.state["tick"] += 1
        self._save()
        return self._build_render_params()

    # --- Phase 1: Crops ---

    def _grow_crops(self, is_night, battery_pct):
        """Advance crop growth. Crops only grow at night (unless solar > 4000)."""
        if not is_night:
            return
        for crop in self.state["world"]["crops"]:
            if crop["stage"] >= 3:
                continue  # already harvestable
            # Calculate ticks needed for this stage
            base_ticks = CROP_STAGE_TICKS[crop["stage"]]
            adjusted = int(base_ticks / crop.get("growth_rate", 1.0))
            if battery_pct >= 80:
                adjusted = max(1, adjusted // 2)
            ticks_in_stage = self.state["tick"] - crop.get("stage_tick", crop["planted_tick"])
            if ticks_in_stage >= adjusted:
                crop["stage"] += 1
                crop["stage_tick"] = self.state["tick"]
            # Wither chance when battery critically low
            if battery_pct < 20 and random.random() < 0.10:
                if crop["stage"] > 0:
                    crop["stage"] -= 1
                    crop["stage_tick"] = self.state["tick"]

    def _decay_food(self):
        """Food decreases over time (characters eating)."""
        if self.state["tick"] % 10 == 0 and self.state["world"]["food"] > 0:
            self.state["world"]["food"] = max(0, self.state["world"]["food"] - 1)

    # --- Phase 2: Threats ---

    def _spawn_threats(self, is_night, battery_pct, grid_status):
        """Spawn threats based on conditions. Max 2 active threats."""
        if len(self.state["threats"]) >= 2:
            return
        if self.state["world"]["threat_cooldown"] > 0:
            self.state["world"]["threat_cooldown"] -= 1
            return

        base_chance = 15 if is_night else 3
        if battery_pct < 30:
            base_chance *= 2
        if grid_status.lower() != "on":
            base_chance = 33

        if random.randint(1, 100) <= base_chance:
            # Pick threat type — all spawn at col1 edges
            roll = random.randint(1, 100)
            if roll <= 40:
                # Yeti from the right edge of col1
                threat = {"type": "yeti", "x": GAME_X_MAX, "hp": 4, "state": "approaching", "speed": 1, "damage": 2, "dir": -1}
            elif roll <= 70:
                # Alien (little green man) from the left edge
                threat = {"type": "alien", "x": GAME_X_MIN, "hp": 2, "state": "approaching", "speed": 1, "damage": 1, "dir": 1}
            else:
                # Raider from the right edge
                threat = {"type": "raider", "x": GAME_X_MAX, "hp": 3, "state": "approaching", "speed": 1, "damage": 1, "dir": -1}
            self.state["threats"].append(threat)
            self.state["world"]["threat_cooldown"] = 8
            self.state["world"]["last_event"] = f"{threat['type']}_spawn"
            logger.info("Game: %s spawned at x=%d", threat["type"], threat["x"])

    def _move_threats(self):
        """Move threats toward house within col1 bounds."""
        for threat in self.state["threats"]:
            if threat["state"] == "approaching":
                direction = threat.get("dir", -1)
                if direction > 0:
                    threat["x"] = min(HOME_X + 3, threat["x"] + threat["speed"])
                else:
                    threat["x"] = max(HOME_X - 3, threat["x"] - threat["speed"])
                # Clamp to game area
                threat["x"] = max(GAME_X_MIN, min(GAME_X_MAX, threat["x"]))

    # --- Phase 3: Character AI ---

    def _nearest_threat_dist(self, char):
        """Distance to nearest threat from character."""
        if not self.state["threats"]:
            return 999
        return min(abs(char["x"] - t["x"]) for t in self.state["threats"])

    def _char_home_x(self, char):
        """Per-character home position so they don't all stack at HOME_X."""
        offset = char.get("home_offset", 0)
        return max(GAME_X_MIN, min(GAME_X_MAX, HOME_X + offset))

    def _character_decide(self, char, is_night, battery_pct, weather_icon):
        """Priority-based behavior tree for one character."""
        threat_dist = self._nearest_threat_dist(char)
        fighting_chars = [c for c in self.state["characters"] if c["alive"] and c["state"] == "fighting"]
        my_home = self._char_home_x(char)

        # 0. RETURNING — must finish walking home before taking new tasks
        #    Only combat/flee can interrupt a return trip
        if char["state"] == "returning":
            if abs(char["x"] - my_home) <= 1:
                # Arrived home — now idle
                char["state"] = "idle"
                char["x"] = my_home
                char["target_x"] = my_home
            elif threat_dist < 4 and char["hp"] > 2:
                pass  # fall through to flee/fight checks below
            else:
                return  # keep walking home

        # 1. FLEE — low HP and threat nearby
        flee_threshold = 3 if char["trait"] == "fast" else 2
        if char["hp"] <= flee_threshold and threat_dist < 6:
            char["state"] = "fleeing"
            char["target_x"] = my_home
            return

        # 2. FIGHT — threat nearby, brave enough
        if char["trait"] != "cautious" and threat_dist < (8 if char["trait"] == "brave" else 5) and char["hp"] > 2:
            nearest = min(self.state["threats"], key=lambda t: abs(char["x"] - t["x"]))
            char["state"] = "fighting"
            char["target_x"] = nearest["x"]
            return

        # 3. DEFEND — threat near house, no one else fighting it
        if threat_dist < 10 and len(fighting_chars) == 0 and char["hp"] > 2:
            nearest = min(self.state["threats"], key=lambda t: abs(char["x"] - t["x"]))
            char["state"] = "fighting"
            char["target_x"] = nearest["x"]
            return

        # 4. HARVEST — ripe crops at night (only one char per crop)
        harvestable = [c for c in self.state["world"]["crops"] if c["stage"] >= 3]
        # Filter out crops another character is already heading to
        busy_targets = {c["target_x"] for c in self.state["characters"]
                        if c["alive"] and c["id"] != char["id"] and c["state"] == "farming"}
        available_crops = [c for c in harvestable if c["x"] not in busy_targets]
        if available_crops and is_night and self.state["world"]["food"] < 50:
            crop = min(available_crops, key=lambda c: abs(char["x"] - c["x"]))
            if abs(char["x"] - crop["x"]) <= 2:
                # At crop — harvest then return home with supplies
                distance = abs(crop["x"] - HOME_X)
                base_yield = 15 + random.randint(0, 10)
                distance_bonus = int(distance * 0.5)
                bonus = 5 if char["trait"] == "cautious" else 0
                total = base_yield + distance_bonus + bonus
                self.state["world"]["food"] = min(MAX_FOOD, self.state["world"]["food"] + total)
                # Auto-replant: reset to seed stage, new growth rate
                crop["stage"] = 0
                crop["planted_tick"] = self.state["tick"]
                crop["stage_tick"] = self.state["tick"]
                crop["growth_rate"] = round(random.uniform(0.7, 1.3), 2)
                # Return home with supplies — won't take new tasks until home
                char["state"] = "returning"
                char["target_x"] = my_home
                self.state["world"]["last_event"] = "harvest"
                logger.info("Game: %s harvested crop at x=%d, yield=%d, food=%d (returning home)",
                            char["id"], crop["x"], total, self.state["world"]["food"])
            else:
                char["state"] = "farming"
                char["target_x"] = crop["x"]
            return

        # 5. PLANT — empty slot, night, have food
        if is_night and self.state["world"]["food"] > 20 and threat_dist > 8:
            used_xs = {c["x"] for c in self.state["world"]["crops"]}
            busy_plant = {c["target_x"] for c in self.state["characters"]
                          if c["alive"] and c["id"] != char["id"] and c["state"] == "farming"}
            empty_slots = [s for s in CROP_SLOTS if s[0] not in used_xs and s[0] not in busy_plant]
            if empty_slots:
                # Pick nearest empty slot to this character
                slot_x, slot_y = min(empty_slots, key=lambda s: abs(char["x"] - s[0]))
                if abs(char["x"] - slot_x) <= 2:
                    # At slot — plant, then return home
                    self.state["world"]["crops"].append({
                        "x": slot_x, "y": slot_y, "stage": 0,
                        "planted_tick": self.state["tick"],
                        "stage_tick": self.state["tick"],
                        "growth_rate": round(random.uniform(0.7, 1.3), 2),
                    })
                    char["state"] = "returning"
                    char["target_x"] = my_home
                    logger.info("Game: %s planted crop at x=%d,y=%d (returning home)", char["id"], slot_x, slot_y)
                else:
                    char["state"] = "farming"
                    char["target_x"] = slot_x
                return

        # 6. FISH — low food, no harvestable crops, pond must be active
        if self.state["world"]["food"] < 30 and not harvestable and self.state["world"].get("pond_active", False):
            if abs(char["x"] - POND_X) <= 2:
                char["state"] = "fishing"
                char["target_x"] = POND_X
                if random.random() < 0.30:
                    self.state["world"]["food"] = min(MAX_FOOD, self.state["world"]["food"] + 5)
                    logger.info("Game: %s caught a fish, food=%d", char["id"], self.state["world"]["food"])
            else:
                char["state"] = "fishing"
                char["target_x"] = POND_X
            return

        # 7. HEAL — at home, safe, have food
        if char["hp"] < char["max_hp"] and abs(char["x"] - my_home) <= 3 and threat_dist > 8 and self.state["world"]["food"] > 10:
            char["state"] = "idle"
            char["target_x"] = my_home
            if self.state["tick"] % 5 == 0:
                heal_amt = 2 if battery_pct >= 80 else 1
                char["hp"] = min(char["max_hp"], char["hp"] + heal_amt)
                self.state["world"]["food"] = max(0, self.state["world"]["food"] - 2)
            return

        # 8. PATROL — default daytime, stay within col1 game area
        # Only pick a new target when not already patrolling or reached current target
        if not is_night:
            if char["state"] != "patrol" or abs(char["x"] - char["target_x"]) <= 1:
                char["state"] = "patrol"
                # Each character patrols a different zone to avoid stacking
                if char["trait"] == "brave":
                    char["target_x"] = random.randint(14, GAME_X_MAX)
                elif char["trait"] == "cautious":
                    char["target_x"] = random.randint(GAME_X_MIN, 6)
                else:
                    char["target_x"] = random.randint(7, 13)
            return

        # 9. SLEEP — night, safe, nothing to do
        char["state"] = "idle"
        char["target_x"] = my_home
        if self.state["tick"] % 10 == 0 and char["hp"] < char["max_hp"]:
            char["hp"] = min(char["max_hp"], char["hp"] + 1)

    # --- Phase 4: Combat ---

    def _resolve_combat(self):
        """Resolve combat between characters and threats."""
        dead_threats = []
        for threat in self.state["threats"]:
            for char in self.state["characters"]:
                if not char["alive"] or char["state"] != "fighting":
                    continue
                if abs(char["x"] - threat["x"]) <= 2:
                    # Combat!
                    char_dmg = 1
                    if char["trait"] == "brave":
                        char_dmg = 2
                    # Dog bonus
                    for pet in self.state["pets"]:
                        if pet["id"] == "dog" and pet["alive"] and abs(pet["x"] - char["x"]) <= 5:
                            char_dmg += 1
                            break
                    threat["hp"] -= char_dmg
                    char["hp"] -= threat["damage"]
                    if char["hp"] <= 0:
                        char["hp"] = 0
                        char["alive"] = False
                        char["state"] = "dead"
                        char["revive_timer"] = 30
                        self.state["world"]["last_event"] = f"{char['id']}_died"
                        logger.info("Game: %s died!", char["id"])
                    if threat["hp"] <= 0:
                        dead_threats.append(threat)
                        self.state["world"]["food"] = min(MAX_FOOD, self.state["world"]["food"] + 10)
                        self.state["world"]["last_event"] = f"{threat['type']}_killed"
                        logger.info("Game: %s killed! +10 food", threat["type"])
                    break  # one combatant per threat per tick
        for t in dead_threats:
            if t in self.state["threats"]:
                self.state["threats"].remove(t)

    # --- Phase 5: Movement ---

    def _move_characters(self):
        """Move characters toward their target_x."""
        for char in self.state["characters"]:
            if not char["alive"] or char["state"] == "idle" or char["state"] == "fishing":
                continue
            target = char["target_x"]
            if char["x"] == target:
                continue
            # Speed based on HP ratio
            hp_ratio = char["hp"] / char["max_hp"] if char["max_hp"] > 0 else 0
            speed = 1
            if char["state"] == "fleeing":
                speed = 2
            elif char["trait"] == "fast":
                speed = 2
            elif hp_ratio < 0.33:
                speed = 1  # limping, already at 1
            else:
                speed = 2 if hp_ratio > 0.75 else 1

            if target > char["x"]:
                char["x"] = min(target, char["x"] + speed)
            else:
                char["x"] = max(target, char["x"] - speed)
            # Clamp to game area
            char["x"] = max(GAME_X_MIN, min(GAME_X_MAX, char["x"]))

    def _deploy_pets(self):
        """Only one pet can be deployed at a time. Choose based on threats."""
        dog = next((p for p in self.state["pets"] if p["id"] == "dog"), None)
        cat = next((p for p in self.state["pets"] if p["id"] == "cat"), None)
        if not dog or not cat:
            return

        has_yeti = any(t["type"] == "yeti" for t in self.state["threats"])
        has_alien = any(t["type"] == "alien" for t in self.state["threats"])

        if has_yeti and not has_alien:
            dog["deployed"] = True
            cat["deployed"] = False
        elif has_alien and not has_yeti:
            dog["deployed"] = False
            cat["deployed"] = True
        elif has_yeti and has_alien:
            # Pick based on which threat is closer to house
            yeti = min((t for t in self.state["threats"] if t["type"] == "yeti"),
                       key=lambda t: abs(t["x"] - HOME_X))
            alien = min((t for t in self.state["threats"] if t["type"] == "alien"),
                        key=lambda t: abs(t["x"] - HOME_X))
            if abs(yeti["x"] - HOME_X) < abs(alien["x"] - HOME_X):
                dog["deployed"] = True
                cat["deployed"] = False
            else:
                dog["deployed"] = False
                cat["deployed"] = True
        else:
            # No threats — both stay home
            dog["deployed"] = False
            cat["deployed"] = False

        # Recall undeployed pet to home
        if not dog["deployed"]:
            dog["x"] = HOME_X
        if not cat["deployed"]:
            cat["x"] = HOME_X

    def _pet_abilities(self):
        """Dog barks at yetis (scare off), cat scratches aliens (damage)."""
        for pet in self.state["pets"]:
            if not pet.get("deployed", False):
                continue

            if pet["id"] == "dog":
                # Dog barks at nearby yetis — chance to scare them off
                for threat in list(self.state["threats"]):
                    if threat["type"] == "yeti" and abs(pet["x"] - threat["x"]) < 8:
                        if random.random() < 0.25:
                            # Scare yeti — push back 5px toward edge
                            direction = threat.get("dir", -1)
                            retreat = 5 * (-direction)  # push back the way it came
                            threat["x"] += retreat
                            # If pushed off game area, remove it
                            if threat["x"] > GAME_X_MAX or threat["x"] < GAME_X_MIN:
                                self.state["threats"].remove(threat)
                                self.state["world"]["last_event"] = "yeti_scared"
                                logger.info("Game: Dog scared off yeti!")
                            else:
                                logger.info("Game: Dog barked at yeti! Pushed to x=%d", threat["x"])

            elif pet["id"] == "cat":
                # Cat scratches nearby aliens — deals 1 damage per tick
                for threat in list(self.state["threats"]):
                    if threat["type"] == "alien" and abs(pet["x"] - threat["x"]) < 6:
                        threat["hp"] -= 1
                        if threat["hp"] <= 0:
                            self.state["threats"].remove(threat)
                            self.state["world"]["food"] = min(MAX_FOOD, self.state["world"]["food"] + 10)
                            self.state["world"]["last_event"] = "alien_scratched"
                            logger.info("Game: Cat killed alien!")
                        else:
                            logger.info("Game: Cat scratched alien! HP=%d", threat["hp"])

    def _move_pets(self):
        """Move deployed pet to follow nearest alive character. Undeployed pets stay home."""
        alive_chars = [c for c in self.state["characters"] if c["alive"]]
        if not alive_chars:
            return
        for pet in self.state["pets"]:
            if not pet.get("deployed", False):
                continue
            # Follow nearest character
            nearest = min(alive_chars, key=lambda c: abs(c["x"] - pet["x"]))
            offset = 2 if pet["id"] == "dog" else -2
            target = nearest["x"] + offset
            if abs(pet["x"] - target) > 1:
                if target > pet["x"]:
                    pet["x"] = min(target, pet["x"] + 2)
                else:
                    pet["x"] = max(target, pet["x"] - 2)
            pet["x"] = max(GAME_X_MIN, min(GAME_X_MAX, pet["x"]))

    # --- Phase 6: Revival ---

    def _check_revivals(self, battery_pct):
        """Check if dead characters should revive."""
        all_dead = all(not c["alive"] for c in self.state["characters"])

        # Colony collapse: all dead for 100 ticks = new generation
        if all_dead:
            min_timer = min(c["revive_timer"] for c in self.state["characters"])
            if min_timer <= -100:
                logger.info("Game: Colony collapse! New generation spawning.")
                for char in self.state["characters"]:
                    my_home = self._char_home_x(char)
                    char["alive"] = True
                    char["hp"] = char["max_hp"]
                    char["x"] = my_home
                    char["state"] = "idle"
                    char["target_x"] = my_home
                    char["revive_timer"] = 0
                self.state["world"]["food"] = 50
                self.state["world"]["crops"] = []
                self.state["world"]["prosperity"] = 30
                return

        for char in self.state["characters"]:
            if char["alive"]:
                continue
            char["revive_timer"] -= 1

            # Revival thresholds based on battery
            threshold = -30 if battery_pct > 50 else (-60 if battery_pct > 20 else -120)
            if char["revive_timer"] <= threshold:
                my_home = self._char_home_x(char)
                char["alive"] = True
                char["hp"] = char["max_hp"] // 2
                char["x"] = my_home
                char["state"] = "idle"
                char["target_x"] = my_home
                char["revive_timer"] = 0
                self.state["world"]["last_event"] = f"{char['id']}_revived"
                logger.info("Game: %s revived with %d HP", char["id"], char["hp"])

    # --- Phase 7: Starvation ---

    def _check_starvation(self):
        """Characters take damage when food is 0."""
        if self.state["world"]["food"] > 0:
            return
        if self.state["tick"] % 5 == 0:
            for char in self.state["characters"]:
                if char["alive"]:
                    char["hp"] -= 1
                    if char["hp"] <= 0:
                        char["hp"] = 0
                        char["alive"] = False
                        char["state"] = "dead"
                        char["revive_timer"] = 30
                        logger.info("Game: %s starved!", char["id"])

    # --- Phase 8: Prosperity ---

    def _update_prosperity(self, battery_pct, solar_power):
        """Calculate prosperity from power + game state."""
        food_pct = (self.state["world"]["food"] / MAX_FOOD) * 100
        alive_count = sum(1 for c in self.state["characters"] if c["alive"])
        alive_pct = (alive_count / len(self.state["characters"])) * 100
        solar_score = min(100, (solar_power / 5000) * 100)
        self.state["world"]["prosperity"] = int(
            battery_pct * 0.3 + food_pct * 0.3 + alive_pct * 0.2 + solar_score * 0.2
        )

    # --- Render param serialization ---

    def _build_render_params(self):
        """Serialize game state to compact pixlet config params."""
        params = {}

        # Characters: "id:x:target_x:state:alive:speed"
        chars = []
        for c in self.state["characters"]:
            if c["alive"]:
                ratio = c["hp"] / c["max_hp"] if c["max_hp"] > 0 else 0
                speed = "slow" if ratio < 0.33 else ("mid" if ratio < 0.75 else "fast")
            else:
                speed = "dead"
            chars.append(f"{c['id']}:{c['x']}:{c['target_x']}:{c['state']}:{1 if c['alive'] else 0}:{speed}")
        params["gc"] = "|".join(chars)

        # Pets: "id:x:alive:deployed"
        pets = [f"{p['id']}:{p['x']}:{1 if p['alive'] else 0}:{1 if p.get('deployed', False) else 0}" for p in self.state["pets"]]
        params["gp"] = "|".join(pets)

        # Threats: "type:x:state:dir"
        threats = [f"{t['type']}:{t['x']}:{t['state']}:{t.get('dir', -1)}" for t in self.state["threats"]]
        params["gt"] = "|".join(threats) if threats else ""

        # Crops: "x:y:stage"
        crops = [f"{cr['x']}:{cr.get('y', 24)}:{cr['stage']}" for cr in self.state["world"]["crops"]]
        params["gcr"] = "|".join(crops) if crops else ""

        # Pond active flag
        params["gpond"] = "true" if self.state["world"].get("pond_active", False) else "false"

        params["gactive"] = "true"
        return params


# Global game engine instance (initialized lazily)
_game_engine = None


def _get_game_engine():
    """Get or create the global game engine."""
    global _game_engine
    if _game_engine is None:
        _game_engine = GameEngine()
    return _game_engine


def render_pixlet(sensor_data, weather_data, config=None, game_params=None):
    """Invoke pixlet render with sensor data as config params. Returns path to .webp."""
    now = datetime.now()
    seasonal = ""
    if config:
        seasonal = config.get("seasonal", {}).get("override", "")

    cmd = [
        "pixlet", "render", str(STAR_FILE),
        "-o", str(WEBP_OUTPUT),
        f"battery_pct={sensor_data.get('battery_pct', '0')}",
        f"solar_power={sensor_data.get('solar_power', '0')}",
        f"load_power={sensor_data.get('load_power', '0')}",
        f"grid_power={sensor_data.get('grid_power', '0')}",
        f"grid_status={sensor_data.get('grid_status', 'on')}",
        f"weather_icon={weather_data.get('icon', 'clear-day')}",
        f"temperature={weather_data.get('temperature', '')}",
        f"is_night={weather_data.get('is_night', 'false')}",
        f"cloud_cover={weather_data.get('cloud_cover', '0')}",
        f"sun_elevation={weather_data.get('sun_elevation', '0')}",
        f"month={now.month}",
        f"day={now.day}",
        f"hour={now.hour}",
        f"seasonal={seasonal}",
    ]

    # Append game engine params if active
    if game_params:
        for key, value in game_params.items():
            cmd.append(f"{key}={value}")

    logger.info("Running: %s", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

    if result.returncode != 0:
        logger.error("Pixlet render failed: %s", result.stderr)
        return None

    if not WEBP_OUTPUT.exists():
        logger.error("Pixlet did not produce output file")
        return None

    logger.info("Rendered %s (%d bytes)", WEBP_OUTPUT, WEBP_OUTPUT.stat().st_size)
    return WEBP_OUTPUT


def push_to_tidbyt(webp_path, config):
    """Push rendered WebP to Tidbyt via its cloud API."""
    tidbyt_config = config["tidbyt"]
    device_id = tidbyt_config["device_id"]
    api_token = tidbyt_config["api_token"]
    installation_id = tidbyt_config.get("installation_id", "powerwall")

    with open(webp_path, "rb") as f:
        image_data = base64.b64encode(f.read()).decode("utf-8")

    url = f"{TIDBYT_API_BASE}/{device_id}/push"
    headers = {
        "Authorization": f"Bearer {api_token}",
        "Content-Type": "application/json",
    }
    payload = {
        "image": image_data,
        "installationID": installation_id,
        "background": True,
    }

    resp = requests.post(url, json=payload, headers=headers, timeout=15)

    if 200 <= resp.status_code < 300:
        logger.info("Pushed to Tidbyt successfully (%d)", resp.status_code)
    else:
        logger.error("Tidbyt push failed (%d): %s", resp.status_code, resp.text)


def run_once(config):
    """Single fetch-render-push cycle."""
    logger.info("--- Starting update cycle ---")

    # Reuse one session for all HA requests (sensors + weather)
    session = _build_ha_session(config)

    # Fetch sensor data from HA
    sensor_data = fetch_all_sensors(session, config)
    logger.info("Sensor data: %s", sensor_data)

    # Fetch weather (reuses session if provider is homeassistant)
    weather_data = fetch_weather(session, config)
    logger.info("Weather: %s", weather_data)

    session.close()

    # Run game engine tick
    engine = _get_game_engine()
    game_params = engine.tick(sensor_data, weather_data)

    # Render via Pixlet
    webp_path = render_pixlet(sensor_data, weather_data, config, game_params)
    if webp_path is None:
        logger.error("Render failed, skipping push")
        return False

    # Push to Tidbyt
    push_to_tidbyt(webp_path, config)
    return True


# ---------------------------------------------------------------------------
# WebSocket real-time mode
# ---------------------------------------------------------------------------

def _build_watched_entities(config):
    """Build set of entity IDs to watch via WebSocket."""
    watched = set(config["home_assistant"]["sensors"].values())
    weather_config = config.get("weather", {})
    if weather_config.get("provider", "pirateweather") == "homeassistant":
        watched.add(weather_config.get("entity_id", "weather.home"))
        watched.add("sun.sun")
    return watched


def _cache_to_render_data(cache, config):
    """Convert the entity state cache into sensor_data + weather_data dicts."""
    sensors = config["home_assistant"]["sensors"]
    sensor_data = {}
    for metric, entity_id in sensors.items():
        entry = cache.get(entity_id)
        if entry is None:
            sensor_data[metric] = "0"
            continue
        state = entry.get("state", "0")
        sensor_data[metric] = "0" if state in ("unavailable", "unknown") else state

    # Weather data
    weather_config = config.get("weather", {})
    provider = weather_config.get("provider", "pirateweather")

    if provider == "homeassistant":
        weather_entity = weather_config.get("entity_id", "weather.home")
        w_entry = cache.get(weather_entity, {})
        condition = w_entry.get("state", "sunny")
        if condition in ("unavailable", "unknown"):
            condition = "sunny"

        sun_entry = cache.get("sun.sun", {})
        is_night = sun_entry.get("state") == "below_horizon"
        sun_elevation = float(sun_entry.get("attributes", {}).get("elevation", 0))

        attrs = w_entry.get("attributes", {})
        temp = attrs.get("temperature")

        if is_night and condition in HA_NIGHT_OVERRIDES:
            icon = HA_NIGHT_OVERRIDES[condition]
        else:
            icon = HA_CONDITION_MAP.get(condition, "cloudy")

        if temp is not None:
            temp = str(int(round(float(temp))))
        else:
            temp = ""

        cloud_cover = attrs.get("cloud_coverage", attrs.get("cloudiness", 0))
        if cloud_cover is None:
            cloud_cover = 0

        weather_data = {
            "icon": icon, "temperature": temp, "is_night": str(is_night).lower(),
            "cloud_cover": str(int(cloud_cover)), "sun_elevation": str(round(sun_elevation, 1)),
        }
    else:
        # Pirate Weather: not available via WS, use cached REST result
        weather_data = cache.get("_weather_pirate", dict(DEFAULT_WEATHER))

    return sensor_data, weather_data


def _do_render_push(cache, config):
    """Render and push using cached state."""
    sensor_data, weather_data = _cache_to_render_data(cache, config)
    logger.info("WS render: sensors=%s weather=%s", sensor_data, weather_data)

    # Run game engine tick
    engine = _get_game_engine()
    game_params = engine.tick(sensor_data, weather_data)

    webp_path = render_pixlet(sensor_data, weather_data, config, game_params)
    if webp_path is None:
        logger.error("Render failed, skipping push")
        return
    push_to_tidbyt(webp_path, config)


def _initial_fetch_to_cache(config):
    """Do a full REST fetch and populate the cache. Returns cache dict."""
    cache = {}
    session = _build_ha_session(config)

    # Fetch all sensor entities
    for entity_id in config["home_assistant"]["sensors"].values():
        try:
            data = fetch_ha_entity(session, entity_id)
            cache[entity_id] = {"state": data.get("state", "0"), "attributes": data.get("attributes", {})}
        except requests.RequestException as e:
            logger.error("Initial fetch %s failed: %s", entity_id, e)
            cache[entity_id] = {"state": "0", "attributes": {}}

    # Fetch weather + sun entities if using HA weather
    weather_config = config.get("weather", {})
    if weather_config.get("provider", "pirateweather") == "homeassistant":
        for eid in [weather_config.get("entity_id", "weather.home"), "sun.sun"]:
            try:
                data = fetch_ha_entity(session, eid)
                cache[eid] = {"state": data.get("state", ""), "attributes": data.get("attributes", {})}
            except requests.RequestException as e:
                logger.error("Initial fetch %s failed: %s", eid, e)
                cache[eid] = {"state": "", "attributes": {}}
    else:
        # Pirate Weather: fetch once via REST, store in cache
        cache["_weather_pirate"] = fetch_weather_pirate(config)

    session.close()
    return cache


try:
    import websockets
except ImportError:
    websockets = None  # Only needed for WebSocket mode


async def _ws_authenticate(ws, token):
    """Handle HA WebSocket authentication handshake."""
    msg = json.loads(await ws.recv())
    if msg.get("type") != "auth_required":
        raise RuntimeError(f"Expected auth_required, got {msg.get('type')}")

    await ws.send(json.dumps({"type": "auth", "access_token": token}))

    msg = json.loads(await ws.recv())
    if msg.get("type") == "auth_ok":
        logger.info("WebSocket authenticated (HA %s)", msg.get("ha_version", "?"))
        return
    raise RuntimeError(f"Auth failed: {msg}")


async def _ws_subscribe(ws):
    """Subscribe to state_changed events. Returns subscription ID."""
    sub_id = 1
    await ws.send(json.dumps({
        "type": "subscribe_events",
        "event_type": "state_changed",
        "id": sub_id,
    }))
    msg = json.loads(await ws.recv())
    if msg.get("success"):
        logger.info("Subscribed to state_changed events (id=%d)", sub_id)
    else:
        raise RuntimeError(f"Subscribe failed: {msg}")
    return sub_id


async def ws_loop(config):
    """Main WebSocket event loop with auto-reconnect."""
    if websockets is None:
        logger.error("websockets package required for WebSocket mode: pip install websockets")
        sys.exit(1)

    ha_config = config["home_assistant"]
    ha_url = ha_config["url"].rstrip("/")
    token = ha_config["token"]
    watched = _build_watched_entities(config)
    min_push_interval = 5  # seconds

    # Use ws:// or wss:// matching http:// or https://
    ws_url = ha_url.replace("http://", "ws://").replace("https://", "wss://") + "/api/websocket"

    backoff = 2
    max_backoff = 30

    while True:
        # Initial REST fetch + render + push
        logger.info("--- WebSocket mode: initial REST fetch ---")
        cache = _initial_fetch_to_cache(config)
        _do_render_push(cache, config)
        last_push = time.monotonic()

        try:
            logger.info("Connecting to %s", ws_url)
            async with websockets.connect(ws_url) as ws:
                await _ws_authenticate(ws, token)
                await _ws_subscribe(ws)
                backoff = 2  # reset on successful connection

                pending_update = False
                async for raw in ws:
                    msg = json.loads(raw)
                    if msg.get("type") != "event":
                        continue

                    event_data = msg.get("event", {}).get("data", {})
                    entity_id = event_data.get("entity_id")
                    if entity_id not in watched:
                        continue

                    new_state = event_data.get("new_state", {})
                    cache[entity_id] = {
                        "state": new_state.get("state", ""),
                        "attributes": new_state.get("attributes", {}),
                    }
                    logger.info("WS update: %s = %s", entity_id, new_state.get("state"))

                    # Throttled render + push
                    elapsed = time.monotonic() - last_push
                    if elapsed >= min_push_interval:
                        _do_render_push(cache, config)
                        last_push = time.monotonic()
                        pending_update = False
                    else:
                        pending_update = True

                # If we exit the loop with pending updates, flush them
                if pending_update:
                    _do_render_push(cache, config)

        except (websockets.ConnectionClosed, ConnectionRefusedError, OSError) as e:
            logger.warning("WebSocket disconnected: %s. Retrying in %ds...", e, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, max_backoff)
        except RuntimeError as e:
            if "Auth failed" in str(e):
                logger.error("WebSocket auth failed — check your HA token. Exiting.")
                sys.exit(1)
            logger.error("WebSocket error: %s. Retrying in %ds...", e, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, max_backoff)


def main():
    config = load_config()
    mode = config.get("schedule", {}).get("mode", "polling")
    once = "--once" in sys.argv

    if once:
        success = run_once(config)
        sys.exit(0 if success else 1)

    if mode == "websocket":
        logger.info("Starting WebSocket real-time mode")
        asyncio.run(ws_loop(config))
    else:
        interval = config.get("schedule", {}).get("interval_seconds", 15)
        logger.info("Starting polling loop with %ds interval", interval)
        while True:
            try:
                run_once(config)
            except Exception:
                logger.exception("Unexpected error in update cycle")

            logger.info("Sleeping %ds until next update", interval)
            time.sleep(interval)


if __name__ == "__main__":
    main()
