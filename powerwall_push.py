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


def render_pixlet(sensor_data, weather_data, config=None):
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

    # Render via Pixlet
    webp_path = render_pixlet(sensor_data, weather_data, config)
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

    webp_path = render_pixlet(sensor_data, weather_data, config)
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
