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

def main(config):
    """Render 3-column energy dashboard: Solar/Weather | Home/Battery | Grid.
    Animated energy flow dots show power direction between columns."""
    battery_pct = int(config.get("battery_pct", "0"))
    solar_power = float(config.get("solar_power", "0"))
    load_power = float(config.get("load_power", "0"))
    grid_power = float(config.get("grid_power", "0"))
    grid_status = config.get("grid_status", "on")
    weather_icon = config.get("weather_icon", "clear-day")

    # Determine column 1 icon: solar panel when producing, weather when not
    if solar_power > 0:
        col1_icon = build_solar_icon()
        solar_flow = 1
    else:
        col1_icon = build_weather_icon(weather_icon)
        solar_flow = 0

    # Determine grid flow direction
    if grid_power < -10:
        grid_flow = 1   # exporting to grid
    elif grid_power > 10:
        grid_flow = -1  # importing from grid
    else:
        grid_flow = 0

    # Format power values
    solar_text = format_power(solar_power)
    load_text = format_power(load_power)
    grid_text = format_power(grid_power)

    solar_color = "#00cc00" if solar_power > 0 else "#666666"

    # Column 1: Solar / Weather
    col1 = render.Column(
        main_align = "space_between",
        cross_align = "center",
        children = [
            col1_icon,
            render.Text(content = solar_text, height = 8, font = "tb-8", color = solar_color),
            render.Text(content = "kW", height = 8, font = "tb-8", color = solar_color),
        ],
    )

    # Column 2: Home + battery bar (load color = green/amber/red by usage)
    if load_power < 2000:
        load_color = "#00cc00"
    elif load_power < 5000:
        load_color = "#ffd11a"
    else:
        load_color = "#ff4400"

    # House icon + seasonal scene items in slot-based layout:
    # [4px left scene] [16px house] [4px right scene] = 24px
    seasonal = get_seasonal_name(config)
    house_icon = build_house_icon(seasonal)
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
        grid_color = "#ff0000"
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
        grid_color = "#00cc00" if grid_power < -10 else "#ffd11a"
        grid_icon = build_grid_icon()

    col3 = render.Column(
        main_align = "space_between",
        cross_align = "center",
        children = [
            render.Box(width = 20, height = 16, child = render.Row(
                main_align = "center",
                children = [grid_icon],
            )),
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

    # Main display: fixed-width columns for centering
    display = render.Stack(
        children = [
            render.Row(
                expanded = True,
                children = [
                    render.Box(width = 20, child = col1),
                    render.Box(width = 24, child = col2),
                    render.Box(width = 20, child = col3),
                ],
            ),
            render.Column(
                children = [
                    render.Box(height = 7),
                    render.Row(expanded = True, children = dots),
                ],
            ),
        ],
    )

    return render.Root(
        delay = 200,
        child = render.Padding(
            pad = (0, 1, 0, 0),
            child = display,
        ),
    )

# --- Pixel-art icons ---

def build_solar_icon():
    """Solar panel pixel art with animated sun, in 20x16 box."""
    panel_color = SOLAR_BLUE
    grid_color = SOLAR_GRID

    # Build panel rows: 3 cols of cells separated by grid lines
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

    # Animated sun rays (pulse in and out) — 5 rays around 3x3 core
    sun_rays = animation.Transformation(
        child = render.Stack(children = [
            render.Padding(pad = (1, 0, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
            render.Padding(pad = (3, 0, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
            render.Padding(pad = (0, 1, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
            render.Padding(pad = (4, 1, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
            render.Padding(pad = (0, 3, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
            render.Padding(pad = (4, 3, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
            render.Padding(pad = (1, 4, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
            render.Padding(pad = (3, 4, 0, 0), child = render.Box(width = 1, height = 1, color = "#ffaa00")),
        ]),
        duration = 18,
        delay = 0,
        direction = "alternate",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
        ],
    )

    return render.Box(
        width = 20,
        height = 16,
        child = render.Stack(children = [
            # Sun core (3x3 yellow, top-left corner)
            render.Padding(pad = (1, 1, 0, 0), child = render.Box(width = 3, height = 3, color = "#ffcc00")),
            # Sun rays (animated pulse around core)
            sun_rays,
            # Panel body starting at y=4 (below sun, aligned with house)
            render.Padding(pad = (4, 4, 0, 0), child = panel),
            # Support post
            render.Padding(pad = (9, 11, 0, 0), child = render.Box(width = 2, height = 2, color = SOLAR_GRAY)),
            # Base
            render.Padding(pad = (7, 13, 0, 0), child = render.Box(width = 6, height = 1, color = SOLAR_GRAY)),
        ]),
    )

def build_house_icon(seasonal = ""):
    """House pixel art, 16x16. Seasonal decorations built in (same coords as house)."""
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
        render.Padding(pad = (3, 8, 0, 0), child = render.Box(width = 10, height = 6, color = HOUSE_WALL)),
        # Window (left side, light blue glow)
        render.Padding(pad = (4, 9, 0, 0), child = render.Box(width = 3, height = 3, color = HOUSE_WINDOW)),
        # Door (right side)
        render.Padding(pad = (9, 10, 0, 0), child = render.Box(width = 3, height = 4, color = HOUSE_DOOR)),
        # Foundation
        render.Padding(pad = (2, 14, 0, 0), child = render.Box(width = 12, height = 1, color = HOUSE_FOUNDATION)),
    ]

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

def _build_burst(x, y, size, colors, delay, duration):
    """Build one radial burst at (x,y). size='small' (5px +) or 'big' (9px full).
    Returns list of animated children."""
    children = []

    if size == "small":
        offsets = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]
    else:
        offsets = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]

    for i, offset in enumerate(offsets):
        dx, dy = offset[0], offset[1]
        px = x + dx
        py = y + dy

        # Clamp to 24x16 bounds
        if px < 0 or px > 23 or py < 0 or py > 15:
            continue

        color = colors[i % len(colors)]
        ripple = i * 1  # stagger each pixel by 1 frame for ripple effect

        if size == "big":
            # Big burst: appear, hold, drift down 1px, fade
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
                            animation.Keyframe(percentage = 0.05, transforms = [animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 0.5, transforms = [animation.Translate(0, 0), animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 0.8, transforms = [animation.Translate(0, 1), animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(0, 2), animation.Scale(0.0, 0.0)]),
                        ],
                    ),
                ),
            )
        else:
            # Small burst: appear and fade (no drift)
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
                            animation.Keyframe(percentage = 0.05, transforms = [animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 0.6, transforms = [animation.Scale(1.0, 1.0)]),
                            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
                        ],
                    ),
                ),
            )

    return children

def _build_fireworks(bg_bursts, fg_bursts, duration):
    """Build layered fireworks. Returns (behind_stack, front_stack) for depth."""
    bg_children = []
    for burst in bg_bursts:
        bg_children.extend(_build_burst(burst[0], burst[1], "small", burst[2], burst[3], duration))

    fg_children = []
    for burst in fg_bursts:
        fg_children.extend(_build_burst(burst[0], burst[1], "big", burst[2], burst[3], duration))

    bg = render.Stack(children = bg_children) if bg_children else None
    fg = render.Stack(children = fg_children) if fg_children else None
    return (bg, fg)

def _july4_fireworks():
    """July 4th: warm, rapid volley across the sky."""
    dim = ["#884400", "#664400", "#886644"]
    bright = ["#ff4400", "#ffcc00", "#ff8800", "#ffffff"]
    bg = [
        (2, 2, dim, 4),
        (21, 3, dim, 16),
        (12, 1, dim, 28),
    ]
    fg = [
        (6, 4, bright, 0),
        (17, 3, bright, 10),
        (11, 5, bright, 22),
    ]
    return _build_fireworks(bg, fg, 36)

def _newyear_fireworks():
    """New Year's: elegant gold/silver celebration."""
    dim = ["#555577", "#446666", "#665588"]
    bright = ["#ffcc00", "#ffffff", "#cc88ff", "#00cccc"]
    bg = [
        (3, 3, dim, 6),
        (20, 2, dim, 24),
    ]
    fg = [
        (8, 4, bright, 0),
        (18, 3, bright, 16),
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

# --- Weather icons for column 1 (20x16 area) ---

def build_weather_icon(weather_icon):
    """Build a 20x16 weather widget for the solar column when solar=0."""
    if weather_icon == "clear-night":
        return _moon_and_stars()
    elif weather_icon == "rain" or weather_icon == "sleet":
        return _rain_icon()
    elif weather_icon == "snow":
        return _snow_icon()
    elif weather_icon == "cloudy" or weather_icon == "overcast":
        return _cloud_icon()
    elif weather_icon == "partly-cloudy-night":
        return _moon_and_cloud()
    elif weather_icon == "partly-cloudy-day":
        return _cloud_icon()
    elif weather_icon == "wind":
        return _wind_icon()
    elif weather_icon == "fog":
        return _fog_icon()
    return _moon_and_stars()

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

def _cloud_shape(color = CLOUD_COLOR, w = 10, h = 3):
    """Small pixel-art cloud: main body + trailing bump."""
    return render.Row(children = [
        render.Box(width = w, height = h, color = color),
        render.Padding(pad = (0, 1, 0, 0), child = render.Box(width = w // 2, height = h - 1, color = color)),
    ])

def _moon_and_stars():
    """Pixel-art crescent moon with twinkling stars in 20x16 area."""
    return render.Box(
        width = 20,
        height = 16,
        child = render.Stack(
            children = [
                # Crescent moon (left-facing, built from pixel rows)
                render.Padding(pad = (10, 3, 0, 0), child = render.Box(width = 1, height = 1, color = MOON_COLOR)),
                render.Padding(pad = (9, 4, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
                render.Padding(pad = (8, 5, 0, 0), child = render.Box(width = 3, height = 2, color = MOON_COLOR)),
                render.Padding(pad = (9, 7, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
                render.Padding(pad = (10, 8, 0, 0), child = render.Box(width = 1, height = 1, color = MOON_COLOR)),
                # Twinkling stars
                _twinkling_star(3, 2, 0),
                _twinkling_star(16, 6, 12),
                _twinkling_star(5, 12, 7),
            ],
        ),
    )

def _moon_and_cloud():
    """Crescent moon with a small drifting cloud."""
    return render.Box(
        width = 20,
        height = 16,
        child = render.Stack(
            children = [
                # Crescent moon (same shape, shifted up)
                render.Padding(pad = (10, 1, 0, 0), child = render.Box(width = 1, height = 1, color = MOON_COLOR)),
                render.Padding(pad = (9, 2, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
                render.Padding(pad = (8, 3, 0, 0), child = render.Box(width = 3, height = 2, color = MOON_COLOR)),
                render.Padding(pad = (9, 5, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
                render.Padding(pad = (10, 6, 0, 0), child = render.Box(width = 1, height = 1, color = MOON_COLOR)),
                # Drifting cloud
                animation.Transformation(
                    child = render.Padding(
                        pad = (0, 9, 0, 0),
                        child = _cloud_shape(w = 8),
                    ),
                    duration = 40,
                    delay = 0,
                    direction = "normal",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-12, 0)], curve = "linear"),
                        animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(22, 0)]),
                    ],
                ),
            ],
        ),
    )

def _rain_icon():
    """Rain drops falling within 20x16 area."""
    drops = []
    for x, delay in zip([3, 10, 17], [0, 5, 2]):
        drops.append(
            render.Padding(
                pad = (x, 0, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 1, height = 2, color = RAIN_COLOR),
                    duration = 12,
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

    # Cloud at top
    drops.append(render.Padding(pad = (4, 0, 0, 0), child = _cloud_shape()))

    return render.Box(width = 20, height = 16, child = render.Stack(children = drops))

def _snow_icon():
    """Snowflakes drifting within 20x16 area."""
    flakes = []
    for x, delay in zip([2, 10, 16], [0, 6, 3]):
        flakes.append(
            render.Padding(
                pad = (x, 0, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 1, height = 1, color = SNOW_COLOR),
                    duration = 20,
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

    # Cloud at top
    flakes.append(render.Padding(pad = (4, 0, 0, 0), child = _cloud_shape()))

    return render.Box(width = 20, height = 16, child = render.Stack(children = flakes))

def _cloud_icon():
    """Drifting clouds within 20x16 area."""
    return render.Box(
        width = 20,
        height = 16,
        child = render.Stack(
            children = [
                # Large cloud
                animation.Transformation(
                    child = render.Padding(pad = (0, 3, 0, 0), child = _cloud_shape()),
                    duration = 35,
                    delay = 0,
                    direction = "normal",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-14, 0)], curve = "linear"),
                        animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(22, 0)]),
                    ],
                ),
                # Small cloud (lighter gray, smaller)
                animation.Transformation(
                    child = render.Padding(pad = (0, 9, 0, 0), child = _cloud_shape(color = "#444444", w = 7, h = 2)),
                    duration = 28,
                    delay = 10,
                    direction = "normal",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-10, 0)], curve = "linear"),
                        animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(22, 0)]),
                    ],
                ),
            ],
        ),
    )

def _wind_icon():
    """Horizontal wind streaks within 20x16 area."""
    streaks = []
    for y, delay in zip([3, 8, 13], [0, 2, 1]):
        streaks.append(
            animation.Transformation(
                child = render.Padding(
                    pad = (0, y, 0, 0),
                    child = render.Box(width = 5, height = 1, color = WIND_COLOR),
                ),
                duration = 6,
                delay = delay,
                direction = "normal",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-6, 0)], curve = "linear"),
                    animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(22, 0)]),
                ],
            ),
        )

    return render.Box(width = 20, height = 16, child = render.Stack(children = streaks))

def _fog_icon():
    """Gray haze drifting within 20x16 area."""
    haze = []
    haze_y = [4, 9, 13]

    for y in haze_y:
        haze.append(
            animation.Transformation(
                child = render.Padding(
                    pad = (0, y, 0, 0),
                    child = render.Box(width = 10, height = 2, color = FOG_COLOR),
                ),
                duration = 30,
                delay = y,
                direction = "alternate",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-8, 0)], curve = "ease_in_out"),
                    animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(12, 0)]),
                ],
            ),
        )

    return render.Box(width = 20, height = 16, child = render.Stack(children = haze))

def format_power(watts):
    """Format wattage as compact kW: 0W->'0', 676W->'.7', 1920W->'1.9'"""
    w = abs(watts)
    if w < 50:
        return "0"
    kw = w / 1000.0
    if kw < 0.95:
        d = int(kw * 10 + 0.5)
        return ".%d" % d
    tenths = int(kw * 10 + 0.5)
    whole = tenths // 10
    frac = tenths % 10
    return "%d.%d" % (whole, frac)
