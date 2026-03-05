"""
Applet: Powerwall Weather
Summary: Tesla Powerwall + Weather
Description: Energy monitor for Tesla Powerwall 3. At night, the solar column becomes a weather display.
Author: willaraujo
"""

load("encoding/base64.star", "base64")
load("render.star", "render")
load("animation.star", "animation")

# Animated energy flow dots (GIF)
DOTS_LTR = base64.decode(
    "R0lGODlhCgAFAIEAAP/RGwAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJCgABACwAAAAA" +
    "CgAFAAAIFAADCBxIsGBBAAIRBlCo0KDDggEBACH5BAkKAAEALAEAAgAHAAEAgf/RGwAAAAAAAAAA" +
    "AAgIAAEECCCQYEAAIfkECQoAAQAsAgACAAcAAQCB/9EbAAAAAAAAAAAACAgAAQQIIJBgQAA7"
)

DOTS_RTL = base64.decode(
    "R0lGODlhCgAFAIABAP/RGwAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJDwABACwAAAAACgAFAAAC" +
    "CIyPqQHWvKIqACH5BAkPAAEALAAAAAAKAAUAAAIIjI+pYByuYiwAIfkECQ8AAQAsAAAAAAoABQAA" +
    "AgmMj5lgHO6UTAUAOw=="
)

# Weather colors for column-1 animations
RAIN_COLOR = "#4488CC"
SNOW_COLOR = "#CCDDFF"
STAR_COLOR = "#8888AA"
CLOUD_COLOR = "#3a3a3a"
MOON_COLOR = "#CCCC88"
WIND_COLOR = "#667788"
FOG_COLOR = "#333333"

# Battery bar gradient colors (8 segments, red -> green)
BATT_GRADIENT = [
    "#ff0000",
    "#ff4400",
    "#ff8800",
    "#ffcc00",
    "#cccc00",
    "#88cc00",
    "#44cc00",
    "#00cc00",
]
BATT_OUTLINE = "#555555"
BATT_EMPTY = "#111111"

# Icon colors
SOLAR_BLUE = "#1a3a5c"
SOLAR_GRID = "#3388cc"
SOLAR_GRAY = "#888888"
HOUSE_ROOF = "#cc4444"
HOUSE_WALL = "#ddaa55"
HOUSE_WINDOW = "#66ccff"
HOUSE_DOOR = "#885522"
HOUSE_CHIMNEY = "#aa6633"
HOUSE_FOUNDATION = "#777777"
GRID_METAL = "#888888"
GRID_DARK = "#666666"

# Power thresholds (watts)
SOLAR_MAX_W = 5000.0       # Solar power at full sun intensity
LOAD_LOW_W = 2000          # Load below this = green
LOAD_HIGH_W = 5000         # Load above this = red (between = amber)
GRID_DEADBAND_W = 10       # Grid power within +/- this = idle (no flow)
POWER_ZERO_W = 50          # Power below this displays as "0"

# Dynamic colors for power status
COLOR_GREEN = "#00cc00"
COLOR_AMBER = "#ffd11a"
COLOR_RED_WARN = "#ff4400"
COLOR_RED = "#ff0000"
COLOR_GRAY = "#666666"

# Sun intensity color endpoints
SUN_DIM_CORE = "#aa7700"
SUN_BRIGHT_CORE = "#ffdd00"
SUN_DIM_RAY = "#996600"
SUN_BRIGHT_RAY = "#ffbb00"

# Weather dim factors (how much weather reduces sun intensity)
WEATHER_DIM_HEAVY = 0.3    # cloudy, overcast, fog
WEATHER_DIM_PRECIP = 0.4   # rain, sleet, snow
WEATHER_DIM_PARTIAL = 0.7  # partly-cloudy

# Weather condition groups (for matching in multiple places)
WEATHER_HEAVY = ("cloudy", "overcast", "fog")
WEATHER_PRECIP = ("rain", "sleet", "snow")
WEATHER_RAIN = ("rain", "sleet")
WEATHER_CLOUD_FULL = ("cloudy", "overcast")

# Character colors (living world)
CHAR_SKIN = "#ffcc88"
CHAR_PARENT1_SHIRT = "#4488cc"
CHAR_PARENT2_SHIRT = "#cc4444"
CHAR_KID_SHIRT = "#44cc44"
CHAR_PANTS = "#555555"
CHAR_SHOES = "#333333"
DOG_COLOR = "#aa7744"
CAT_COLOR = "#888888"

def main(config):
    """Render 3-column energy dashboard: Solar/Weather | Home/Battery | Grid.
    Animated energy flow dots show power direction between columns."""
    battery_pct = int(config.get("battery_pct", "0"))
    solar_power = float(config.get("solar_power", "0"))
    load_power = float(config.get("load_power", "0"))
    grid_power = float(config.get("grid_power", "0"))
    grid_status = config.get("grid_status", "on")
    weather_icon = config.get("weather_icon", "clear-day")
    sun_elevation = float(config.get("sun_elevation", "0"))

    # Column 1: solar panel visible only when actively generating during day
    is_night = config.get("is_night", "false") == "true"
    show_panel = (not is_night) and solar_power > POWER_ZERO_W

    if show_panel:
        col1_icon = build_solar_icon(solar_power, weather_icon, sun_elevation)
        solar_flow = 1
    else:
        solar_flow = 0

    # Determine grid flow direction
    if grid_power < -GRID_DEADBAND_W:
        grid_flow = 1   # exporting to grid
    elif grid_power > GRID_DEADBAND_W:
        grid_flow = -1  # importing from grid
    else:
        grid_flow = 0

    # Format power values
    solar_text = format_power(solar_power)
    load_text = format_power(load_power)
    grid_text = format_power(grid_power)

    # Column 1: two modes
    if show_panel:
        # SOLAR MODE: icon + power text + "kW"
        solar_color = COLOR_GREEN if solar_power > 0 else COLOR_GRAY
        col1 = render.Column(
            main_align = "space_between",
            cross_align = "center",
            children = [
                col1_icon,
                render.Text(content = solar_text, height = 8, font = "tb-8", color = solar_color),
                render.Text(content = "kW", height = 8, font = "tb-8", color = solar_color),
            ],
        )
    else:
        # WEATHER MODE: full-height scene, NO text
        col1 = build_weather_scene(weather_icon, sun_elevation, is_night)

    # Column 2: Home + battery bar (load color = green/amber/red by usage)
    if load_power < LOAD_LOW_W:
        load_color = COLOR_GREEN
    elif load_power < LOAD_HIGH_W:
        load_color = COLOR_AMBER
    else:
        load_color = COLOR_RED_WARN

    # House icon + seasonal scene items in slot-based layout:
    # [4px left scene] [16px house] [4px right scene] = 24px
    seasonal = get_seasonal_name(config)
    house_icon = build_house_icon(seasonal, is_night)
    left_scene = build_left_scene(seasonal)
    right_scene = build_right_scene(seasonal)
    bg_overlay, fg_overlay = build_full_overlay(seasonal)

    scene_row = render.Row(children = [left_scene, house_icon, right_scene])
    layers = []
    if bg_overlay:
        layers.append(bg_overlay)
    layers.append(scene_row)
    if fg_overlay:
        layers.append(fg_overlay)
    house_box = render.Box(width = 24, height = 16, child = render.Stack(children = layers))

    col2 = render.Column(
        main_align = "space_between",
        cross_align = "center",
        children = [
            house_box,
            render.Text(content = load_text, height = 8, font = "tb-8", color = load_color),
            render.Box(height = 8, child = build_battery_bar(battery_pct)),
        ],
    )

    # Column 3: Grid (blinking icon + "OFF" when grid is down)
    grid_down = grid_status.lower() != "on"
    if grid_down:
        grid_color = COLOR_RED
        grid_text = "OFF"
        grid_icon = animation.Transformation(
            child = build_grid_icon(),
            duration = 10,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
            ],
        )
    else:
        grid_color = COLOR_GREEN if grid_power < -GRID_DEADBAND_W else COLOR_AMBER
        grid_icon = build_grid_icon()

    col3 = render.Column(
        main_align = "space_between",
        cross_align = "center",
        children = [
            grid_icon,
            render.Text(content = grid_text, height = 8, font = "tb-8", color = grid_color),
            render.Text(content = "kW" if not grid_down else "", height = 8, font = "tb-8", color = grid_color),
        ],
    )

    # Energy flow dots row (dots are 10px wide, centered at column boundaries)
    # Col boundaries: col1|col2 at x=20, col2|col3 at x=44
    dots = [render.Box(width = 15)]

    # Solar -> Home flow dots (centered at x=20)
    if solar_flow:
        dots.append(render.Image(src = DOTS_LTR))
    else:
        dots.append(render.Box(width = 10))

    dots.append(render.Box(width = 14))

    # Grid <-> Home flow dots (centered at x=44)
    if grid_flow == -1:
        dots.append(render.Image(src = DOTS_RTL))
    elif grid_flow == 1:
        dots.append(render.Image(src = DOTS_LTR))
    else:
        dots.append(render.Box(width = 10))

    # Main display: layered stack
    # Layer 0: sky background (night), Layer 1: columns, Layer 2: life, Layer 3: weather, Layer 4: dots
    sky_bg = build_sky_background(is_night)
    life_overlay = build_life_overlay(config)
    weather_overlay = build_weather_overlay(weather_icon, is_night)

    display_children = []
    if sky_bg:
        display_children.append(sky_bg)

    display_children.append(
        render.Row(
            expanded = True,
            children = [
                render.Box(width = 20, child = col1),
                render.Box(width = 24, child = col2),
                render.Box(width = 20, child = col3),
            ],
        ),
    )

    if life_overlay:
        display_children.append(life_overlay)

    if weather_overlay:
        display_children.append(weather_overlay)

    display_children.append(
        render.Column(
            children = [
                render.Box(height = 7),
                render.Row(expanded = True, children = dots),
            ],
        ),
    )

    display = render.Stack(children = display_children)

    return render.Root(
        delay = 200,
        child = render.Padding(
            pad = (0, 1, 0, 0),
            child = display,
        ),
    )

# --- Pixel-art icons ---

def _hex02(n):
    """Zero-padded 2-digit hex. Starlark doesn't support %02x."""
    h = "%x" % n
    if len(h) < 2:
        h = "0" + h
    return h

def _lerp_color(c1, c2, t):
    """Interpolate between two hex colors. t=0.0 returns c1, t=1.0 returns c2."""
    r1 = int(c1[1:3], 16)
    g1 = int(c1[3:5], 16)
    b1 = int(c1[5:7], 16)
    r2 = int(c2[1:3], 16)
    g2 = int(c2[3:5], 16)
    b2 = int(c2[5:7], 16)
    r = int(r1 + (r2 - r1) * t)
    g = int(g1 + (g2 - g1) * t)
    b = int(b1 + (b2 - b1) * t)
    return "#" + _hex02(r) + _hex02(g) + _hex02(b)

def build_solar_icon(solar_power = 0, weather_icon = "clear-day", sun_elevation = 45.0):
    """Solar panel with dynamic sun + weather overlays, in 20x16 box.
    Sun brightness scales with solar_power. Sun Y position from elevation."""
    panel_color = SOLAR_BLUE
    grid_color = SOLAR_GRID

    # Map sun elevation to Y position (0=top, 7=near panel)
    sun_y = max(0, min(7, int(7 - (min(max(sun_elevation, 0.0), 90.0) / 90.0) * 7)))

    # Dynamic intensity from solar power (0.0 to 1.0)
    intensity = min(solar_power / SOLAR_MAX_W, 1.0) if solar_power > 0 else 0.0

    # Weather dims the sun
    weather_dim = 1.0
    if weather_icon in WEATHER_HEAVY:
        weather_dim = WEATHER_DIM_HEAVY
    elif weather_icon in WEATHER_PRECIP:
        weather_dim = WEATHER_DIM_PRECIP
    elif weather_icon == "partly-cloudy-day":
        weather_dim = WEATHER_DIM_PARTIAL
    effective = intensity * weather_dim

    # Dynamic sun colors — dim amber to bright yellow
    core_color = _lerp_color(SUN_DIM_CORE, SUN_BRIGHT_CORE, effective)
    ray_color = _lerp_color(SUN_DIM_RAY, SUN_BRIGHT_RAY, effective)
    ray_count = int(effective * 8)
    ray_speed = max(40, 80 - int(effective * 40))

    # Build panel rows
    panel_rows = []
    for row in range(2):
        cell_row = render.Row(children = [
            render.Box(width = 1, height = 3, color = grid_color),
            render.Box(width = 3, height = 3, color = panel_color),
            render.Box(width = 1, height = 3, color = grid_color),
            render.Box(width = 3, height = 3, color = panel_color),
            render.Box(width = 1, height = 3, color = grid_color),
            render.Box(width = 3, height = 3, color = panel_color),
            render.Box(width = 1, height = 3, color = grid_color),
        ])
        panel_rows.append(cell_row)
        if row == 0:
            panel_rows.append(render.Box(width = 13, height = 1, color = grid_color))
    panel = render.Column(children = panel_rows)

    # Build ray pixels (only show ray_count of them), offset by sun_y
    all_ray_pads = [
        (1, 0), (3, 0), (0, 1), (4, 1), (0, 3), (4, 3), (1, 4), (3, 4),
    ]
    ray_children = []
    for i in range(ray_count):
        px, py = all_ray_pads[i]
        ray_children.append(
            render.Padding(pad = (px, py + sun_y, 0, 0), child = render.Box(width = 1, height = 1, color = ray_color)),
        )

    children = [
        # Sun core (3x3, dynamic color), Y position from elevation
        render.Padding(pad = (1, 1 + sun_y, 0, 0), child = render.Box(width = 3, height = 3, color = core_color)),
    ]

    # Add animated rays if any
    if ray_children:
        sun_rays = animation.Transformation(
            child = render.Stack(children = ray_children),
            duration = ray_speed,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
            ],
        )
        children.append(sun_rays)

    # Panel + structure with rise-from-ground animation
    panel_group = render.Stack(children = [
        render.Padding(pad = (4, 4, 0, 0), child = panel),
        render.Padding(pad = (9, 11, 0, 0), child = render.Box(width = 2, height = 2, color = SOLAR_GRAY)),
        render.Padding(pad = (7, 13, 0, 0), child = render.Box(width = 6, height = 1, color = SOLAR_GRAY)),
    ])
    children.append(animation.Transformation(
        child = panel_group,
        duration = 30,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 0.3), animation.Translate(0, 8)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(1.0, 1.0), animation.Translate(0, 0)]),
        ],
    ))

    # Layer weather effects on top
    if "cloud" in weather_icon or weather_icon == "overcast":
        children.extend(_solar_cloud_overlay(weather_icon))
    if weather_icon in WEATHER_RAIN:
        children.extend(_solar_rain_overlay())
    if weather_icon == "snow":
        children.extend(_solar_snow_overlay())
    if weather_icon == "wind":
        children.extend(_solar_wind_overlay())
    if weather_icon == "fog":
        children.extend(_solar_fog_overlay())

    return render.Box(width = 20, height = 16, child = render.Stack(children = children))

def _solar_cloud_overlay(weather_icon):
    """Drifting puffy cloud(s) over solar panel. More clouds for heavier overcast."""
    children = []
    # First cloud — always present for any cloud condition
    children.append(
        animation.Transformation(
            child = render.Padding(pad = (0, 0, 0, 0), child = _cloud_shape(size = "medium")),
            duration = 80,
            delay = 0,
            direction = "normal",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-12, 0)], curve = "linear"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(24, 0)]),
            ],
        ),
    )
    # Second cloud for full overcast/cloudy
    if weather_icon in WEATHER_CLOUD_FULL:
        children.append(
            animation.Transformation(
                child = render.Padding(pad = (0, 5, 0, 0), child = _cloud_shape(color = "#555555", size = "small")),
                duration = 60,
                delay = 30,
                direction = "normal",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-10, 0)], curve = "linear"),
                    animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(24, 0)]),
                ],
            ),
        )
    return children

def _solar_rain_overlay():
    """Rain drops falling over the solar panel area."""
    drops = []
    for x, delay in zip([3, 10, 16], [0, 8, 16]):
        drops.append(
            render.Padding(
                pad = (x, 0, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 1, height = 2, color = RAIN_COLOR),
                    duration = 30,
                    delay = delay,
                    direction = "normal",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, -3)], curve = "linear"),
                        animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(0, 18)]),
                    ],
                ),
            ),
        )
    # Puffy cloud at top
    drops.append(render.Padding(pad = (3, 0, 0, 0), child = _cloud_shape(size = "small")))
    return drops

def _solar_snow_overlay():
    """Snowflakes drifting over the solar panel area."""
    flakes = []
    for x, delay in zip([2, 10, 16], [0, 12, 24]):
        flakes.append(
            render.Padding(
                pad = (x, 0, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 1, height = 1, color = SNOW_COLOR),
                    duration = 50,
                    delay = delay,
                    direction = "normal",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, -2)], curve = "linear"),
                        animation.Keyframe(percentage = 0.5, transforms = [animation.Translate(2, 8)], curve = "ease_in_out"),
                        animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(-1, 18)]),
                    ],
                ),
            ),
        )
    # Puffy cloud at top
    flakes.append(render.Padding(pad = (3, 0, 0, 0), child = _cloud_shape(size = "small")))
    return flakes

def _solar_wind_overlay():
    """Wind streaks blowing across the solar area."""
    streaks = []
    for y, delay in zip([3, 9], [0, 6]):
        streaks.append(
            animation.Transformation(
                child = render.Padding(pad = (0, y, 0, 0), child = render.Box(width = 4, height = 1, color = WIND_COLOR)),
                duration = 20,
                delay = delay,
                direction = "normal",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-5, 0)], curve = "linear"),
                    animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(22, 0)]),
                ],
            ),
        )
    return streaks

def _solar_fog_overlay():
    """Fog haze drifting over the solar area."""
    haze = []
    for y, delay in zip([2, 8], [0, 15]):
        haze.append(
            animation.Transformation(
                child = render.Padding(pad = (0, y, 0, 0), child = render.Box(width = 10, height = 2, color = FOG_COLOR)),
                duration = 60,
                delay = delay,
                direction = "alternate",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-6, 0)], curve = "ease_in_out"),
                    animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(14, 0)]),
                ],
            ),
        )
    return haze

def build_house_icon(seasonal = "", is_night = False):
    """House pixel art, 16x16. Night mode dims windows/walls."""
    # Dynamic colors for day/night
    wall_color = "#997744" if is_night else HOUSE_WALL
    window_color = "#334455" if is_night else HOUSE_WINDOW
    door_color = "#664411" if is_night else HOUSE_DOOR

    children = [
        # Chimney (on right slope of roof, connects at y=4)
        render.Padding(pad = (10, 2, 0, 0), child = render.Box(width = 2, height = 3, color = HOUSE_CHIMNEY)),
        # Roof - wide triangle shape
        render.Padding(pad = (6, 3, 0, 0), child = render.Box(width = 4, height = 1, color = HOUSE_ROOF)),
        render.Padding(pad = (5, 4, 0, 0), child = render.Box(width = 6, height = 1, color = HOUSE_ROOF)),
        render.Padding(pad = (4, 5, 0, 0), child = render.Box(width = 8, height = 1, color = HOUSE_ROOF)),
        render.Padding(pad = (3, 6, 0, 0), child = render.Box(width = 10, height = 1, color = HOUSE_ROOF)),
        render.Padding(pad = (2, 7, 0, 0), child = render.Box(width = 12, height = 1, color = HOUSE_ROOF)),
        # Walls
        render.Padding(pad = (3, 8, 0, 0), child = render.Box(width = 10, height = 6, color = wall_color)),
        # Window (left side)
        render.Padding(pad = (4, 9, 0, 0), child = render.Box(width = 3, height = 3, color = window_color)),
        # Interior light behind door (visible when door opens)
        render.Padding(pad = (9, 10, 0, 0), child = render.Box(width = 3, height = 4, color = "#886622")),
        # Foundation
        render.Padding(pad = (2, 14, 0, 0), child = render.Box(width = 12, height = 1, color = HOUSE_FOUNDATION)),
    ]

    # Animated door that opens and closes
    children.append(animation.Transformation(
        child = render.Padding(pad = (9, 10, 0, 0),
            child = render.Box(width = 3, height = 4, color = door_color)),
        duration = 120,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, 0)]),
            animation.Keyframe(percentage = 0.70, transforms = [animation.Translate(0, 0)]),
            animation.Keyframe(percentage = 0.78, transforms = [animation.Translate(3, 0)]),
            animation.Keyframe(percentage = 0.88, transforms = [animation.Translate(3, 0)]),
            animation.Keyframe(percentage = 0.95, transforms = [animation.Translate(0, 0)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(0, 0)]),
        ],
    ))

    # Night: warm interior glow inside window
    if is_night:
        children.append(render.Padding(pad = (5, 10, 0, 0), child = render.Box(width = 2, height = 2, color = "#aa8833")))

    # Seasonal house decorations (same coordinate system — moves with house)
    if seasonal == "christmas":
        children.extend(_house_christmas_decor())
    elif seasonal == "halloween":
        children.extend(_house_halloween_decor())

    return render.Box(width = 16, height = 16, child = render.Stack(children = children))

def build_grid_icon():
    """Power pylon pixel art, centered in 20x16 box."""
    return render.Box(
        width = 20,
        height = 16,
        child = render.Stack(
            children = [
                # Top cap (center: x=9-10 in 20px = exactly centered)
                render.Padding(pad = (9, 1, 0, 0), child = render.Box(width = 2, height = 1, color = GRID_METAL)),
                # Upper cross arm
                render.Padding(pad = (6, 2, 0, 0), child = render.Box(width = 8, height = 1, color = GRID_METAL)),
                # Wire attachment points (symmetric: x=5 and x=14)
                render.Padding(pad = (5, 3, 0, 0), child = render.Box(width = 1, height = 1, color = GRID_DARK)),
                render.Padding(pad = (9, 3, 0, 0), child = render.Box(width = 2, height = 1, color = GRID_METAL)),
                render.Padding(pad = (14, 3, 0, 0), child = render.Box(width = 1, height = 1, color = GRID_DARK)),
                # Upper taper
                render.Padding(pad = (8, 4, 0, 0), child = render.Box(width = 4, height = 1, color = GRID_METAL)),
                render.Padding(pad = (9, 5, 0, 0), child = render.Box(width = 2, height = 1, color = GRID_METAL)),
                # Center post
                render.Padding(pad = (9, 6, 0, 0), child = render.Box(width = 2, height = 2, color = GRID_METAL)),
                # Lower cross arm
                render.Padding(pad = (7, 8, 0, 0), child = render.Box(width = 6, height = 1, color = GRID_METAL)),
                # Lower wire points (symmetric: x=6 and x=13)
                render.Padding(pad = (6, 9, 0, 0), child = render.Box(width = 1, height = 1, color = GRID_DARK)),
                render.Padding(pad = (9, 9, 0, 0), child = render.Box(width = 2, height = 1, color = GRID_METAL)),
                render.Padding(pad = (13, 9, 0, 0), child = render.Box(width = 1, height = 1, color = GRID_DARK)),
                # Lower taper
                render.Padding(pad = (8, 10, 0, 0), child = render.Box(width = 4, height = 1, color = GRID_METAL)),
                render.Padding(pad = (9, 11, 0, 0), child = render.Box(width = 2, height = 2, color = GRID_METAL)),
                # Base
                render.Padding(pad = (8, 13, 0, 0), child = render.Box(width = 4, height = 1, color = GRID_DARK)),
                # Ground line (matches house foundation)
                render.Padding(pad = (6, 14, 0, 0), child = render.Box(width = 8, height = 1, color = GRID_DARK)),
            ],
        ),
    )

# --- Battery bar ---

def build_battery_bar(battery_pct):
    """Build a battery icon with gradient segments and percentage text beside it."""
    filled = int(battery_pct * 8 / 100)
    if battery_pct > 0 and filled == 0:
        filled = 1

    # Gradient segments (no gaps, compact bar)
    segs = []
    for i in range(8):
        color = BATT_GRADIENT[i] if i < filled else BATT_EMPTY
        segs.append(render.Box(width = 1, height = 3, color = color))
    interior_bg = render.Row(children = segs)

    # Compact battery icon (10px body + 1px tip = 11px)
    battery_icon = render.Row(
        children = [
            render.Stack(
                children = [
                    render.Box(width = 10, height = 5, color = BATT_OUTLINE),
                    render.Padding(
                        pad = (1, 1, 1, 1),
                        child = render.Box(width = 8, height = 3, color = "#000000", child = interior_bg),
                    ),
                ],
            ),
            render.Padding(
                pad = (0, 1, 0, 0),
                child = render.Box(width = 1, height = 3, color = BATT_OUTLINE),
            ),
        ],
    )

    # Percentage text to the right of the battery
    pct_text = "%d%%" % battery_pct

    return render.Row(
        cross_align = "center",
        children = [
            battery_icon,
            render.Padding(
                pad = (1, 0, 0, 0),
                child = render.Text(content = pct_text, font = "tom-thumb", color = "#ffffff"),
            ),
        ],
    )

# --- Seasonal system: slot-based composition ---
# House decorations (snow, lights) are built INTO the house icon.
# Scene items (tree, snowman, pumpkin, turkey) are self-contained 4x16 boxes
# placed in left/right margin slots beside the house.
# Full overlays (firework, bat) span the entire 24x16 area.

def get_seasonal_name(config):
    """Resolve seasonal name from config or auto-detect from date."""
    seasonal = config.get("seasonal", "")

    if seasonal == "" or seasonal == "auto":
        month = int(config.get("month", "0"))
        day = int(config.get("day", "0"))
        if (month == 12 and day >= 30) or (month == 1 and day <= 2):
            seasonal = "newyear"
        elif (month == 12 and day >= 15) or (month == 1 and day <= 5):
            seasonal = "christmas"
        elif month == 7 and day >= 1 and day <= 7:
            seasonal = "july4"
        elif month == 10 and day >= 25 and day <= 31:
            seasonal = "halloween"
        elif month == 11 and day >= 20 and day <= 30:
            seasonal = "thanksgiving"

    return seasonal

def build_left_scene(seasonal):
    """Left margin scene item (4x16 box). Independent of house."""
    if seasonal == "christmas":
        return _build_christmas_tree()
    elif seasonal == "halloween":
        return _build_pumpkin()
    elif seasonal == "thanksgiving":
        return _build_turkey()
    return render.Box(width = 4, height = 16)

def build_right_scene(seasonal):
    """Right margin scene item (4x16 box). Independent of house."""
    if seasonal == "christmas":
        return _build_snowman()
    elif seasonal == "halloween":
        return _build_ghost()
    return render.Box(width = 4, height = 16)

def build_full_overlay(seasonal):
    """Full 24x16 overlay. Returns (behind, front) for depth layering."""
    if seasonal == "july4":
        return _july4_fireworks()
    elif seasonal == "newyear":
        return _newyear_fireworks()
    elif seasonal == "halloween":
        return (None, _build_bat())
    return (None, None)

# --- House decorations (use house coordinate system) ---

def _house_christmas_decor():
    """Snow on roof + twinkling lights — uses same coords as house."""
    lights_a = render.Stack(children = [
        render.Padding(pad = (3, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff0000")),
        render.Padding(pad = (7, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff0000")),
        render.Padding(pad = (11, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff0000")),
    ])
    lights_b = render.Stack(children = [
        render.Padding(pad = (5, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#00ff00")),
        render.Padding(pad = (9, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#00ff00")),
    ])

    twinkling_a = animation.Transformation(
        child = lights_a,
        duration = 8,
        delay = 0,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    )
    twinkling_b = animation.Transformation(
        child = lights_b,
        duration = 8,
        delay = 4,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    )

    return [
        # Snow on roof peak (same coords as roof at y=3)
        render.Padding(pad = (6, 3, 0, 0), child = render.Box(width = 4, height = 1, color = "#ffffff")),
        render.Padding(pad = (5, 4, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffffff")),
        render.Padding(pad = (10, 4, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffffff")),
        # Twinkling lights below eave
        twinkling_a,
        twinkling_b,
    ]

def _house_halloween_decor():
    """Spooky purple/orange flickering lights + spiderweb — house coords."""
    # Flickering orange and purple lights along eave (y=8, below roof)
    lights_a = render.Stack(children = [
        render.Padding(pad = (3, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff6600")),
        render.Padding(pad = (7, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff6600")),
        render.Padding(pad = (11, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff6600")),
    ])
    lights_b = render.Stack(children = [
        render.Padding(pad = (5, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#8800cc")),
        render.Padding(pad = (9, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#8800cc")),
    ])

    flicker_a = animation.Transformation(
        child = lights_a,
        duration = 6,
        delay = 0,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    )
    flicker_b = animation.Transformation(
        child = lights_b,
        duration = 6,
        delay = 3,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    )

    return [
        # Spiderweb on upper-left corner of house (roof/wall junction)
        render.Padding(pad = (2, 7, 0, 0), child = render.Box(width = 1, height = 1, color = "#666666")),
        render.Padding(pad = (3, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#555555")),
        render.Padding(pad = (2, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#555555")),
        render.Padding(pad = (2, 9, 0, 0), child = render.Box(width = 1, height = 1, color = "#444444")),
        # Spooky window glow (replace blue with eerie green)
        render.Padding(pad = (4, 9, 0, 0), child = render.Box(width = 3, height = 3, color = "#44ff44")),
        # Flickering orange + purple lights
        flicker_a,
        flicker_b,
    ]

# --- Self-contained scene items (all coords relative to own 4x16 box) ---

def _build_christmas_tree():
    """Christmas tree in 4x16 box."""
    return render.Box(
        width = 4,
        height = 16,
        child = render.Stack(children = [
            # Star
            render.Padding(pad = (1, 5, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffcc00")),
            # Tree body (tiered triangle)
            render.Padding(pad = (1, 6, 0, 0), child = render.Box(width = 1, height = 1, color = "#008800")),
            render.Padding(pad = (0, 7, 0, 0), child = render.Box(width = 3, height = 1, color = "#008800")),
            render.Padding(pad = (0, 8, 0, 0), child = render.Box(width = 4, height = 1, color = "#006600")),
            render.Padding(pad = (1, 9, 0, 0), child = render.Box(width = 2, height = 1, color = "#008800")),
            render.Padding(pad = (0, 10, 0, 0), child = render.Box(width = 4, height = 1, color = "#006600")),
            render.Padding(pad = (0, 11, 0, 0), child = render.Box(width = 4, height = 1, color = "#008800")),
            render.Padding(pad = (0, 12, 0, 0), child = render.Box(width = 4, height = 1, color = "#006600")),
            # Trunk
            render.Padding(pad = (1, 13, 0, 0), child = render.Box(width = 1, height = 2, color = "#885522")),
            # Ornaments
            render.Padding(pad = (0, 8, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff0000")),
            render.Padding(pad = (3, 10, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffcc00")),
            render.Padding(pad = (1, 12, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff0000")),
        ]),
    )

def _build_snowman():
    """Snowman in 4x16 box."""
    return render.Box(
        width = 4,
        height = 16,
        child = render.Stack(children = [
            # Hat
            render.Padding(pad = (1, 7, 0, 0), child = render.Box(width = 2, height = 1, color = "#333333")),
            render.Padding(pad = (0, 8, 0, 0), child = render.Box(width = 4, height = 1, color = "#333333")),
            # Head
            render.Padding(pad = (1, 9, 0, 0), child = render.Box(width = 2, height = 1, color = "#ffffff")),
            render.Padding(pad = (1, 9, 0, 0), child = render.Box(width = 1, height = 1, color = "#000000")),
            render.Padding(pad = (3, 9, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff8800")),
            # Scarf
            render.Padding(pad = (1, 10, 0, 0), child = render.Box(width = 2, height = 1, color = "#ff0000")),
            # Body
            render.Padding(pad = (0, 11, 0, 0), child = render.Box(width = 3, height = 3, color = "#ffffff")),
        ]),
    )

def _build_pumpkin():
    """Jack-o-lantern in 4x16 box."""
    return render.Box(
        width = 4,
        height = 16,
        child = render.Stack(children = [
            render.Padding(pad = (1, 11, 0, 0), child = render.Box(width = 1, height = 1, color = "#44aa00")),
            render.Padding(pad = (0, 12, 0, 0), child = render.Box(width = 3, height = 2, color = "#ff8800")),
            render.Padding(pad = (0, 13, 0, 0), child = render.Box(width = 1, height = 1, color = "#000000")),
            render.Padding(pad = (2, 13, 0, 0), child = render.Box(width = 1, height = 1, color = "#000000")),
        ]),
    )

def _build_turkey():
    """Turkey in 4x16 box."""
    return render.Box(
        width = 4,
        height = 16,
        child = render.Stack(children = [
            # Tail feathers
            render.Padding(pad = (0, 10, 0, 0), child = render.Box(width = 1, height = 1, color = "#dd6600")),
            render.Padding(pad = (1, 9, 0, 0), child = render.Box(width = 1, height = 2, color = "#ddaa00")),
            render.Padding(pad = (2, 10, 0, 0), child = render.Box(width = 1, height = 1, color = "#cc3300")),
            # Body
            render.Padding(pad = (0, 11, 0, 0), child = render.Box(width = 3, height = 2, color = "#884422")),
            # Head + wattle
            render.Padding(pad = (3, 11, 0, 0), child = render.Box(width = 1, height = 1, color = "#884422")),
            render.Padding(pad = (3, 12, 0, 0), child = render.Box(width = 1, height = 1, color = "#cc0000")),
        ]),
    )

def _build_ghost():
    """Spooky ghost in 4x16 box."""
    return render.Box(
        width = 4,
        height = 16,
        child = render.Stack(children = [
            # Head (rounded top)
            render.Padding(pad = (1, 8, 0, 0), child = render.Box(width = 2, height = 1, color = "#dddddd")),
            # Body
            render.Padding(pad = (0, 9, 0, 0), child = render.Box(width = 4, height = 3, color = "#dddddd")),
            # Eyes
            render.Padding(pad = (0, 10, 0, 0), child = render.Box(width = 1, height = 1, color = "#000000")),
            render.Padding(pad = (2, 10, 0, 0), child = render.Box(width = 1, height = 1, color = "#000000")),
            # Wavy bottom (alternating pixels)
            render.Padding(pad = (0, 12, 0, 0), child = render.Box(width = 1, height = 1, color = "#dddddd")),
            render.Padding(pad = (2, 12, 0, 0), child = render.Box(width = 1, height = 1, color = "#dddddd")),
        ]),
    )

# --- Full overlays (span entire 24x16 col2 area) ---
# TODO: Rework fireworks
# - Colors still not right for July 4th
# - Arcing not visible — rockets should launch from grid side (right)
#   and solar side (left) and arc across the sky like cannonballs
# - Need more dramatic parabolic trajectories spanning the full display

def _build_rocket(launch_x, burst_x, burst_y, trail_color, burst_colors, size, delay, duration):
    """One bottle rocket: launches from ground, rises to burst point, explodes.
    Returns list of animation children.
    launch_x: ground x position, burst_x/burst_y: explosion apex,
    size: 'small' (dim, distant) or 'big' (bright, close)."""
    children = []

    # --- Rocket trail arcing from ground to burst point (cannonball trajectory) ---
    # Midpoint: halfway between launch and burst horizontally, peaks above burst vertically
    mid_x = (launch_x + burst_x) // 2
    mid_y = burst_y - 2 if burst_y >= 2 else 0  # arc peaks above the burst point
    children.append(
        animation.Transformation(
            child = render.Box(width = 1, height = 2, color = trail_color),
            duration = duration,
            delay = delay,
            direction = "normal",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(launch_x, 15)], curve = "ease_out"),
                animation.Keyframe(percentage = 0.2, transforms = [animation.Translate(mid_x, mid_y)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 0.35, transforms = [animation.Translate(burst_x, burst_y)]),
                animation.Keyframe(percentage = 0.4, transforms = [animation.Translate(burst_x, burst_y), animation.Scale(0.0, 0.0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
            ],
        ),
    )

    # --- Explosion burst at apex ---
    if size == "small":
        offsets = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]
    else:
        offsets = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]

    for i, offset in enumerate(offsets):
        dx, dy = offset[0], offset[1]
        px = burst_x + dx
        py = burst_y + dy
        if px < 0 or px > 23 or py < 0 or py > 15:
            continue

        color = burst_colors[i % len(burst_colors)]
        ripple = i * 1

        if size == "big":
            children.append(
                render.Padding(
                    pad = (px, py, 0, 0),
                    child = animation.Transformation(
                        child = render.Box(width = 1, height = 1, color = color),
                        duration = duration,
                        delay = delay + ripple,
                        direction = "normal",
                        fill_mode = "forwards",
                        keyframes = [
                            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(0.0, 0.0)]),
                            animation.Keyframe(percentage = 0.35, transforms = [animation.Scale(0.0, 0.0)]),
                            animation.Keyframe(percentage = 0.4, transforms = [animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 0.65, transforms = [animation.Translate(0, 0), animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 0.9, transforms = [animation.Translate(0, 2), animation.Scale(0.0, 0.0)]),
                            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
                        ],
                    ),
                ),
            )
        else:
            children.append(
                render.Padding(
                    pad = (px, py, 0, 0),
                    child = animation.Transformation(
                        child = render.Box(width = 1, height = 1, color = color),
                        duration = duration,
                        delay = delay + ripple,
                        direction = "normal",
                        fill_mode = "forwards",
                        keyframes = [
                            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(0.0, 0.0)]),
                            animation.Keyframe(percentage = 0.35, transforms = [animation.Scale(0.0, 0.0)]),
                            animation.Keyframe(percentage = 0.4, transforms = [animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 0.7, transforms = [animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
                        ],
                    ),
                ),
            )

    return children

def _build_fireworks(bg_rockets, fg_rockets, duration):
    """Build layered bottle rocket volley. Returns (behind_stack, front_stack).
    Each rocket: (launch_x, burst_x, burst_y, trail_color, burst_colors, delay)."""
    bg_children = []
    for r in bg_rockets:
        bg_children.extend(_build_rocket(r[0], r[1], r[2], r[3], r[4], "small", r[5], duration))

    fg_children = []
    for r in fg_rockets:
        fg_children.extend(_build_rocket(r[0], r[1], r[2], r[3], r[4], "big", r[5], duration))

    bg = render.Stack(children = bg_children) if bg_children else None
    fg = render.Stack(children = fg_children) if fg_children else None
    return (bg, fg)

def _july4_fireworks():
    """July 4th: bottle rocket volley — warm reds, oranges, golds, white sparks."""
    # Background (dim, distant rockets)
    bg = [
        #  launch_x, burst_x, burst_y, trail,     burst_colors,                          delay
        (1, 3, 2, "#774400", ["#aa5500", "#886633", "#995522"], 2),
        (22, 20, 1, "#774400", ["#aa6600", "#885533", "#997744"], 18),
        (10, 12, 2, "#664400", ["#886633", "#775522", "#aa6644"], 32),
    ]
    # Foreground (bright, close rockets)
    fg = [
        (4, 6, 4, "#ffaa00", ["#ff4400", "#ff6600", "#ffaa00", "#ffffff"], 0),
        (19, 17, 3, "#ffaa00", ["#ff5500", "#ffcc00", "#ff8800", "#ffffff"], 12),
        (11, 10, 5, "#ffcc00", ["#ff3300", "#ff7700", "#ffbb00", "#ffffff"], 24),
    ]
    return _build_fireworks(bg, fg, 38)

def _newyear_fireworks():
    """New Year's: elegant gold, silver, purple celebration."""
    bg = [
        (2, 4, 3, "#555544", ["#777766", "#666655", "#888877"], 4),
        (21, 19, 2, "#555544", ["#777766", "#666677", "#888866"], 22),
    ]
    fg = [
        (7, 9, 4, "#ccaa00", ["#ffcc00", "#ffffff", "#cc88ff", "#ffdd44"], 0),
        (17, 16, 3, "#ccaa00", ["#ffdd00", "#ffffff", "#aa66ee", "#00ccaa"], 14),
    ]
    return _build_fireworks(bg, fg, 40)

def _build_bat():
    """Bat flying across 24x16 area."""
    return animation.Transformation(
        child = render.Padding(
            pad = (0, 2, 0, 0),
            child = render.Row(children = [
                render.Box(width = 2, height = 1, color = "#222222"),
                render.Box(width = 1, height = 1, color = "#333333"),
                render.Box(width = 2, height = 1, color = "#222222"),
            ]),
        ),
        duration = 20,
        delay = 0,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-2, 0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(20, 0)]),
        ],
    )

# --- Full-height weather scenes for column 1 (20x32 area) ---

def _big_crescent(x, y):
    """Large crescent moon pixel art (~8px tall) at given position."""
    return [
        render.Padding(pad = (x + 2, y, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
        render.Padding(pad = (x + 1, y + 1, 0, 0), child = render.Box(width = 4, height = 1, color = MOON_COLOR)),
        render.Padding(pad = (x, y + 2, 0, 0), child = render.Box(width = 3, height = 1, color = MOON_COLOR)),
        render.Padding(pad = (x, y + 3, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
        render.Padding(pad = (x, y + 4, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
        render.Padding(pad = (x, y + 5, 0, 0), child = render.Box(width = 3, height = 1, color = MOON_COLOR)),
        render.Padding(pad = (x + 1, y + 6, 0, 0), child = render.Box(width = 4, height = 1, color = MOON_COLOR)),
        render.Padding(pad = (x + 2, y + 7, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
    ]

def _rain_drop(x, delay, duration = 15):
    """Single animated rain drop at x position."""
    return render.Padding(
        pad = (x, 0, 0, 0),
        child = animation.Transformation(
            child = render.Box(width = 1, height = 2, color = RAIN_COLOR),
            duration = duration,
            delay = delay,
            direction = "normal",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, 4)], curve = "linear"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(0, 34)]),
            ],
        ),
    )

def _snow_flake(x, delay, duration = 40):
    """Single animated snowflake with lateral drift."""
    return render.Padding(
        pad = (x, 0, 0, 0),
        child = animation.Transformation(
            child = render.Box(width = 1, height = 1, color = SNOW_COLOR),
            duration = duration,
            delay = delay,
            direction = "normal",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, -2)], curve = "linear"),
                animation.Keyframe(percentage = 0.5, transforms = [animation.Translate(2, 14)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(-1, 34)]),
            ],
        ),
    )

def _clear_night_scene():
    """Clear night: moon pinned to top-left corner (y=0)."""
    children = _big_crescent(1, 0)
    return render.Stack(children = children)

def _clear_day_scene():
    """Clear day without solar panel: sun pinned to top-left corner (y=0)."""
    children = [
        # Sun core (5x5 with bright center), top-left
        render.Padding(pad = (2, 0, 0, 0), child = render.Box(width = 5, height = 5, color = SUN_DIM_RAY)),
        render.Padding(pad = (3, 1, 0, 0), child = render.Box(width = 3, height = 3, color = SUN_BRIGHT_CORE)),
    ]
    # Animated rays around sun at y=0
    ray_pads = [(7, 0), (1, 2), (8, 2), (2, 5), (7, 5)]
    ray_children = []
    for px, py in ray_pads:
        ray_children.append(render.Padding(pad = (px, py, 0, 0), child = render.Box(width = 1, height = 1, color = SUN_BRIGHT_RAY)))
    children.append(animation.Transformation(
        child = render.Stack(children = ray_children),
        duration = 50,
        delay = 0,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    ))
    return render.Stack(children = children)

def build_weather_scene(weather_icon, sun_elevation = 0.0, is_night = True):
    """Build col1 scene: just sun or moon in top-left. Weather effects come from overlay."""
    if is_night or weather_icon.endswith("-night"):
        return _clear_night_scene()
    return _clear_day_scene()

# --- Full-width sky & weather overlay (64x32) ---

# --- Living world: characters, pets, random encounters ---

def _pixel_person(x, y, shirt_color):
    """3x4 pixel person at position (x, y)."""
    return render.Stack(children = [
        render.Padding(pad = (x + 1, y, 0, 0), child = render.Box(width = 1, height = 1, color = CHAR_SKIN)),
        render.Padding(pad = (x, y + 1, 0, 0), child = render.Box(width = 3, height = 1, color = shirt_color)),
        render.Padding(pad = (x + 1, y + 2, 0, 0), child = render.Box(width = 1, height = 1, color = CHAR_PANTS)),
        render.Padding(pad = (x, y + 3, 0, 0), child = render.Box(width = 1, height = 1, color = CHAR_SHOES)),
        render.Padding(pad = (x + 2, y + 3, 0, 0), child = render.Box(width = 1, height = 1, color = CHAR_SHOES)),
    ])

def _pixel_dog(x, y):
    """4x3 pixel dog at position (x, y)."""
    return render.Stack(children = [
        render.Padding(pad = (x, y, 0, 0), child = render.Box(width = 1, height = 1, color = DOG_COLOR)),
        render.Padding(pad = (x + 1, y, 0, 0), child = render.Box(width = 3, height = 1, color = DOG_COLOR)),
        render.Padding(pad = (x + 1, y + 1, 0, 0), child = render.Box(width = 3, height = 1, color = DOG_COLOR)),
        render.Padding(pad = (x + 1, y + 2, 0, 0), child = render.Box(width = 1, height = 1, color = DOG_COLOR)),
        render.Padding(pad = (x + 3, y + 2, 0, 0), child = render.Box(width = 1, height = 1, color = DOG_COLOR)),
    ])

def _pixel_cat(x, y):
    """3x2 pixel cat at position (x, y)."""
    return render.Stack(children = [
        render.Padding(pad = (x, y, 0, 0), child = render.Box(width = 1, height = 1, color = "#aaaaaa")),
        render.Padding(pad = (x + 1, y, 0, 0), child = render.Box(width = 2, height = 1, color = CAT_COLOR)),
        render.Padding(pad = (x + 1, y + 1, 0, 0), child = render.Box(width = 1, height = 1, color = CAT_COLOR)),
        render.Padding(pad = (x + 2, y + 1, 0, 0), child = render.Box(width = 1, height = 1, color = CAT_COLOR)),
    ])

def _pixel_ufo(x, y):
    """5x3 pixel UFO at position (x, y)."""
    return render.Stack(children = [
        render.Padding(pad = (x + 1, y, 0, 0), child = render.Box(width = 3, height = 1, color = "#44ff44")),
        render.Padding(pad = (x, y + 1, 0, 0), child = render.Box(width = 5, height = 1, color = "#888888")),
        render.Padding(pad = (x + 1, y + 2, 0, 0), child = render.Box(width = 1, height = 1, color = "#ff0000")),
        render.Padding(pad = (x + 3, y + 2, 0, 0), child = render.Box(width = 1, height = 1, color = "#0044ff")),
    ])

def _pixel_yeti(x, y):
    """4x5 SkiFree yeti at position (x, y)."""
    return render.Stack(children = [
        render.Padding(pad = (x + 1, y, 0, 0), child = render.Box(width = 2, height = 1, color = "#ffffff")),
        render.Padding(pad = (x, y + 1, 0, 0), child = render.Box(width = 4, height = 2, color = "#eeeeee")),
        render.Padding(pad = (x + 1, y + 3, 0, 0), child = render.Box(width = 2, height = 1, color = "#dddddd")),
        render.Padding(pad = (x, y + 4, 0, 0), child = render.Box(width = 1, height = 1, color = "#cccccc")),
        render.Padding(pad = (x + 3, y + 4, 0, 0), child = render.Box(width = 1, height = 1, color = "#cccccc")),
    ])

def _walking_person(shirt_color, start_x, end_x, y, duration, delay = 0):
    """Animate a person walking from start_x to end_x."""
    return animation.Transformation(
        child = _pixel_person(0, y, shirt_color),
        duration = duration,
        delay = delay,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(start_x, 0)], curve = "linear"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(end_x, 0)]),
        ],
    )

def _walking_entity(entity, start_x, end_x, duration, delay = 0):
    """Animate any sprite walking from start_x to end_x."""
    return animation.Transformation(
        child = entity,
        duration = duration,
        delay = delay,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(start_x, 0)], curve = "linear"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(end_x, 0)]),
        ],
    )

def _scene_leaving_home():
    """Parent walks from house toward grid."""
    return [_walking_person(CHAR_PARENT1_SHIRT, 30, 55, 11, 80)]

def _scene_coming_home():
    """Parent walks from grid back to house."""
    return [_walking_person(CHAR_PARENT2_SHIRT, 55, 30, 11, 80)]

def _scene_solar_work():
    """Person walks from house to solar panel."""
    return [_walking_person(CHAR_PARENT1_SHIRT, 30, 8, 11, 80)]

def _scene_walk_dog():
    """Person + dog walk together from house rightward."""
    return [
        _walking_person(CHAR_PARENT2_SHIRT, 28, 52, 11, 90),
        _walking_entity(_pixel_dog(0, 12), 32, 56, 90),
    ]

def _scene_kid_plays():
    """Kid runs back and forth near house."""
    return [
        animation.Transformation(
            child = _pixel_person(0, 11, CHAR_KID_SHIRT),
            duration = 60,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(28, 0)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(42, 0)]),
            ],
        ),
    ]

def _scene_cat_wander():
    """Cat darts across screen fast."""
    return [_walking_entity(_pixel_cat(0, 13), 5, 60, 40)]

def _scene_family_walk():
    """Two adults + kid walking together."""
    return [
        _walking_person(CHAR_PARENT1_SHIRT, 26, 50, 11, 100),
        _walking_person(CHAR_PARENT2_SHIRT, 30, 54, 11, 100),
        _walking_person(CHAR_KID_SHIRT, 28, 52, 12, 100),
    ]

def _scene_ufo():
    """UFO flies across the sky."""
    return [animation.Transformation(
        child = _pixel_ufo(0, 2),
        duration = 60,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-8, 0)], curve = "linear"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(72, 0)]),
        ],
    )]

def _scene_abduction():
    """UFO hovers over person, tractor beam pulls them up."""
    children = []
    # UFO flies in and stops over victim
    children.append(animation.Transformation(
        child = _pixel_ufo(0, 1),
        duration = 100,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-8, 0)], curve = "ease_out"),
            animation.Keyframe(percentage = 0.30, transforms = [animation.Translate(28, 0)]),
            animation.Keyframe(percentage = 0.70, transforms = [animation.Translate(28, 0)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(72, 0)]),
        ],
    ))
    # Tractor beam (visible while UFO hovers)
    children.append(animation.Transformation(
        child = render.Padding(pad = (30, 4, 0, 0),
            child = render.Box(width = 3, height = 10, color = "#225522")),
        duration = 100,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 0.30, transforms = [animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 0.35, transforms = [animation.Scale(1.0, 1.0)]),
            animation.Keyframe(percentage = 0.65, transforms = [animation.Scale(1.0, 1.0)]),
            animation.Keyframe(percentage = 0.70, transforms = [animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    ))
    # Person being pulled up
    children.append(animation.Transformation(
        child = _pixel_person(30, 11, CHAR_PARENT1_SHIRT),
        duration = 100,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, 0)]),
            animation.Keyframe(percentage = 0.35, transforms = [animation.Translate(0, 0)]),
            animation.Keyframe(percentage = 0.65, transforms = [animation.Translate(0, -10)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(0, -10)]),
        ],
    ))
    return children

def _scene_yeti():
    """SkiFree yeti chases and eats a person."""
    children = []
    # Person running — starts ahead but yeti catches up
    children.append(animation.Transformation(
        child = _pixel_person(0, 10, CHAR_PARENT1_SHIRT),
        duration = 80,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(24, 0)], curve = "linear"),
            animation.Keyframe(percentage = 0.55, transforms = [animation.Translate(44, 0)]),
            # Yeti catches them — person disappears (scale to 0)
            animation.Keyframe(percentage = 0.60, transforms = [animation.Translate(44, 0), animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(44, 0), animation.Scale(0.0, 0.0)]),
        ],
    ))
    # Yeti chasing — faster, catches up at 60%
    children.append(animation.Transformation(
        child = _pixel_yeti(0, 10),
        duration = 80,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(14, 0)], curve = "linear"),
            animation.Keyframe(percentage = 0.55, transforms = [animation.Translate(42, 0)]),
            # Yeti stops briefly to eat (stays at catch point)
            animation.Keyframe(percentage = 0.75, transforms = [animation.Translate(42, 0)]),
            # Then walks off screen
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(68, 0)]),
        ],
    ))
    return children

def _scene_pond_fishing():
    """Pond with fisher during rainy night."""
    children = []
    # Pond water surface
    children.append(render.Padding(pad = (2, 13, 0, 0), child = render.Box(width = 12, height = 2, color = "#224466")))
    # Pond shimmer
    children.append(render.Padding(pad = (5, 13, 0, 0), child = render.Box(width = 3, height = 1, color = "#335577")))
    # Reeds at edges
    children.append(render.Padding(pad = (1, 11, 0, 0), child = render.Box(width = 1, height = 3, color = "#226622")))
    children.append(render.Padding(pad = (15, 11, 0, 0), child = render.Box(width = 1, height = 3, color = "#226622")))
    # Fisher person sitting at edge
    children.append(render.Padding(pad = (10, 10, 0, 0), child = render.Box(width = 1, height = 1, color = CHAR_SKIN)))
    children.append(render.Padding(pad = (9, 11, 0, 0), child = render.Box(width = 3, height = 1, color = CHAR_PARENT1_SHIRT)))
    children.append(render.Padding(pad = (9, 12, 0, 0), child = render.Box(width = 2, height = 1, color = CHAR_PANTS)))
    # Fishing rod
    children.append(render.Padding(pad = (12, 9, 0, 0), child = render.Box(width = 1, height = 1, color = "#885533")))
    children.append(render.Padding(pad = (12, 10, 0, 0), child = render.Box(width = 1, height = 4, color = "#885533")))
    # Tiny fish bobbing in water
    children.append(animation.Transformation(
        child = render.Padding(pad = (6, 14, 0, 0), child = render.Box(width = 2, height = 1, color = "#ff8844")),
        duration = 40,
        delay = 20,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, 0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(4, 0)]),
        ],
    ))
    return children

def _scene_snowball():
    """Kid throws snowball across screen during snow."""
    children = []
    # Kid standing
    children.append(_pixel_person(25, 11, CHAR_KID_SHIRT))
    # Snowball arc animation
    children.append(animation.Transformation(
        child = render.Padding(pad = (0, 0, 0, 0), child = render.Box(width = 2, height = 2, color = "#ffffff")),
        duration = 40,
        delay = 10,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(28, 12)]),
            animation.Keyframe(percentage = 0.5, transforms = [animation.Translate(40, 6)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(52, 12)]),
        ],
    ))
    return children

def _scene_fireworks():
    """Fireworks burst in the sky during clear nights."""
    children = []
    # Rocket goes up
    children.append(animation.Transformation(
        child = render.Padding(pad = (0, 0, 0, 0), child = render.Box(width = 1, height = 2, color = "#ffaa00")),
        duration = 60,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(32, 14)]),
            animation.Keyframe(percentage = 0.3, transforms = [animation.Translate(32, 3)]),
            animation.Keyframe(percentage = 0.35, transforms = [animation.Translate(32, 3), animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(32, 3), animation.Scale(0.0, 0.0)]),
        ],
    ))
    # Burst particles in 4 directions
    burst_configs = [(3, 0, "#ff4444"), (-3, 0, "#44ff44"), (0, -3, "#4444ff"), (2, 2, "#ffff44")]
    for dx, dy, color in burst_configs:
        children.append(animation.Transformation(
            child = render.Padding(pad = (0, 0, 0, 0), child = render.Box(width = 1, height = 1, color = color)),
            duration = 60,
            delay = 0,
            direction = "normal",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(0.0, 0.0)]),
                animation.Keyframe(percentage = 0.30, transforms = [animation.Scale(0.0, 0.0)]),
                animation.Keyframe(percentage = 0.35, transforms = [animation.Translate(32, 3), animation.Scale(1.0, 1.0)]),
                animation.Keyframe(percentage = 0.7, transforms = [animation.Translate(32 + dx, 3 + dy)]),
                animation.Keyframe(percentage = 0.75, transforms = [animation.Translate(32 + dx, 3 + dy), animation.Scale(0.0, 0.0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(32 + dx, 3 + dy), animation.Scale(0.0, 0.0)]),
            ],
        ))
    return children

def _activity_seed(config):
    """Deterministic seed from date+hour. Changes hourly for stable characters."""
    m = int(config.get("month", "1"))
    d = int(config.get("day", "1"))
    h = int(config.get("hour", "0"))
    return ((m * 31 + d) * 24 + h) % 100

def build_life_overlay(config):
    """Build character/activity overlay. Uses game engine if active, else seed-based fallback."""
    if config.get("gactive", "false") == "true":
        return _build_game_overlay(config)

    # Fallback: seed-based scenes (when game engine not running)
    seed = _activity_seed(config)
    is_night = config.get("is_night", "false") == "true"
    weather = config.get("weather_icon", "clear-day")
    children = []

    if is_night and weather in ("rain", "sleet") and seed < 50:
        children = _scene_pond_fishing()
    elif weather == "snow" and 40 <= seed and seed < 55:
        children = _scene_snowball()
    elif is_night and "clear" in weather and 85 <= seed and seed < 90:
        children = _scene_fireworks()
    elif seed < 20:
        children = _scene_leaving_home()
    elif seed < 40:
        children = _scene_coming_home()
    elif seed < 50:
        children = _scene_solar_work()
    elif seed < 60:
        children = _scene_walk_dog()
    elif seed < 70:
        children = _scene_kid_plays()
    elif seed < 75:
        children = _scene_cat_wander()
    elif seed < 80:
        children = _scene_family_walk()
    elif seed < 90:
        return None
    elif seed < 94:
        children = _scene_ufo()
    elif seed < 97:
        children = _scene_abduction()
    else:
        children = _scene_yeti()

    if not children:
        return None
    return render.Box(width = 64, height = 32, child = render.Stack(children = children))

# --- Game overlay: persistent survival simulation rendering ---

# Speed → animation duration mapping (behavioral cues, no stats shown)
GAME_SPEED_DUR = {"slow": 140, "mid": 80, "fast": 50}
GAME_SHIRTS = {"parent1": "#4488cc", "parent2": "#cc4444", "kid": "#44cc44"}

def _build_game_overlay(config):
    """Parse game state params and render characters, threats, crops with behavioral animations."""
    children = []

    # Characters: "id:x:target_x:state:alive:speed"
    gc = config.get("gc", "")
    if gc:
        for entry in gc.split("|"):
            parts = entry.split(":")
            if len(parts) >= 6:
                children.extend(_render_game_char(parts))

    # Pets: "id:x:alive"
    gp = config.get("gp", "")
    if gp:
        for entry in gp.split("|"):
            parts = entry.split(":")
            if len(parts) >= 3:
                children.extend(_render_game_pet(parts))

    # Threats: "type:x:state"
    gt = config.get("gt", "")
    if gt:
        for entry in gt.split("|"):
            parts = entry.split(":")
            if len(parts) >= 3:
                children.extend(_render_game_threat(parts))

    # Crops: "x:stage"
    gcr = config.get("gcr", "")
    if gcr:
        for entry in gcr.split("|"):
            parts = entry.split(":")
            if len(parts) >= 2:
                children.extend(_render_crop(parts))

    if not children:
        return None
    return render.Box(width = 64, height = 32, child = render.Stack(children = children))

def _render_game_char(parts):
    """Render one game character based on state — behavior only, no stats."""
    char_id = parts[0]
    x = int(parts[1])
    target_x = int(parts[2])
    state = parts[3]
    alive = parts[4] == "1"
    speed = parts[5]

    shirt = GAME_SHIRTS.get(char_id, "#4488cc")
    children = []

    if not alive:
        # Gravestone cross at home area (each character offset slightly)
        gx = 28 if char_id == "parent1" else (30 if char_id == "parent2" else 32)
        children.append(render.Padding(pad = (gx, 12, 0, 0), child = render.Box(width = 1, height = 3, color = "#666666")))
        children.append(render.Padding(pad = (gx - 1, 13, 0, 0), child = render.Box(width = 3, height = 1, color = "#666666")))
        return children

    dur = GAME_SPEED_DUR.get(speed, 80)

    if state == "fighting":
        # Rapid jitter — character vibrates at threat position
        children.append(animation.Transformation(
            child = _pixel_person(0, 11, shirt),
            duration = 8,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(x - 1, 0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(x + 1, 0)]),
            ],
        ))
    elif state == "farming":
        # Bobbing up/down at crop position (tending crops)
        children.append(animation.Transformation(
            child = _pixel_person(0, 11, shirt),
            duration = 20,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(x, 0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(x, -1)]),
            ],
        ))
    elif state == "fishing":
        # Sitting at pond edge with twitching fishing rod
        children.append(render.Padding(pad = (x, 10, 0, 0), child = render.Box(width = 1, height = 1, color = CHAR_SKIN)))
        children.append(render.Padding(pad = (x - 1, 11, 0, 0), child = render.Box(width = 3, height = 1, color = shirt)))
        children.append(render.Padding(pad = (x - 1, 12, 0, 0), child = render.Box(width = 2, height = 1, color = CHAR_PANTS)))
        # Rod with twitch
        children.append(render.Padding(pad = (x + 2, 9, 0, 0), child = render.Box(width = 1, height = 1, color = "#885533")))
        children.append(animation.Transformation(
            child = render.Padding(pad = (x + 2, 10, 0, 0), child = render.Box(width = 1, height = 4, color = "#885533")),
            duration = 30,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, 0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(1, 0)]),
            ],
        ))
    elif state == "fleeing":
        # Double-speed dash toward home
        children.append(_walking_person(shirt, x, target_x, 11, 40))
    elif x != target_x:
        # Walking to target at speed determined by HP (hidden)
        children.append(_walking_person(shirt, x, target_x, 11, dur))
    else:
        # Static/idle at position
        children.append(_pixel_person(x, 11, shirt))

    return children

def _render_game_pet(parts):
    """Render game pet (dog/cat) at position."""
    pet_id = parts[0]
    x = int(parts[1])
    alive = parts[2] == "1"
    if not alive:
        return []
    if pet_id == "dog":
        return [_pixel_dog(x, 12)]
    elif pet_id == "cat":
        return [_pixel_cat(x, 13)]
    return []

def _render_game_threat(parts):
    """Render approaching threat with menacing animation."""
    threat_type = parts[0]
    x = int(parts[1])
    children = []

    if threat_type == "yeti":
        # Yeti stomps toward house with slight shake
        children.append(animation.Transformation(
            child = _pixel_yeti(0, 10),
            duration = 15,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(x, 0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(x - 1, 0)]),
            ],
        ))
    elif threat_type == "ufo":
        # UFO hovering at sky level
        children.append(animation.Transformation(
            child = _pixel_ufo(0, 2),
            duration = 20,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(x, 0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(x, -1)]),
            ],
        ))
    elif threat_type == "raider":
        # Raider: red-shirted person walking menacingly
        children.append(animation.Transformation(
            child = _pixel_person(0, 11, "#ff0000"),
            duration = 12,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(x, 0)]),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(x - 1, 0)]),
            ],
        ))

    return children

def _render_crop(parts):
    """Render crop at growth stage 0-3."""
    x = int(parts[0])
    stage = int(parts[1])
    children = []

    if stage == 0:
        # Seed: tiny brown dot
        children.append(render.Padding(pad = (x, 14, 0, 0), child = render.Box(width = 1, height = 1, color = "#885533")))
    elif stage == 1:
        # Sprout: small green shoot
        children.append(render.Padding(pad = (x, 13, 0, 0), child = render.Box(width = 1, height = 2, color = "#228822")))
    elif stage == 2:
        # Grown: taller green with yellow tip
        children.append(render.Padding(pad = (x, 12, 0, 0), child = render.Box(width = 1, height = 3, color = "#228822")))
        children.append(render.Padding(pad = (x, 12, 0, 0), child = render.Box(width = 1, height = 1, color = "#ddaa00")))
    elif stage == 3:
        # Harvestable: golden pulse animation
        children.append(render.Padding(pad = (x, 12, 0, 0), child = render.Box(width = 2, height = 3, color = "#228822")))
        children.append(animation.Transformation(
            child = render.Padding(pad = (x, 12, 0, 0), child = render.Box(width = 2, height = 1, color = "#ddaa00")),
            duration = 15,
            delay = 0,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.8, 0.8)]),
            ],
        ))

    return children

# --- Full-width sky & weather overlay (64x32) ---

def build_sky_background(is_night):
    """Continuous sky background spanning full 64x32. Night: dark navy + stars."""
    if not is_night:
        return None
    children = [
        # Dark navy sky band across full width (top 16px = sky area above icons)
        render.Box(width = 64, height = 16, color = "#0a0a1a"),
    ]
    children.extend(_overlay_stars())
    return render.Box(width = 64, height = 32, child = render.Stack(children = children))

def _overlay_stars():
    """Mix of permanent and twinkling stars across full 64px sky."""
    children = []
    # Permanent (static) stars — dim dots always visible
    for x, y in [(4, 2), (19, 5), (30, 1), (43, 4), (55, 2), (62, 6), (12, 8), (37, 10)]:
        children.append(render.Padding(pad = (x, y, 0, 0),
            child = render.Box(width = 1, height = 1, color = "#555566")))
    # Twinkling stars — animated, spread across all columns
    children.extend([
        _twinkling_star(8, 1, 0), _twinkling_star(25, 3, 12),
        _twinkling_star(35, 6, 7), _twinkling_star(48, 1, 18),
        _twinkling_star(58, 4, 4), _twinkling_star(15, 9, 15),
        _twinkling_star(42, 8, 22), _twinkling_star(52, 11, 10),
    ])
    return children

def build_weather_overlay(weather_icon, is_night):
    """Full-width weather effects (64x32) that overlay across all columns."""
    children = []
    if weather_icon == "thunderstorm":
        children.extend(_overlay_clouds(2))
        children.extend(_overlay_rain())
        children.extend(_overlay_lightning())
    elif weather_icon in WEATHER_RAIN:
        children.extend(_overlay_clouds(1))
        children.extend(_overlay_rain())
    elif weather_icon == "snow":
        children.extend(_overlay_clouds(1))
        children.extend(_overlay_snow())
    elif weather_icon in WEATHER_CLOUD_FULL:
        children.extend(_overlay_clouds(3))
    elif "partly-cloudy" in weather_icon:
        children.extend(_overlay_clouds(1))
    elif weather_icon == "wind":
        children.extend(_overlay_wind())
    elif weather_icon == "fog":
        children.extend(_overlay_fog())
    if not children:
        return None
    return render.Box(width = 64, height = 32, child = render.Stack(children = children))

def _overlay_clouds(count):
    """Clouds drifting across full 64px width."""
    children = []
    configs = [
        ("#3a3a3a", "large", 3, 160, 0),
        ("#555555", "medium", 8, 130, 40),
        ("#4a4a4a", "small", 5, 180, 80),
    ]
    for i in range(min(count, len(configs))):
        color, size, y, dur, delay = configs[i]
        children.append(animation.Transformation(
            child = render.Padding(pad = (0, y, 0, 0), child = _cloud_shape(color = color, size = size)),
            duration = dur,
            delay = delay,
            direction = "normal",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-20, 0)], curve = "linear"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(80, 0)]),
            ],
        ))
    return children

def _overlay_rain():
    """Rain drops falling across full 64px width."""
    children = []
    for x, delay in zip([3, 10, 18, 25, 33, 40, 48, 55, 62], [0, 5, 10, 3, 8, 13, 2, 7, 11]):
        children.append(_rain_drop(x, delay))
    return children

def _overlay_lightning():
    """Lightning bolt near center (house area) with double-flash."""
    bolt_pixels = [
        (31, 3), (30, 4), (31, 4), (29, 5), (30, 5), (30, 6), (31, 6), (31, 7), (32, 7),
    ]
    bolt_children = []
    for bx, by in bolt_pixels:
        bolt_children.append(render.Padding(pad = (bx, by, 0, 0),
            child = render.Box(width = 1, height = 1, color = "#ffff44")))
    children = [animation.Transformation(
        child = render.Stack(children = bolt_children),
        duration = 60,
        delay = 10,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 0.12, transforms = [animation.Scale(1.0, 1.0)]),
            animation.Keyframe(percentage = 0.22, transforms = [animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 0.32, transforms = [animation.Scale(1.0, 1.0)]),
            animation.Keyframe(percentage = 0.42, transforms = [animation.Scale(0.0, 0.0)]),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    )]
    return children

def _overlay_snow():
    """Snowflakes drifting across full 64px width."""
    children = []
    for x, delay in zip([2, 8, 15, 22, 30, 37, 44, 51, 58, 5, 35, 48], [0, 8, 16, 4, 12, 20, 28, 6, 14, 24, 10, 18]):
        children.append(_snow_flake(x, delay))
    return children

def _overlay_wind():
    """Wind streaks spanning full 64px width."""
    children = []
    for y, delay, w in zip([3, 8, 14, 20, 26], [0, 4, 8, 2, 6], [8, 6, 10, 7, 5]):
        children.append(animation.Transformation(
            child = render.Padding(pad = (0, y, 0, 0), child = render.Box(width = w, height = 1, color = WIND_COLOR)),
            duration = 25,
            delay = delay,
            direction = "normal",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-10, 0)], curve = "linear"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(70, 0)]),
            ],
        ))
    return children

def _overlay_fog():
    """Fog bands oscillating across full 64px width."""
    children = []
    for y, delay, gray in zip([3, 9, 16, 22, 28], [0, 10, 20, 5, 15], ["#444444", "#333333", "#3a3a3a", "#383838", "#404040"]):
        children.append(animation.Transformation(
            child = render.Padding(pad = (0, y, 0, 0), child = render.Box(width = 30, height = 2, color = gray)),
            duration = 140,
            delay = delay,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-20, 0)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(40, 0)]),
            ],
        ))
    return children

def _twinkling_star(x, y, delay):
    """Single 1px star that fades in/out at the given position."""
    return render.Padding(
        pad = (x, y, 0, 0),
        child = animation.Transformation(
            child = render.Box(width = 1, height = 1, color = STAR_COLOR),
            duration = 25,
            delay = delay,
            direction = "alternate",
            fill_mode = "forwards",
            keyframes = [
                animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
                animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
            ],
        ),
    )

def _cloud_shape(color = CLOUD_COLOR, size = "medium"):
    """Puffy pixel-art cloud. size: 'small' (8x3), 'medium' (12x4), 'large' (16x5), 'storm' (16x5 dark)."""
    if size == "small":
        return render.Stack(children = [
            # Two bumps on top
            render.Padding(pad = (1, 0, 0, 0), child = render.Box(width = 2, height = 1, color = color)),
            render.Padding(pad = (5, 0, 0, 0), child = render.Box(width = 2, height = 1, color = color)),
            # Merged body
            render.Padding(pad = (1, 1, 0, 0), child = render.Box(width = 6, height = 1, color = color)),
            # Full base
            render.Padding(pad = (0, 2, 0, 0), child = render.Box(width = 8, height = 1, color = color)),
        ])
    elif size == "large":
        return render.Stack(children = [
            # Two bumps
            render.Padding(pad = (3, 0, 0, 0), child = render.Box(width = 3, height = 1, color = color)),
            render.Padding(pad = (9, 0, 0, 0), child = render.Box(width = 3, height = 1, color = color)),
            # Merge
            render.Padding(pad = (2, 1, 0, 0), child = render.Box(width = 10, height = 1, color = color)),
            # Wide body
            render.Padding(pad = (1, 2, 0, 0), child = render.Box(width = 12, height = 1, color = color)),
            # Full base
            render.Padding(pad = (0, 3, 0, 0), child = render.Box(width = 16, height = 1, color = color)),
            # Rounded bottom
            render.Padding(pad = (2, 4, 0, 0), child = render.Box(width = 12, height = 1, color = color)),
        ])
    elif size == "storm":
        dark = "#2a2a2a"
        belly = "#1a1a1a"
        return render.Stack(children = [
            render.Padding(pad = (3, 0, 0, 0), child = render.Box(width = 3, height = 1, color = dark)),
            render.Padding(pad = (9, 0, 0, 0), child = render.Box(width = 3, height = 1, color = dark)),
            render.Padding(pad = (2, 1, 0, 0), child = render.Box(width = 11, height = 1, color = dark)),
            render.Padding(pad = (1, 2, 0, 0), child = render.Box(width = 14, height = 1, color = dark)),
            render.Padding(pad = (0, 3, 0, 0), child = render.Box(width = 16, height = 2, color = belly)),
        ])
    # Default: medium (12x4)
    return render.Stack(children = [
        # Two bumps
        render.Padding(pad = (2, 0, 0, 0), child = render.Box(width = 3, height = 1, color = color)),
        render.Padding(pad = (7, 0, 0, 0), child = render.Box(width = 3, height = 1, color = color)),
        # Merged body
        render.Padding(pad = (1, 1, 0, 0), child = render.Box(width = 10, height = 1, color = color)),
        # Full base
        render.Padding(pad = (0, 2, 0, 0), child = render.Box(width = 12, height = 1, color = color)),
        # Rounded bottom
        render.Padding(pad = (1, 3, 0, 0), child = render.Box(width = 10, height = 1, color = color)),
    ])

def format_power(watts):
    """Format wattage as compact kW: 0W->'0', 676W->'.7', 1920W->'1.9'"""
    w = abs(watts)
    if w < POWER_ZERO_W:
        return "0"
    kw = w / 1000.0
    if kw < 0.95:
        d = int(kw * 10 + 0.5)
        return ".%d" % d
    tenths = int(kw * 10 + 0.5)
    whole = tenths // 10
    frac = tenths % 10
    return "%d.%d" % (whole, frac)
