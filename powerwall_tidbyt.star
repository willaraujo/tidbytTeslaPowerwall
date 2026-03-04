"""
Applet: Powerwall Weather
Summary: Tesla Powerwall + Weather
Description: Energy production and consumption monitor for Tesla Powerwall 3 with animated weather effects. Pulls data from Home Assistant.
Author: willaraujo
"""

load("encoding/base64.star", "base64")
load("math.star", "math")
load("render.star", "render")
load("animation.star", "animation")

# Icons from the Tesla Solar community app (base64-encoded PNGs)
SOLAR_PANEL = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAABUAAAAQCAYAAAD52jQlAAAArElEQVQ4ja2T2xGFIAxETxyrcOhM"
    "y7M0xzb2fjA4kYcPrvsFCSzhBExCZDLDAHwuxZ5ovEq+MfIaWkYSqt3ikdLmlkG38dcmx1U9v2h8"
    "721mVeaNRgkwpjCzbytTWABO43i4VDMe44lYqlaS4sb5ttKWiu5faQoL+7ae5pLKd+4ntQVPlCMo"
    "mHpmOcNWLGc7+ES+uFevmELJNcU8ugG+rRKOx9/XoKph40P8rR8wcGBXI4UlEQAAAABJRU5ErkJg"
    "gg=="
)

SOLAR_PANEL_OFF = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAABUAAAAQCAYAAAD52jQlAAAAd0lEQVQ4je2TwQrAIAxDo+y7e+iP"
    "d5cJtY0iustgOWklsb4i8OsTKqxoZrZkLoX6r5FBRAAAqkrX7XIWXFmX3rijFDqTiEBVuz1D1bW+"
    "yjKFBaSJqX96ZDiqRbbVH5yyTKGrilxbzaOrwLtdAs+gdgdEAwcf4lg3XnREWPIOZLAAAAAASUVO"
    "RK5CYII="
)

GRID = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAt0lEQVQ4jYWQuxEDIQxEhcfFeIZm"
    "HEEtTimHTmiBa4KYZC+xGKEToITR5+0KEYkAADIi54ycM6z+2wIkSEQUQnArg4cAQxJk+LouAgDn"
    "nNPcULdcaq2Q/VrrPNN7BwDI1zIopTzvwMN6Ay2y2/A4oGsyf5lqiyil7N13OcPmHU4DMk/Rj/7v"
    "+8E0wCJaoLWGFD1S9OB8wKcNJMiuE7z6swanlXcwg7puwlJAO8pDLWG5rlXfgv+4AXBeHhx5xCS7"
    "AAAAAElFTkSuQmCC"
)

HOUSE = base64.decode(
    "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAb0lEQVQ4jcWQQQrAMAgE19KX9dL/"
    "v2h7arDRFT1VCIHEGVYBUbxu+ntUCybnkgBPJDu83jsSBbckGUyC7yklOnYUaEkSWwlcPwHQPGxm"
    "ls2fJQj9anmVAADOTlOVLhXsQJXuUB/d+l/w2UE1q/p7AIUnlBV3qmXkAAAAAElFTkSuQmCC"
)

# Animated energy flow dots (GIF)
DOTS_LTR = base64.decode(
    "R0lGODlhCgAFAIABAA31VAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJDwABACwAAAAACgAFAAAC"
    "CYyPmWAc7pRMBQAh+QQJDwABACwAAAAACgAFAAACCIyPqWAcrmIsACH5BAkPAAEALAAAAAAKAAUA"
    "AAIIjI+pAda8oioAOw=="
)

DOTS_RTL = base64.decode(
    "R0lGODlhCgAFAIABAP/RGwAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJDwABACwAAAAACgAFAAAC"
    "CIyPqQHWvKIqACH5BAkPAAEALAAAAAAKAAUAAAIIjI+pYByuYiwAIfkECQ8AAQAsAAAAAAoABQAA"
    "AgmMj5lgHO6UTAUAOw=="
)

# Weather condition colors
RAIN_COLOR = "#4488CC"
SNOW_COLOR = "#CCDDFF"
SUN_GLOW_COLOR = "#332200"
STAR_COLOR = "#FFFFFF"
CLOUD_COLOR = "#444444"
WIND_COLOR = "#667788"

def main(config):
    battery_pct = int(config.get("battery_pct", "0"))
    solar_power = float(config.get("solar_power", "0"))
    load_power = float(config.get("load_power", "0"))
    grid_power = float(config.get("grid_power", "0"))
    grid_status = config.get("grid_status", "on")
    weather_icon = config.get("weather_icon", "clear-day")
    temperature = config.get("temperature", "")

    # Determine solar icon
    if solar_power > 0:
        solar_img = SOLAR_PANEL
        solar_flow = 1
    else:
        solar_img = SOLAR_PANEL_OFF
        solar_flow = 0

    # Determine grid flow direction
    if grid_power < -10:
        grid_flow = 1   # exporting to grid (left to right from home)
    elif grid_power > 10:
        grid_flow = -1  # importing from grid (right to left)
    else:
        grid_flow = 0   # no significant flow

    # Format power values
    solar_text = format_power(solar_power)
    load_text = format_power(load_power)
    grid_text = format_power(grid_power)

    # Battery color
    batt_color = "#00cc00"
    if battery_pct < 5:
        batt_color = "#ff0000"
    elif battery_pct < 20:
        batt_color = "#ff6600"

    # Unit text - show battery % in home column, kW elsewhere
    batt_unit = "%d%%" % battery_pct

    # Build the three data columns
    columns = []

    # Column 1: Solar
    columns.append(
        render.Column(
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Image(src = solar_img),
                render.Text(
                    content = solar_text,
                    height = 8,
                    font = "tb-8",
                    color = "#ffd11a" if solar_power > 0 else "#666666",
                ),
                render.Text(
                    content = "kW",
                    height = 8,
                    font = "tb-8",
                    color = "#ffd11a" if solar_power > 0 else "#666666",
                ),
            ],
        ),
    )

    # Column 2: Home (with battery % as unit)
    columns.append(
        render.Column(
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Image(src = HOUSE),
                render.Text(
                    content = load_text,
                    height = 8,
                    font = "tb-8",
                    color = "#ffd11a",
                ),
                render.Text(
                    content = batt_unit,
                    height = 8,
                    font = "tb-8",
                    color = batt_color,
                ),
            ],
        ),
    )

    # Column 3: Grid
    grid_color = "#ffd11a"
    if grid_status != "on" and grid_status != "On":
        grid_color = "#ff0000"
    columns.append(
        render.Column(
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Image(src = GRID),
                render.Text(
                    content = grid_text,
                    height = 8,
                    font = "tb-8",
                    color = grid_color,
                ),
                render.Text(
                    content = "kW",
                    height = 8,
                    font = "tb-8",
                    color = grid_color,
                ),
            ],
        ),
    )

    # Build energy flow dots row
    dots = [render.Box(width = 18)]

    # Solar -> Home flow dots
    if solar_flow:
        dots.append(
            render.Stack(children = [render.Box(width = 21), render.Image(src = DOTS_LTR)]),
        )
    else:
        dots.append(render.Stack(children = [render.Box(width = 21), render.Box(width = 10)]))

    # Grid <-> Home flow dots
    if grid_flow == -1:
        dots.append(
            render.Stack(children = [render.Box(width = 21), render.Image(src = DOTS_RTL)]),
        )
    elif grid_flow == 1:
        dots.append(
            render.Stack(children = [render.Box(width = 21), render.Image(src = DOTS_LTR)]),
        )
    else:
        dots.append(render.Stack(children = [render.Box(width = 21), render.Box(width = 10)]))

    # Main data display
    data_layer = render.Stack(
        children = [
            render.Row(
                expanded = True,
                main_align = "space_between",
                children = columns,
            ),
            render.Column(
                children = [
                    render.Box(height = 8),
                    render.Row(expanded = True, children = dots),
                ],
            ),
        ],
    )

    # Build weather animation overlay
    weather_layer = build_weather_animation(weather_icon)

    # Stack weather behind data
    if weather_layer:
        display = render.Stack(
            children = [
                weather_layer,
                data_layer,
            ],
        )
    else:
        display = data_layer

    return render.Root(
        delay = 100,
        child = display,
    )

def build_weather_animation(weather_icon):
    """Build ambient weather animation overlay based on condition."""
    if weather_icon == "rain" or weather_icon == "sleet":
        return rain_animation()
    elif weather_icon == "snow":
        return snow_animation()
    elif weather_icon == "clear-day":
        return sun_animation()
    elif weather_icon == "clear-night":
        return night_animation()
    elif weather_icon == "cloudy":
        return cloud_animation()
    elif weather_icon == "overcast":
        return overcast_animation()
    elif weather_icon == "partly-cloudy-day":
        return partly_cloudy_day_animation()
    elif weather_icon == "partly-cloudy-night":
        return partly_cloudy_night_animation()
    elif weather_icon == "wind":
        return wind_animation()
    elif weather_icon == "fog":
        return fog_animation()
    return None

def rain_animation():
    """Animated rain drops falling across the display."""
    drops = []
    # Create several rain drops at different X positions and timing offsets
    drop_positions = [5, 18, 32, 47, 58]
    drop_delays = [0, 12, 6, 18, 3]

    for i in range(len(drop_positions)):
        x = drop_positions[i]
        delay = drop_delays[i]
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
                        animation.Keyframe(
                            percentage = 0.0,
                            transforms = [animation.Translate(0, -4)],
                            curve = "linear",
                        ),
                        animation.Keyframe(
                            percentage = 1.0,
                            transforms = [animation.Translate(0, 34)],
                        ),
                    ],
                ),
            ),
        )

    return render.Stack(children = drops)

def snow_animation():
    """Animated snowflakes drifting down slowly."""
    flakes = []
    flake_x = [3, 15, 28, 42, 55]
    flake_delays = [0, 15, 8, 22, 5]

    for i in range(len(flake_x)):
        x = flake_x[i]
        delay = flake_delays[i]
        # Snow drifts with slight horizontal wobble
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
                        animation.Keyframe(
                            percentage = 0.0,
                            transforms = [animation.Translate(0, -2)],
                            curve = "linear",
                        ),
                        animation.Keyframe(
                            percentage = 0.5,
                            transforms = [animation.Translate(2, 16)],
                            curve = "ease_in_out",
                        ),
                        animation.Keyframe(
                            percentage = 1.0,
                            transforms = [animation.Translate(-1, 34)],
                        ),
                    ],
                ),
            ),
        )

    return render.Stack(children = flakes)

def sun_animation():
    """Subtle yellow glow pixels for sunny conditions."""
    rays = []
    # Small yellow dots at edges that pulse
    ray_positions = [(0, 0), (60, 0), (0, 28), (60, 28), (30, 0)]

    for pos in ray_positions:
        x, y = pos[0], pos[1]
        rays.append(
            render.Padding(
                pad = (x, y, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 2, height = 2, color = SUN_GLOW_COLOR),
                    duration = 40,
                    delay = 0,
                    direction = "alternate",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(
                            percentage = 0.0,
                            transforms = [animation.Scale(1.0, 1.0)],
                            curve = "ease_in_out",
                        ),
                        animation.Keyframe(
                            percentage = 1.0,
                            transforms = [animation.Scale(0.0, 0.0)],
                        ),
                    ],
                ),
            ),
        )

    return render.Stack(children = rays)

def night_animation():
    """Dark background with twinkling star dots."""
    stars = []
    star_positions = [(4, 2), (22, 5), (50, 1), (38, 3), (12, 28)]
    star_delays = [0, 20, 10, 30, 15]

    for i in range(len(star_positions)):
        x, y = star_positions[i][0], star_positions[i][1]
        delay = star_delays[i]
        stars.append(
            render.Padding(
                pad = (x, y, 0, 0),
                child = animation.Transformation(
                    child = render.Box(width = 1, height = 1, color = STAR_COLOR),
                    duration = 40,
                    delay = delay,
                    direction = "alternate",
                    fill_mode = "forwards",
                    keyframes = [
                        animation.Keyframe(
                            percentage = 0.0,
                            transforms = [animation.Scale(1.0, 1.0)],
                            curve = "ease_in_out",
                        ),
                        animation.Keyframe(
                            percentage = 1.0,
                            transforms = [animation.Scale(0.0, 0.0)],
                        ),
                    ],
                ),
            ),
        )

    return render.Stack(children = stars)

def cloud_animation():
    """Multiple cloud shapes drifting at different heights and speeds."""
    clouds = []
    # Cloud clusters: (y_position, width, height, speed_duration, delay, color)
    cloud_defs = [
        (1, 10, 3, 90, 0, "#3a3a3a"),
        (5, 6, 2, 70, 30, "#444444"),
        (26, 8, 2, 85, 50, "#3a3a3a"),
    ]

    for cloud_def in cloud_defs:
        y, w, h, dur, delay, color = cloud_def[0], cloud_def[1], cloud_def[2], cloud_def[3], cloud_def[4], cloud_def[5]
        clouds.append(
            animation.Transformation(
                child = render.Padding(
                    pad = (0, y, 0, 0),
                    child = render.Row(
                        children = [
                            render.Box(width = w, height = h, color = color),
                            render.Padding(
                                pad = (0, 1, 0, 0),
                                child = render.Box(width = int(w / 2), height = max(h - 1, 1), color = color),
                            ),
                        ],
                    ),
                ),
                duration = dur,
                delay = delay,
                direction = "normal",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(
                        percentage = 0.0,
                        transforms = [animation.Translate(-15, 0)],
                        curve = "linear",
                    ),
                    animation.Keyframe(
                        percentage = 1.0,
                        transforms = [animation.Translate(70, 0)],
                    ),
                ],
            ),
        )

    return render.Stack(children = clouds)

def overcast_animation():
    """Heavy cloud cover -- more clouds, darker, multiple layers."""
    clouds = []
    # Dense cloud layer: (y, width, height, duration, delay, color)
    cloud_defs = [
        (0, 12, 3, 100, 0, "#333333"),
        (2, 8, 2, 75, 15, "#3a3a3a"),
        (4, 10, 3, 90, 40, "#2e2e2e"),
        (14, 7, 2, 80, 25, "#333333"),
        (24, 9, 3, 85, 10, "#2e2e2e"),
        (27, 6, 2, 70, 50, "#3a3a3a"),
    ]

    for cloud_def in cloud_defs:
        y, w, h, dur, delay, color = cloud_def[0], cloud_def[1], cloud_def[2], cloud_def[3], cloud_def[4], cloud_def[5]
        clouds.append(
            animation.Transformation(
                child = render.Padding(
                    pad = (0, y, 0, 0),
                    child = render.Row(
                        children = [
                            render.Box(width = w, height = h, color = color),
                            render.Padding(
                                pad = (0, 1, 0, 0),
                                child = render.Box(width = int(w / 2), height = max(h - 1, 1), color = color),
                            ),
                        ],
                    ),
                ),
                duration = dur,
                delay = delay,
                direction = "normal",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(
                        percentage = 0.0,
                        transforms = [animation.Translate(-15, 0)],
                        curve = "linear",
                    ),
                    animation.Keyframe(
                        percentage = 1.0,
                        transforms = [animation.Translate(70, 0)],
                    ),
                ],
            ),
        )

    return render.Stack(children = clouds)

def partly_cloudy_day_animation():
    """Sun glow with a single small cloud drifting through."""
    sun = sun_animation()
    # Just one small cloud -- "partly" means mostly clear
    cloud = animation.Transformation(
        child = render.Padding(
            pad = (0, 2, 0, 0),
            child = render.Row(
                children = [
                    render.Box(width = 7, height = 2, color = "#444444"),
                    render.Padding(
                        pad = (0, 1, 0, 0),
                        child = render.Box(width = 3, height = 1, color = "#444444"),
                    ),
                ],
            ),
        ),
        duration = 90,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(
                percentage = 0.0,
                transforms = [animation.Translate(-12, 0)],
                curve = "linear",
            ),
            animation.Keyframe(
                percentage = 1.0,
                transforms = [animation.Translate(70, 0)],
            ),
        ],
    )
    return render.Stack(children = [sun, cloud])

def partly_cloudy_night_animation():
    """Stars with a single small cloud drifting through."""
    stars = night_animation()
    cloud = animation.Transformation(
        child = render.Padding(
            pad = (0, 2, 0, 0),
            child = render.Row(
                children = [
                    render.Box(width = 7, height = 2, color = "#3a3a3a"),
                    render.Padding(
                        pad = (0, 1, 0, 0),
                        child = render.Box(width = 3, height = 1, color = "#3a3a3a"),
                    ),
                ],
            ),
        ),
        duration = 90,
        delay = 0,
        direction = "normal",
        fill_mode = "forwards",
        keyframes = [
            animation.Keyframe(
                percentage = 0.0,
                transforms = [animation.Translate(-12, 0)],
                curve = "linear",
            ),
            animation.Keyframe(
                percentage = 1.0,
                transforms = [animation.Translate(70, 0)],
            ),
        ],
    )
    return render.Stack(children = [stars, cloud])

def wind_animation():
    """Fast horizontal streaks for windy/hurricane conditions."""
    streaks = []
    streak_y = [3, 10, 18, 25, 30]
    streak_delays = [0, 5, 2, 8, 4]

    for i in range(len(streak_y)):
        y = streak_y[i]
        delay = streak_delays[i]
        streaks.append(
            animation.Transformation(
                child = render.Padding(
                    pad = (0, y, 0, 0),
                    child = render.Box(width = 4, height = 1, color = WIND_COLOR),
                ),
                duration = 15,
                delay = delay,
                direction = "normal",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(
                        percentage = 0.0,
                        transforms = [animation.Translate(-6, 0)],
                        curve = "linear",
                    ),
                    animation.Keyframe(
                        percentage = 1.0,
                        transforms = [animation.Translate(68, 0)],
                    ),
                ],
            ),
        )

    return render.Stack(children = streaks)

def fog_animation():
    """Low-opacity gray haze drifting slowly."""
    haze = []
    haze_y = [8, 18, 26]

    for y in haze_y:
        haze.append(
            animation.Transformation(
                child = render.Padding(
                    pad = (0, y, 0, 0),
                    child = render.Box(width = 12, height = 2, color = "#222222"),
                ),
                duration = 100,
                delay = y * 3,
                direction = "alternate",
                fill_mode = "forwards",
                keyframes = [
                    animation.Keyframe(
                        percentage = 0.0,
                        transforms = [animation.Translate(-15, 0)],
                        curve = "ease_in_out",
                    ),
                    animation.Keyframe(
                        percentage = 1.0,
                        transforms = [animation.Translate(55, 0)],
                    ),
                ],
            ),
        )

    return render.Stack(children = haze)

def format_power(watts):
    """Format wattage: '1.92' for >=1000W, '784' for <1000W, '0' for 0."""
    w = abs(watts)
    if w < 1:
        return "0"
    elif w >= 1000:
        return "%.2f" % (w / 1000.0)
    else:
        return "%d" % int(w)
