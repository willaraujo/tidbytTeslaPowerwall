"""
Applet: Powerwall Weather
Summary: Tesla Powerwall + Weather
Description: Energy monitor for Tesla Powerwall 3. At night, the solar column becomes a weather display.
Author: willaraujo
"""

load("encoding/base64.star", "base64")
load("render.star", "render")
load("animation.star", "animation")

# Icons (base64-encoded PNGs)
SOLAR_PANEL = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAABUAAAAQCAYAAAD52jQlAAAArElEQVQ4ja2T2xGFIAxETxyrcOhM" +
    "y7M0xzb2fjA4kYcPrvsFCSzhBExCZDLDAHwuxZ5ovEq+MfIaWkYSqt3ikdLmlkG38dcmx1U9v2h8" +
    "721mVeaNRgkwpjCzbytTWABO43i4VDMe44lYqlaS4sb5ttKWiu5faQoL+7ae5pLKd+4ntQVPlCMo" +
    "mHpmOcNWLGc7+ES+uFevmELJNcU8ugG+rRKOx9/XoKph40P8rR8wcGBXI4UlEQAAAABJRU5ErkJg" +
    "gg=="
)

GRID = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAt0lEQVQ4jYWQuxEDIQxEhcfFeIZm" +
    "HEEtTimHTmiBa4KYZC+xGKEToITR5+0KEYkAADIi54ycM6z+2wIkSEQUQnArg4cAQxJk+LouAgDn" +
    "nNPcULdcaq2Q/VrrPNN7BwDI1zIopTzvwMN6Ay2y2/A4oGsyf5lqiyil7N13OcPmHU4DMk/Rj/7v" +
    "+8E0wCJaoLWGFD1S9OB8wKcNJMiuE7z6swanlXcwg7puwlJAO8pDLWG5rlXfgv+4AXBeHhx5xCS7" +
    "AAAAAElFTkSuQmCC"
)

HOUSE = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAb0lEQVQ4jcWQQQrAMAgE19KX9dL/" +
    "v2h7arDRFT1VCIHEGVYBUbxu+ntUCybnkgBPJDu83jsSBbckGUyC7yklOnYUaEkSWwlcPwHQPGxm" +
    "ls2fJQj9anmVAADOTlOVLhXsQJXuUB/d+l/w2UE1q/p7AIUnlBV3qmXkAAAAAElFTkSuQmCC"
)

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

# Battery bar gradient colors (8 segments, red → green)
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
        col1_icon = render.Image(src = SOLAR_PANEL)
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

    col2 = render.Column(
        main_align = "space_between",
        cross_align = "center",
        children = [
            render.Box(width = 24, height = 16, child = render.Row(
                main_align = "center",
                children = [render.Image(src = HOUSE)],
            )),
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
            child = render.Image(src = GRID),
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
        grid_icon = render.Image(src = GRID)

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
                    render.Box(height = 16),
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

# --- Battery bar (outlined battery icon with gradient segments) ---

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
