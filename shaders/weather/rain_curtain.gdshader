shader_type canvas_item;
render_mode unshaded, blend_mix;

// 一次片元哈希生成一条落下的雨线。三份材质各自代表远、中、近景。
uniform vec2 canvas_size = vec2(1600.0, 600.0);
uniform float clock_seconds = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float density : hint_range(0.0, 1.0) = 0.7;
uniform float layer_opacity : hint_range(0.0, 1.0) = 0.4;
uniform float rain_speed = 800.0;
uniform float streak_length = 34.0;
uniform float streak_width = 1.3;
uniform float cell_width = 15.0;
uniform float cell_height = 100.0;
uniform float slant = 0.14;
uniform float gust = 0.0;
uniform float wind_density = 0.0;
uniform vec4 rain_color : source_color = vec4(0.74, 0.83, 0.92, 1.0);

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// UV 遮罩不依赖贴图或动画帧资源，雨线在水平/竖直格子边界连续移动。
float rain_streak(vec2 pixel, vec2 seed_offset, float speed_factor) {
    float skew = slant + 0.33 * gust;
    vec2 motion = vec2(pixel.x - skew * pixel.y, pixel.y - clock_seconds * rain_speed * speed_factor);
    vec2 cell_span = vec2(cell_width, cell_height);
    vec2 grid = floor(motion / cell_span + seed_offset);
    vec2 local = fract(motion / cell_span + seed_offset) * cell_span;
    float seed = hash21(grid + 13.7);
    float enabled = step(1.0 - clamp(density * intensity * (0.90 + wind_density * 0.17), 0.0, 1.0), seed);
    float lane_x = (0.12 + hash21(grid + 3.1) * 0.76) * cell_width;
    float length_px = streak_length * mix(0.65, 1.3, hash21(grid + 6.6));
    float start_y = hash21(grid + 19.3) * max(cell_height - length_px, 2.0);
    float line_x = 1.0 - smoothstep(streak_width * 0.2, streak_width * 1.35, abs(local.x - lane_x));
    float line_y = smoothstep(start_y, start_y + 3.5, local.y) *
        (1.0 - smoothstep(start_y + length_px - 5.0, start_y + length_px, local.y));
    float taper = mix(0.6, 1.0, hash21(grid + 24.7));
    return enabled * line_x * line_y * taper;
}

void fragment() {
    vec2 px = UV * canvas_size;
    // 第二次独立取样错开雨线，提高暴雨密度但每层仍仅两次低成本哈希。
    float streaks = rain_streak(px, vec2(0.0), 1.0);
    streaks = max(streaks, rain_streak(px, vec2(0.47, 0.29), 0.87) * 0.72);
    float alpha = clamp(streaks * layer_opacity * pow(intensity, 0.88), 0.0, 0.72);
    COLOR = vec4(rain_color.rgb, alpha);
}
