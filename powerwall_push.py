#!/usr/bin/env python3
"""Orchestrator: fetch Powerwall data from HA + weather, render via Pixlet,
push to Tidbyt. Supports Pirate Weather API or Home Assistant weather entities
(e.g. Met.no / Meteorologisk institutt)."""

import base64
import logging
import os
import subprocess
import sys
import time
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
    "lightning": "rain",
    "lightning-rainy": "rain",
    "exceptional": "cloudy",
}


def fetch_weather(session, config):
    """Fetch weather using the configured provider."""
    weather_config = config.get("weather", {})
    provider = weather_config.get("provider", "pirateweather")

    if provider == "homeassistant":
        return fetch_weather_ha(session, config)
    return fetch_weather_pirate(config)


def _is_night_ha(session):
    """Check HA's sun.sun entity to determine if it's nighttime."""
    try:
        data = fetch_ha_entity(session, "sun.sun")
        is_night = data.get("state") == "below_horizon"
        logger.info("Sun state: %s (is_night=%s)", data.get("state"), is_night)
        return is_night
    except requests.RequestException:
        logger.warning("Could not fetch sun.sun, assuming daytime")
        return False


# HA conditions that should flip to their night variant when sun is below horizon
HA_NIGHT_OVERRIDES = {
    "sunny": "clear-night",
    "partlycloudy": "partly-cloudy-night",
}


def fetch_weather_ha(session, config):
    """Fetch current weather from a Home Assistant weather entity (e.g. Met.no)."""
    entity_id = config.get("weather", {}).get("entity_id", "weather.home")

    try:
        data = fetch_ha_entity(session, entity_id)
        condition = data.get("state", "sunny")

        if condition in ("unavailable", "unknown"):
            logger.warning("Weather entity %s is %s", entity_id, condition)
            return {"icon": "clear-day", "temperature": "", "is_night": "false"}

        is_night = _is_night_ha(session)

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

        logger.info("HA weather: condition=%s icon=%s temp=%s is_night=%s", condition, icon, temp, is_night)
        return {"icon": icon, "temperature": temp, "is_night": str(is_night).lower()}
    except requests.RequestException as e:
        logger.error("Failed to fetch HA weather (%s): %s", entity_id, e)
        return {"icon": "clear-day", "temperature": "", "is_night": "false"}


def fetch_weather_pirate(config):
    """Fetch current weather from Pirate Weather API."""
    weather_config = config.get("weather", {})
    api_key = weather_config.get("api_key", "")
    lat = weather_config.get("latitude", 0)
    lon = weather_config.get("longitude", 0)

    if not api_key:
        logger.warning("No Pirate Weather API key configured, skipping weather")
        return {"icon": "clear-day", "temperature": "", "is_night": "false"}

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
        return {"icon": icon, "temperature": temp, "is_night": str(is_night).lower()}
    except requests.RequestException as e:
        logger.error("Failed to fetch weather: %s", e)
        return {"icon": "clear-day", "temperature": "", "is_night": "false"}


def render_pixlet(sensor_data, weather_data):
    """Invoke pixlet render with sensor data as config params. Returns path to .webp."""
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

    if resp.status_code == 200:
        logger.info("Pushed to Tidbyt successfully")
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
    webp_path = render_pixlet(sensor_data, weather_data)
    if webp_path is None:
        logger.error("Render failed, skipping push")
        return False

    # Push to Tidbyt
    push_to_tidbyt(webp_path, config)
    return True


def main():
    config = load_config()
    interval = config.get("schedule", {}).get("interval_seconds", 120)
    once = "--once" in sys.argv

    if once:
        success = run_once(config)
        sys.exit(0 if success else 1)

    logger.info("Starting loop with %ds interval", interval)
    while True:
        try:
            run_once(config)
        except Exception:
            logger.exception("Unexpected error in update cycle")

        logger.info("Sleeping %ds until next update", interval)
        time.sleep(interval)


if __name__ == "__main__":
    main()
