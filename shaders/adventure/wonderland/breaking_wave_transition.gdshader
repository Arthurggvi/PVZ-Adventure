shader_type canvas_item;
render_mode unshaded;

// 直接折射实际战场；海面原图提供浪身纹理，原始素材不作修改。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D water_art : source_color, repeat_disable, filter_linear;
uniform sampler2D foam_art : source_color, repeat_disable, filter_linear;
uniform float elapsed = 0.0;
uniform float duration = 4.8;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
float fluid(vec2 p) {
    return noise(p) * 0.62 + noise(p * 2.07 + 3.1) * 0.26 + noise(p * 4.1 - 1.3) * 0.12;
}
void fragment() {
    float t = elapsed;
    vec2 uv = SCREEN_UV;
    float advance = smoothstep(0.32, 2.0, t);
    float depth = smoothstep(1.55, 2.45, t);
    float emerge = smoothstep(2.3, duration, t);
    float impact = smoothstep(0.65, 1.6, t) * (1.0 - smoothstep(2.1, 2.7, t));
    // 连续长浪由远处长高后翻卷：中心略先到，左右保持柔软不对称。
    float front = mix(-0.23, 1.50, advance);
    float arch = 0.09 * sin(uv.x * 4.3 + t * 0.75) + 0.022 * sin(uv.x * 12.0 - t);
    float d = uv.y - front - arch;
    float roll = exp(-pow((d + 0.035) / 0.145, 2.0));
    float lip = exp(-pow((d - 0.012) / 0.035, 2.0));
    float undercut = exp(-pow((d - 0.075) / 0.053, 2.0));
    float wall = 1.0 - smoothstep(-0.035, 0.07, d);
    float swirl = fluid(uv * vec2(4.4, 3.0) + vec2(t * 0.23, -t * 0.4));
    float filament = fluid(vec2(uv.x * 40.0 - t * 2.0, d * 21.0 + t * 2.1));
    // 浪腹像透镜一样压缩旧画面；水下余波逐渐衰减到零。
    float lens = roll * 0.018 * (1.0 - depth) + 0.009 * depth * (1.0 - emerge);
    vec2 distortion = vec2(sin(uv.y * 12.0 + t * 2.3 + swirl * 3.0), cos(uv.x * 9.0 - t * 2.1));
    vec2 screen_uv = uv + distortion * lens + vec2(0.0, roll * 0.025 * (1.0 - depth));
    screen_uv = clamp(screen_uv, vec2(0.002), vec2(0.998));
    vec3 scene = texture(screen_texture, screen_uv).rgb;
    // 原画水纹绕卷浪圆柱展开，不用纯色矩形充当水墙。
    float angle = atan(d * 7.5);
    vec2 art_uv = vec2(0.27 + uv.x * 0.63 + swirl * 0.022, 0.48 + angle * 0.13 - t * 0.045);
    vec3 art = texture(water_art, art_uv).rgb;
    vec3 detail = texture(water_art, vec2(0.32 + uv.x * 0.58, 0.70 + d * 0.17 + swirl * 0.06)).rgb;
    vec3 sea = mix(art, detail, 0.27);
    sea *= 0.75 + roll * 0.85;
    sea = mix(sea, vec3(0.018, 0.22, 0.31), 0.23);
    // 前沿暗槽和背光亮脊共同塑造厚度；暖紫反光沿弧形卷曲。
    sea *= 1.0 - undercut * 0.72;
    float rim = exp(-pow((d + 0.075) / 0.065, 2.0));
    vec3 iridescence = mix(vec3(0.12, 0.71, 0.80), vec3(0.44, 0.30, 0.65), 0.5 + 0.5 * sin(uv.x * 5.0 + t));
    sea += iridescence * rim * 0.48;
    // 泡沫贴着卷浪拉丝和分叉，细节始终从属于同一道浪峰。
    float foam_edge = d + 0.026 * (filament - 0.5);
    float foam = exp(-pow(foam_edge / 0.021, 2.0));
    float lace = pow(max(0.0, 1.0 - abs(filament - 0.51) * 5.7), 3.0);
    float skirt = exp(-pow((d + 0.095) / 0.10, 2.0));
    float foam_sheet = foam * (0.68 + filament * 0.52) + skirt * lace * 0.55;
    vec3 pearl = mix(vec3(0.68, 0.98, 0.98), vec3(0.92, 0.85, 1.0), 0.5 + 0.5 * sin(uv.x * 3.2));
    sea = mix(sea, pearl, clamp(foam_sheet * 0.15, 0.0, 0.98));
    sea += pearl * lip * 0.03;
    // 水下保留明暗方向：上方透入的天光、近处暗涡和逐渐恢复的真实战场。
    float overhead = exp(-uv.y * 3.2);
    vec3 submerged = mix(vec3(0.002, 0.012, 0.035), vec3(0.015, 0.15, 0.21), overhead);
    submerged += vec3(0.012, 0.045, 0.065) * swirl;
    float ray = pow(max(0.0, sin(uv.x * 13.0 + uv.y * 2.4 + sin(t * 0.5))), 18.0);
    float ray2 = pow(max(0.0, sin(uv.x * 7.0 - uv.y * 1.6 - t * 0.15)), 10.0);
    submerged += vec3(0.035, 0.21, 0.25) * (ray + ray2 * 0.36) * overhead;
    vec3 water = mix(sea, submerged, depth);
    float cover = max(wall, smoothstep(1.85, 2.02, t));
    float release = 1.0 - smoothstep(2.32 + uv.y * 0.18, duration, t);
    float opacity = cover * release;
    vec3 result = mix(scene * (1.0 - undercut * 0.22 * (1.0 - depth)), water, opacity);
    float spray = exp(-pow((d - 0.02) / 0.11, 2.0)) * 0.04;
    result += pearl * spray * (1.0 - depth) * advance;
    // 专用绘制的透明卷浪沿曲面展开；局部纹理滑移与浪峰推进分开，避免整张贴图平移。
    vec2 foam_uv = vec2(0.055 + uv.x * 0.89, 0.56 + d / 0.72);
    foam_uv.x += sin(uv.y * 9.0 + t * 2.2) * 0.007 + (swirl - 0.5) * 0.014;
    foam_uv.y += sin(uv.x * 17.0 - t * 2.6) * 0.012;
    float foam_bounds = step(0.0, foam_uv.y) * step(foam_uv.y, 1.0);
    vec4 painted_foam = texture(foam_art, clamp(foam_uv, vec2(0.001), vec2(0.999)));
    float foam_visibility = foam_bounds * smoothstep(0.2, 0.5, t) * (1.0 - smoothstep(1.6, 2.2, t));
    vec3 painted_light = painted_foam.rgb * mix(vec3(0.65, 0.87, 1.0), vec3(0.94, 1.0, 1.0), lip);
    result = mix(result, painted_light, painted_foam.a * foam_visibility);
    // 大气泡只有水下阶段出现，带椭圆透镜和非均匀高光，避免装饰性圆圈。
    float bubbles = smoothstep(1.7, 2.5, t) * (1.0 - smoothstep(3.0, duration, t));
    for (int i = 0; i < 9; i++) {
        float seed = float(i);
        vec2 center = vec2(fract(seed * 0.618 + 0.08), 1.35 - fract(seed * 0.427) * 1.25 - (t - 1.7) * (0.22 + fract(seed * 0.17) * 0.2));
        center.x += sin(t * 1.6 + seed) * 0.018;
        float radius = 0.006 + fract(seed * 0.347) * 0.017;
        vec2 p = (uv - center) * vec2(1.7778, 0.82);
        float distance = length(p);
        float ring = exp(-pow((distance - radius) / 0.0013, 2.0));
        float highlight = clamp(0.35 - (p.x + p.y) / radius * 0.4, 0.0, 1.0);
        result += vec3(0.19, 0.48, 0.54) * ring * highlight * bubbles;
    }
    float vignette = smoothstep(0.25, 0.78, length((uv - 0.5) * vec2(1.0, 0.8)));
    result *= 1.0 - vignette * impact * 0.32;
    COLOR = vec4(result, 1.0);
}
