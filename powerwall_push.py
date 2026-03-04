#!/usr/bin/env python3
"""Orchestrator: fetch Powerwall data from HA + weather from Pirate Weather,
render via Pixlet, push to Tidbyt."""

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


def fetch_ha_sensor(session, ha_url, token, entity_id):
    """Fetch a single sensor state from Home Assistant REST API."""
    url = f"{ha_url.rstrip('/')}/api/states/{entity_id}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    resp = session.get(url, headers=headers, timeout=10)
    resp.raise_for_status()
    data = resp.json()
    state = data.get("state", "unavailable")

    if state in ("unavailable", "unknown"):
        logger.warning("Sensor %s is %s", entity_id, state)
        return None

    return state


def fetch_all_sensors(config):
    """Fetch all Powerwall sensors from HA. Returns dict of metric -> value."""
    ha_config = config["home_assistant"]
    ha_url = ha_config["url"]
    token = ha_config["token"]
    sensors = ha_config["sensors"]

    results = {}
    session = requests.Session()

    for metric, entity_id in sensors.items():
        try:
            state = fetch_ha_sensor(session, ha_url, token, entity_id)
            if state is not None:
                results[metric] = state
            else:
                results[metric] = "0"
        except requests.RequestException as e:
            logger.error("Failed to fetch %s (%s): %s", metric, entity_id, e)
            results[metric] = "0"

    session.close()
    return results


def fetch_weather(config):
    """Fetch current weather from Pirate Weather API."""
    weather_config = config.get("weather", {})
    api_key = weather_config.get("api_key", "")
    lat = weather_config.get("latitude", 0)
    lon = weather_config.get("longitude", 0)

    if not api_key:
        logger.warning("No Pirate Weather API key configured, skipping weather")
        return {"icon": "clear-day", "temperature": ""}

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
        return {"icon": icon, "temperature": temp}
    except requests.RequestException as e:
        logger.error("Failed to fetch weather: %s", e)
        return {"icon": "clear-day", "temperature": ""}


def render_pixlet(sensor_data, weather_data):
    """Invoke pixlet render with sensor data as config params. Returns path to .webp."""
    cmd = [
        "pixlet", "render", str(STAR_FILE),
        "-o", str(WEBP_OUTPUT),
        "-c", f"battery_pct={sensor_data.get('battery_pct', '0')}",
        "-c", f"solar_power={sensor_data.get('solar_power', '0')}",
        "-c", f"load_power={sensor_data.get('load_power', '0')}",
        "-c", f"grid_power={sensor_data.get('grid_power', '0')}",
        "-c", f"grid_status={sensor_data.get('grid_status', 'on')}",
        "-c", f"weather_icon={weather_data.get('icon', 'clear-day')}",
        "-c", f"temperature={weather_data.get('temperature', '')}",
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

    # Fetch sensor data from HA
    sensor_data = fetch_all_sensors(config)
    logger.info("Sensor data: %s", sensor_data)

    # Fetch weather
    weather_data = fetch_weather(config)
    logger.info("Weather: %s", weather_data)

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
