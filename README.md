# Powerwall Tidbyt Plugin

Tesla Powerwall 3 energy monitor for Tidbyt Gen2 with animated weather effects. Pulls data from Home Assistant and displays solar production, home usage, grid power, and battery level with ambient weather animations (rain, snow, sun, clouds, wind).

## How It Works

```
Home Assistant  ──►  Python Script  ──►  Pixlet Render  ──►  Tidbyt Push API  ──►  Tidbyt Gen2
Pirate Weather  ──►       │
```

1. Python fetches Powerwall sensor data from your Home Assistant REST API
2. Python fetches current weather from Pirate Weather API
3. Pixlet renders a 64x32 animated display with energy data + weather effects
4. The rendered WebP is pushed to your Tidbyt via its cloud API
5. Repeats every 2 minutes (configurable)

## Display Layout

Three-column layout based on the Tesla Solar Tidbyt community app:

- **Column 1**: Solar panel icon + solar production (kW)
- **Column 2**: House icon + home load + battery percentage
- **Column 3**: Grid icon + grid power (import/export)
- **Animated dots** show energy flow direction between columns
- **Weather animations** overlay the display (rain drops, snow, sun glow, stars, clouds, wind streaks)

## Prerequisites

- Tidbyt Gen2 connected via TRMNL (or standalone)
- Home Assistant with Tesla Powerwall integration (Tesla Custom Integration or official)
- [Pirate Weather](https://pirateweather.net/) free API key (for weather animations)
- Tidbyt Device ID and API Token (from Tidbyt app: Settings > Developer)
- Home Assistant long-lived access token

## Setup

### 1. Get Your Credentials

**Home Assistant Token:**
1. Go to your HA instance > Profile > Long-Lived Access Tokens
2. Create a new token and copy it

**Tidbyt API:**
1. Open the Tidbyt app on your phone
2. Go to Settings > Developer
3. Copy your Device ID and API Token

**Pirate Weather:**
1. Sign up at [pirateweather.net](https://pirateweather.net/)
2. Get your free API key (10,000 calls/day)

**Home Assistant Entity IDs:**
1. Go to HA > Developer Tools > States
2. Filter for "powerwall" or "tesla" or "battery"
3. Find your entity IDs for: battery %, solar power, load power, grid power, grid status

### 2. Configure

```bash
cp config.example.yaml config.yaml
```

Edit `config.yaml` with your values:

```yaml
home_assistant:
  url: "http://192.168.1.100:8123"
  token: "your_long_lived_access_token"
  sensors:
    battery_pct: "sensor.powerwall_battery"
    solar_power: "sensor.powerwall_solar_power"
    load_power: "sensor.powerwall_load_power"
    grid_power: "sensor.powerwall_grid_power"
    grid_status: "binary_sensor.powerwall_grid_status"

weather:
  provider: "pirateweather"
  api_key: "your_pirate_weather_api_key"
  latitude: 28.5383
  longitude: -81.3792

tidbyt:
  device_id: "your_tidbyt_device_id"
  api_token: "your_tidbyt_api_token"
  installation_id: "powerwall"

schedule:
  interval_seconds: 120
```

### 3. Run with Docker (Recommended)

```bash
docker compose up -d
```

View logs:
```bash
docker compose logs -f
```

### 4. Run Without Docker

Install [Pixlet](https://github.com/tidbyt/pixlet/releases):
```bash
curl -LO https://github.com/tidbyt/pixlet/releases/download/v0.34.0/pixlet_0.34.0_linux_amd64.tar.gz
tar -xzf pixlet_0.34.0_linux_amd64.tar.gz
sudo mv pixlet /usr/local/bin/
```

Install Python dependencies:
```bash
pip install -r requirements.txt
```

Run continuously:
```bash
python powerwall_push.py
```

Run once (for cron):
```bash
python powerwall_push.py --once
```

Cron example (every 2 minutes):
```
*/2 * * * * cd /path/to/trmnlTeslatidbyt && python powerwall_push.py --once
```

## Local Preview

Test the display layout without pushing to Tidbyt:

```bash
pixlet serve powerwall_tidbyt.star \
  -c battery_pct=37 \
  -c solar_power=1920 \
  -c load_power=784 \
  -c grid_power=-1120 \
  -c grid_status=on \
  -c weather_icon=rain \
  -c temperature=72
```

Then open `http://localhost:8080` in your browser.

## Weather Conditions

The plugin responds to these Pirate Weather conditions with ambient animations:

| Condition | Animation |
|-----------|-----------|
| `clear-day` | Yellow glow pixels pulsing in corners |
| `clear-night` | Twinkling star dots |
| `rain` | Blue drops falling across the display |
| `snow` | White dots drifting down with wobble |
| `cloudy` | Gray pixel clusters drifting horizontally |
| `partly-cloudy-day` | Sun glow + cloud drift |
| `partly-cloudy-night` | Stars + cloud drift |
| `wind` | Fast horizontal streaks |
| `fog` | Gray haze drifting slowly |
| `sleet` | Same as rain |

## Troubleshooting

- **"HA OFFLINE"**: Check your HA URL and token. Ensure HA is reachable from where the script runs.
- **No weather animation**: Verify your Pirate Weather API key and lat/lon coordinates.
- **Tidbyt not updating**: Check Device ID and API Token. The Tidbyt push API requires internet access.
- **Docker can't reach HA**: If HA is on the same host, use the host's LAN IP (not `localhost`).
