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

    # Column 2: Home + battery %
    col2 = render.Column(
        main_align = "space_between",
        cross_align = "center",
        children = [
            render.Box(width = 21, height = 16, child = render.Row(
                main_align = "center",
                children = [render.Image(src = HOUSE)],
            )),
            render.Text(content = load_text, height = 8, font = "tb-8", color = "#ffd11a"),
            build_battery_bar(battery_pct),
        ],
    )

    # Column 3: Grid
    grid_color = "#ffd11a"
    if grid_status != "on" and grid_status != "On":
        grid_color = "#ff0000"
    elif grid_power < -10:
        grid_color = "#00cc00"

    col3 = render.Column(
        main_align = "space_between",
        cross_align = "center",
        children = [
            render.Box(width = 21, height = 16, child = render.Row(
                main_align = "center",
                children = [render.Image(src = GRID)],
            )),
            render.Text(content = grid_text, height = 8, font = "tb-8", color = grid_color),
            render.Text(content = "kW", height = 8, font = "tb-8", color = grid_color),
        ],
    )

    # Energy flow dots row (dots are 10px wide, centered at column boundaries)
    dots = [render.Box(width = 17)]

    # Solar -> Home flow dots (centered at x=22)
    if solar_flow:
        dots.append(render.Image(src = DOTS_LTR))
    else:
        dots.append(render.Box(width = 10))

    dots.append(render.Box(width = 10))

    # Grid <-> Home flow dots (centered at x=42)
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
                    render.Box(width = 22, child = col1),
                    render.Box(width = 20, child = col2),
                    render.Box(width = 22, child = col3),
                ],
            ),
            render.Column(
                children = [
                    render.Box(height = 8),
                    render.Row(expanded = True, children = dots),
                ],
            ),
        ],
    )

    return render.Root(
        delay = 200,
        child = display,
    )

# --- Battery bar (outlined battery icon with gradient segments) ---

def build_battery_bar(battery_pct):
    """Build a battery icon: 17x7 outline body + 1px nub, 8 gradient segments inside."""
    filled = int(battery_pct * 8 / 100)
    if battery_pct > 0 and filled == 0:
        filled = 1

    # Build interior segment row (8 segments × 1px + 7 gaps × 1px = 15px)
    segs = []
    for i in range(8):
        color = BATT_GRADIENT[i] if i < filled else BATT_EMPTY
        segs.append(render.Box(width = 1, height = 5, color = color))
        if i < 7:
            segs.append(render.Box(width = 1, height = 5))

    interior = render.Row(children = segs)

    return render.Row(
        children = [
            render.Stack(
                children = [
                    render.Box(width = 17, height = 7, color = BATT_OUTLINE),
                    render.Padding(
                        pad = (1, 1, 1, 1),
                        child = render.Box(width = 15, height = 5, color = "#000000", child = interior),
                    ),
                ],
            ),
            render.Padding(
                pad = (0, 2, 0, 0),
                child = render.Box(width = 1, height = 3, color = BATT_OUTLINE),
            ),
        ],
    )

# --- Weather icons for column 1 (21x16 area) ---

def build_weather_icon(weather_icon):
    """Build a 21x16 weather widget for the solar column when solar=0."""
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

def _moon_and_stars():
    """Pixel-art crescent moon with twinkling stars in 21x16 area."""
    return render.Box(
        width = 21,
        height = 16,
        child = render.Stack(
            children = [
                # Crescent moon built from pixel rows (left-facing crescent)
                # Top tip
                render.Padding(pad = (10, 3, 0, 0), child = render.Box(width = 1, height = 1, color = MOON_COLOR)),
                # Upper body
                render.Padding(pad = (9, 4, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
                # Wide middle
                render.Padding(pad = (8, 5, 0, 0), child = render.Box(width = 3, height = 2, color = MOON_COLOR)),
                # Lower body
                render.Padding(pad = (9, 7, 0, 0), child = render.Box(width = 2, height = 1, color = MOON_COLOR)),
                # Bottom tip
                render.Padding(pad = (10, 8, 0, 0), child = render.Box(width = 1, height = 1, color = MOON_COLOR)),
                # Star 1 (top-left)
                render.Padding(
                    pad = (3, 2, 0, 0),
                    child = animation.Transformation(
                        child = render.Box(width = 1, height = 1, color = STAR_COLOR),
                        duration = 25,
                        delay = 0,
                        direction = "alternate",
                        fill_mode = "forwards",
                        keyframes = [
                            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
                            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
                        ],
                    ),
                ),
                # Star 2 (right)
                render.Padding(
                    pad = (16, 6, 0, 0),
                    child = animation.Transformation(
                        child = render.Box(width = 1, height = 1, color = STAR_COLOR),
                        duration = 25,
                        delay = 12,
                        direction = "alternate",
                        fill_mode = "forwards",
                        keyframes = [
                            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
                            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
                        ],
                    ),
                ),
                # Star 3 (bottom-left)
                render.Padding(
                    pad = (5, 12, 0, 0),
                    child = animation.Transformation(
                        child = render.Box(width = 1, height = 1, color = STAR_COLOR),
                        duration = 25,
                        delay = 7,
                        direction = "alternate",
                        fill_mode = "forwards",
                        keyframes = [
                            animation.Keyframe(percentage = 0.0, transforms = [animation.Scale(1.0, 1.0)], curve = "ease_in_out"),
                            animation.Keyframe(percentage = 1.0, transforms = [animation.Scale(0.0, 0.0)]),
                        ],
                    ),
                ),
            ],
        ),
    )

def _moon_and_cloud():
    """Crescent moon with a small drifting cloud."""
    return render.Box(
        width = 21,
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
                        child = render.Row(
                            children = [
                                render.Box(width = 8, height = 3, color = CLOUD_COLOR),
                                render.Padding(
                                    pad = (0, 1, 0, 0),
                                    child = render.Box(width = 4, height = 2, color = CLOUD_COLOR),
                                ),
                            ],
                        ),
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
    """Rain drops falling within 21x16 area."""
    drops = []
    drop_x = [3, 10, 17]
    drop_delays = [0, 5, 2]

    for i in range(len(drop_x)):
        drops.append(
            render.Padding(
                pad = (drop_x[i], 0, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 1, height = 2, color = RAIN_COLOR),
                    duration = 12,
                    delay = drop_delays[i],
                    direction = "normal",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(0, -3)], curve = "linear"),
                        animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(0, 18)]),
                    ],
                ),
            ),
        )

    # Small cloud at top
    drops.append(
        render.Padding(
            pad = (4, 0, 0, 0),
            child = render.Row(
                children = [
                    render.Box(width = 10, height = 3, color = CLOUD_COLOR),
                    render.Padding(pad = (0, 1, 0, 0), child = render.Box(width = 4, height = 2, color = CLOUD_COLOR)),
                ],
            ),
        ),
    )

    return render.Box(width = 21, height = 16, child = render.Stack(children = drops))

def _snow_icon():
    """Snowflakes drifting within 21x16 area."""
    flakes = []
    flake_x = [2, 10, 16]
    flake_delays = [0, 6, 3]

    for i in range(len(flake_x)):
        flakes.append(
            render.Padding(
                pad = (flake_x[i], 0, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 1, height = 1, color = SNOW_COLOR),
                    duration = 20,
                    delay = flake_delays[i],
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
    flakes.append(
        render.Padding(
            pad = (4, 0, 0, 0),
            child = render.Row(
                children = [
                    render.Box(width = 10, height = 3, color = CLOUD_COLOR),
                    render.Padding(pad = (0, 1, 0, 0), child = render.Box(width = 4, height = 2, color = CLOUD_COLOR)),
                ],
            ),
        ),
    )

    return render.Box(width = 21, height = 16, child = render.Stack(children = flakes))

def _cloud_icon():
    """Drifting clouds within 21x16 area."""
    return render.Box(
        width = 21,
        height = 16,
        child = render.Stack(
            children = [
                # Cloud 1
                animation.Transformation(
                    child = render.Padding(
                        pad = (0, 3, 0, 0),
                        child = render.Row(
                            children = [
                                render.Box(width = 10, height = 3, color = CLOUD_COLOR),
                                render.Padding(pad = (0, 1, 0, 0), child = render.Box(width = 4, height = 2, color = CLOUD_COLOR)),
                            ],
                        ),
                    ),
                    duration = 35,
                    delay = 0,
                    direction = "normal",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-14, 0)], curve = "linear"),
                        animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(22, 0)]),
                    ],
                ),
                # Cloud 2
                animation.Transformation(
                    child = render.Padding(
                        pad = (0, 9, 0, 0),
                        child = render.Row(
                            children = [
                                render.Box(width = 7, height = 2, color = "#444444"),
                                render.Padding(pad = (0, 1, 0, 0), child = render.Box(width = 3, height = 1, color = "#444444")),
                            ],
                        ),
                    ),
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
    """Horizontal wind streaks within 21x16 area."""
    streaks = []
    streak_y = [3, 8, 13]
    streak_delays = [0, 2, 1]

    for i in range(len(streak_y)):
        streaks.append(
            animation.Transformation(
                child = render.Padding(
                    pad = (0, streak_y[i], 0, 0),
                    child = render.Box(width = 5, height = 1, color = WIND_COLOR),
                ),
                duration = 6,
                delay = streak_delays[i],
                direction = "normal",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(percentage = 0.0, transforms = [animation.Translate(-6, 0)], curve = "linear"),
                    animation.Keyframe(percentage = 1.0, transforms = [animation.Translate(22, 0)]),
                ],
            ),
        )

    return render.Box(width = 21, height = 16, child = render.Stack(children = streaks))

def _fog_icon():
    """Gray haze drifting within 21x16 area."""
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

    return render.Box(width = 21, height = 16, child = render.Stack(children = haze))

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
