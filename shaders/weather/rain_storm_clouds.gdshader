shader_type canvas_item;
render_mode unshaded, blend_mix;

// 仅覆盖上缘天空的流动雨云暗影，战场及 UI 不添加实体遮挡。
uniform float clock_seconds = 0.0;
uniform float intensity = 0.0;
uniform float gust = 0.0;
uniform float shade = 0.18;

void fragment() {
    vec2 uv = UV;
    vec2 drift = vec2(clock_seconds * 0.012 + gust * 0.015, 0.0);
    float cloud = 0.52 + 0.22 * sin((uv.x + drift.x) * 11.5 + uv.y * 8.0)
        + 0.15 * sin((uv.x - drift.x * 0.54) * 23.0 - uv.y * 14.0)
        + 0.12 * cos((uv.x + drift.x * 0.24) * 37.0 + uv.y * 10.0);
    float sky_fade = 1.0 - smoothstep(0.12, 0.32, uv.y);
    float shadow = smoothstep(0.27, 0.78, cloud);
    float alpha = clamp(shadow * sky_fade * shade * pow(intensity, 1.5), 0.0, 0.24);
    COLOR = vec4(0.07, 0.09, 0.17, alpha);
}
