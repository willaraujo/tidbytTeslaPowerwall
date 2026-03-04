# tidbytTeslaPowerwall

Turn your Tidbyt Gen2 into a live Tesla Powerwall monitor with animated weather.

Shows solar production, home usage, grid power, and battery level at a glance -- with ambient weather animations (rain drops, snowflakes, twinkling stars, drifting clouds, wind streaks) that reflect your actual local weather in real time.

## What You Need

- **Tidbyt Gen2** -- set up on your wifi with the Tidbyt phone app
- **Home Assistant** -- running on your network with the Tesla Powerwall integration installed
- **A machine to run this script** -- Raspberry Pi, NAS, old laptop, or any always-on computer with Docker (or Python 3.11+)
- No weather API key needed (uses Home Assistant's built-in weather)

## How It Works

```
Home Assistant  -->  Python Script  -->  Pixlet Render  -->  Tidbyt Cloud API  -->  Your Tidbyt
  (Powerwall)                           (64x32 animated)
  (Weather)
```

Every 2 minutes the script:
1. Fetches your Powerwall sensor data from Home Assistant
2. Fetches current weather from Home Assistant (or optionally Pirate Weather)
3. Renders an animated 64x32 display using Pixlet
4. Pushes the result to your Tidbyt via its cloud API

## Display Layout

```
 [Solar]    [House]    [Grid]
  1.92       0.78       1.12
   kW     >>>  37%  <<<  kW
```

- **Column 1**: Solar panel icon + solar production (kW)
- **Column 2**: House icon + home consumption + battery %
- **Column 3**: Grid icon + grid power (import/export)
- **Animated dots** flow between columns showing energy direction
- **Weather animations** play behind the data (rain, snow, sun glow, stars, clouds, wind, fog)

At night, twinkling stars are automatically layered behind weather effects.

---

## Setup (Step by Step)

### Step 1: Get your Home Assistant token

1. Open Home Assistant in a browser: `http://<your-HA-IP>:8123`
2. Click your profile picture (bottom-left corner)
3. Scroll all the way down to **Long-Lived Access Tokens**
4. Click **Create Token**, name it `tidbyt`
5. Copy the token immediately -- you won't be able to see it again

### Step 2: Find your Powerwall sensor entity IDs

1. In Home Assistant, go to **Developer Tools** > **States** tab
2. In the filter box, type `powerwall` (or `tesla` or `battery`)
3. Find and write down these 5 entity IDs:

| What | Example entity ID |
|------|-------------------|
| Battery % | `sensor.powerwall_battery` |
| Solar production | `sensor.powerwall_solar_power` |
| Home consumption | `sensor.powerwall_load_power` |
| Grid power | `sensor.powerwall_grid_power` |
| Grid status | `binary_sensor.powerwall_grid_status` |

Your exact names may differ depending on your HA integration (e.g. `sensor.tesla_wall_connector_...`, `sensor.energy_site_...`).

### Step 3: Find your weather entity ID

1. Still in **Developer Tools** > **States**
2. Filter for `weather`
3. You'll see something like `weather.home` or `weather.forecast_home`
4. Write it down -- no API key needed, this uses HA's built-in Met.no integration

### Step 4: Get your Tidbyt credentials

1. Open the **Tidbyt app** on your phone
2. Tap your Tidbyt device
3. Go to **Settings** > **General** > scroll down to **Developer Info**
4. Copy your **Device ID** and **API Token**

### Step 5: Clone and configure

```bash
git clone https://github.com/willaraujo/tidbytTeslaPowerwall.git
cd tidbytTeslaPowerwall
cp config.example.yaml config.yaml
```

Edit `config.yaml` and fill in your values:

```yaml
home_assistant:
  url: "http://192.168.1.100:8123"          # your HA IP address
  token: "eyJhbGci...your_long_token..."     # from Step 1
  sensors:
    battery_pct: "sensor.powerwall_battery"           # from Step 2
    solar_power: "sensor.powerwall_solar_power"       # from Step 2
    load_power: "sensor.powerwall_load_power"         # from Step 2
    grid_power: "sensor.powerwall_grid_power"         # from Step 2
    grid_status: "binary_sensor.powerwall_grid_status"  # from Step 2

weather:
  provider: "homeassistant"
  entity_id: "weather.home"   # from Step 3

tidbyt:
  device_id: "your-device-id-here"    # from Step 4
  api_token: "your-api-token-here"    # from Step 4
  installation_id: "powerwall"

schedule:
  interval_seconds: 120   # updates every 2 minutes
```

### Step 6: Run it

**Docker (recommended):**

```bash
docker compose up -d
```

Check the logs to make sure it's working:

```bash
docker compose logs -f
```

You should see output like:

```
INFO - HA weather: condition=sunny icon=clear-day temp=72 is_night=false
INFO - Sun state: above_horizon (is_night=False)
INFO - Successfully pushed to Tidbyt
```

**Without Docker:**

Install Pixlet:
```bash
# Linux (x86_64)
curl -LO https://github.com/tidbyt/pixlet/releases/download/v0.34.0/pixlet_0.34.0_linux_amd64.tar.gz
tar -xzf pixlet_0.34.0_linux_amd64.tar.gz
sudo mv pixlet /usr/local/bin/

# macOS (Apple Silicon)
curl -LO https://github.com/tidbyt/pixlet/releases/download/v0.34.0/pixlet_0.34.0_darwin_arm64.tar.gz
tar -xzf pixlet_0.34.0_darwin_arm64.tar.gz
sudo mv pixlet /usr/local/bin/
```

Install Python dependencies and run:
```bash
pip install -r requirements.txt
python powerwall_push.py
```

Or run once via cron (every 2 minutes):
```
*/2 * * * * cd /path/to/tidbytTeslaPowerwall && python powerwall_push.py --once
```

---

## Local Preview

Test the display without pushing to your Tidbyt:

```bash
pixlet serve powerwall_tidbyt.star \
  -c battery_pct=37 \
  -c solar_power=1920 \
  -c load_power=784 \
  -c grid_power=-1120 \
  -c grid_status=on \
  -c weather_icon=rain \
  -c temperature=72 \
  -c is_night=true
```

Then open `http://localhost:8080` in your browser.

## Alternative Weather: Pirate Weather

If you prefer not to use Home Assistant's weather, you can use Pirate Weather instead:

1. Sign up at [pirateweather.net](https://pirateweather.net/) (free, 10,000 calls/day)
2. Get your API key
3. Replace the `weather:` block in `config.yaml`:

```yaml
weather:
  provider: "pirateweather"
  api_key: "your_pirate_weather_api_key"
  latitude: 28.5383
  longitude: -81.3792
```

## Weather Animations

At nighttime, twinkling stars are automatically layered behind all weather effects. Day/night detection uses HA's built-in `sun.sun` entity (no config needed).

| Animation | Night variant | Pirate Weather icon | HA condition |
|-----------|--------------|---------------------|--------------|
| Yellow glow pixels | -- | `clear-day` | `sunny` (day) |
| Twinkling stars | -- | `clear-night` | `sunny` (night) |
| Blue rain drops | Stars + rain | `rain` | `rainy`, `pouring`, `lightning`, `lightning-rainy` |
| White snowflakes | Stars + snow | `snow` | `snowy` |
| Gray drifting clouds | Stars + clouds | `cloudy` | `cloudy` |
| Sun glow + cloud | -- | `partly-cloudy-day` | `partlycloudy` (day) |
| Stars + cloud | -- | `partly-cloudy-night` | `partlycloudy` (night) |
| Horizontal wind streaks | Stars + wind | `wind` | `windy`, `windy-variant` |
| Gray drifting haze | Stars + fog | `fog` | `fog` |
| Rain drops | Stars + rain | `sleet` | `snowy-rainy`, `hail` |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| **"HA OFFLINE" in logs** | Check your HA URL and token. Make sure HA is reachable from where the script runs |
| **No weather animation** | Check your weather entity ID in HA > Developer Tools > States. Try `weather.forecast_home` if `weather.home` doesn't exist |
| **Tidbyt not updating** | Verify Device ID and API Token from the Tidbyt phone app. The machine needs internet access |
| **Docker can't reach HA** | Use your HA's LAN IP (e.g. `192.168.1.100`), not `localhost`. In Docker, localhost means the container itself |
| **Wrong sensor values** | Double-check entity IDs in HA Developer Tools > States -- copy them exactly |
| **Raspberry Pi build fails** | Add `--build-arg TARGETARCH=arm64` to your docker build command |
| **Night detection seems wrong** | Check `TZ` in `docker-compose.yml` -- change `America/New_York` to your timezone |
Plugin
