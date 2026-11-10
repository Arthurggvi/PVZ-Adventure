shader_type canvas_item;
render_mode unshaded, blend_mix;

// 薄水圈 + 上溅水点，随雨势提高密度与频率；仅在可配置的战场地面区域绘制。
uniform vec2 canvas_size = vec2(1600.0, 600.0);
uniform vec4 ground_bounds = vec4(0.27, 0.17, 0.47, 0.81);
uniform float clock_seconds = 0.0;
uniform float intensity = 0.0;
uniform float splash_strength = 1.0;
uniform float wind = 0.0;
uniform vec4 splash_color : source_color = vec4(0.72, 0.87, 0.98, 1.0);
uniform sampler2D light_field : source_color, filter_linear;
uniform bool has_light_field = false;
uniform float light_response = 0.48;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(17.3, 93.9))) * 39571.29);
}

float splash_at(vec2 px, vec2 offset) {
    vec2 span = vec2(29.0, 21.0);
    vec2 tile = floor(px / span + offset);
    vec2 jitter = vec2(hash21(tile + 8.6), hash21(tile + 4.1));
    vec2 origin = (tile + vec2(0.12, 0.16) + jitter * vec2(0.76, 0.67) - offset) * span;
    float seed = hash21(tile + 37.0);
    float cycle = fract(clock_seconds * (1.7 + seed * 1.8) + seed);
    float active = step(1.0 - clamp(0.43 * intensity * splash_strength, 0.0, 0.9), seed);
    float radius = mix(1.0, 9.4, cycle);
    vec2 displacement = px - origin;
    float elliptic = length(vec2(displacement.x, displacement.y * 3.0)) / radius;
    float ring = 1.0 - smoothstep(0.0, 0.22, abs(elliptic - 1.0));
    float ring_fade = 1.0 - smoothstep(0.27, 1.0, cycle);
    vec2 bead = displacement - vec2((jitter.x - 0.5) * 5.0 + wind * cycle * 2.4, -4.0 * sin(cycle * 3.14159));
    float spike = (1.0 - smoothstep(0.9, 2.0, length(bead))) * (1.0 - smoothstep(0.2, 0.6, cycle));
    return active * max(ring * ring_fade * 0.65, spike * 0.52);
}

void fragment() {
    vec2 uv = UV;
    vec2 bounds_end = ground_bounds.xy + ground_bounds.zw;
    float field = step(ground_bounds.x, uv.x) * step(uv.x, bounds_end.x)
        * step(ground_bounds.y, uv.y) * step(uv.y, bounds_end.y);
    vec2 px = uv * canvas_size;
    float splash = max(splash_at(px, vec2(0.0)), 0.7 * splash_at(px, vec2(0.46, 0.41)));
    float alpha = clamp(splash * intensity * splash_strength * 0.72 * field, 0.0, 0.58);
    vec3 light = has_light_field ? texture(light_field, SCREEN_UV).rgb : vec3(0.0);
    COLOR = vec4(clamp(splash_color.rgb * 0.85 + light * light_response, vec3(0.0), vec3(1.0)), alpha);
}
