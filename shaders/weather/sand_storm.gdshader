shader_type canvas_item;
render_mode unshaded, blend_mix;

// 游戏时钟及累积位移由导演所属控制器传入，暂停时纹理完全静止。
uniform float clock_seconds = 0.0;
uniform float wind_travel = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float gust = 0.0;
// 0 在底图上绘制沙墙，1 在角色前绘制流沙与砂粒。
uniform float layer_depth = 0.0;
uniform vec2 canvas_size = vec2(1400.0, 600.0);
uniform vec4 shadow_color : source_color = vec4(0.46, 0.29, 0.12, 1.0);
uniform vec4 sunlit_color : source_color = vec4(0.93, 0.72, 0.38, 1.0);
uniform float wall_opacity = 0.72;
uniform float veil_opacity = 0.3;
uniform float grain_density = 0.62;
// 归一化的棋盘位置和尺寸，中央扬尘透明度降低。
uniform vec4 clear_bounds = vec4(0.17, 0.16, 0.54, 0.78);

// 为每个噪声格或砂粒生成稳定随机值。
float hash21(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

// 连续噪声构成沙丘状的团块，避免整屏正弦条纹。
float noise2(vec2 point) {
    vec2 cell = floor(point); // 当前网格。
    vec2 local = fract(point); // 网格内插值坐标。
    local = local * local * (3.0 - 2.0 * local);
    return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), local.x),
        mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), local.x), local.y);
}

// 三个尺度叠加出大沙团及其破碎边缘。
float billow(vec2 point) {
    return noise2(point) * 0.57 + noise2(point * 2.03 + 7.3) * 0.28
        + noise2(point * 4.11 - 3.7) * 0.15;
}

// 单层稀疏横飞砂粒；大小和速度由前后景尺度决定。
float grains(vec2 pixel, float scale, float travel) {
    vec2 swept = vec2(pixel.x + travel, pixel.y + pixel.x * 0.075); // 右上至左下的飞行路径。
    vec2 cell = floor(swept / scale); // 独立粒子网格。
    float seed = hash21(cell); // 密度及亮度随机种子。
    vec2 center = vec2(0.2 + seed * 0.6, 0.2 + hash21(cell + 19.7) * 0.6); // 防止粒子被网格裁断。
    vec2 local = (fract(swept / scale) - center) * scale; // 粒子中心像素距离。
    float shape = length(local / vec2(1.7 + seed * 3.6 + gust * 2.0, 0.65 + seed * 0.6)); // 短促砂痕。
    return (1.0 - smoothstep(0.25, 1.0, shape))
        * step(seed, grain_density * (0.25 + intensity * 0.75));
}

void fragment() {
    vec2 uv = UV; // 同一底图空间中的天气坐标。
    vec2 pixel = uv * canvas_size; // 砂粒以原图像素为单位。
    float storm = smoothstep(0.2, 1.0, intensity); // 常态流沙向噩梦沙墙的渐变。
    float drift = wind_travel / canvas_size.x; // 从右向左的无跳变累积位移。
    float board = smoothstep(clear_bounds.x - 0.07, clear_bounds.x + 0.08, uv.x)
        * (1.0 - smoothstep(clear_bounds.x + clear_bounds.z - 0.08,
            clear_bounds.x + clear_bounds.z + 0.07, uv.x))
        * smoothstep(clear_bounds.y - 0.04, clear_bounds.y + 0.12, uv.y)
        * (1.0 - smoothstep(clear_bounds.y + clear_bounds.w - 0.12,
            clear_bounds.y + clear_bounds.w + 0.04, uv.y)); // 保护战场中央可读性。
    vec3 tint = sunlit_color.rgb; // 当前层最终颜色。
    float alpha = 0.0; // 当前层最终覆盖率。

    if (layer_depth < 0.5) {
        vec2 rolling = vec2(uv.x * 5.5 + drift * 1.8, uv.y * 4.0); // 远处缓慢滚动的大沙团。
        float curl = noise2(rolling * 0.7 + vec2(0.0, clock_seconds * 0.035)); // 沙团抬升扰动。
        float body = billow(rolling + vec2(curl * 0.8, -curl * 0.55)); // 沙墙不规则密度。
        float sky = 1.0 - smoothstep(0.10, 0.48, uv.y); // 远景天空与栅栏受沙墙吞没。
        float edge = smoothstep(0.68, 1.0, uv.x) * 0.65; // 风沙从右侧土路卷入。
        float density = smoothstep(0.24, 0.78, body); // 留出沙团之间的空隙。
        tint = mix(shadow_color.rgb, sunlit_color.rgb, smoothstep(0.24, 0.78, body));
        alpha = wall_opacity * intensity * (0.10 + storm * 0.9)
            * (0.12 + max(sky, edge) * 0.88) * (0.35 + density * 0.65);
        alpha += intensity * 0.07 * (1.0 - board * 0.5); // 低强度常态也有轻薄暖尘。
    } else {
        vec2 ground_flow = vec2(uv.x * 4.0 + drift * 3.1, uv.y * 22.0); // 贴地拉长的流沙。
        float folds = billow(ground_flow + vec2(0.0, sin(uv.x * 8.0 + drift) * 0.6)); // 蜿蜒沙脊。
        float ribbons = smoothstep(0.38, 0.74, folds); // 细沙流之间保持透明。
        float ground = smoothstep(0.17, 0.45, uv.y); // 主要沿地面掠过。
        float cloud = billow(vec2(uv.x * 6.0 + drift * 2.4, uv.y * 6.0 - clock_seconds * 0.06)); // 近景翻卷尘团。
        float skirt = pow(abs(uv.y - 0.5) * 2.0, 2.0); // 上下边缘浓、中央薄。
        alpha = veil_opacity * intensity * (0.55 + gust * 0.45)
            * (ribbons * ground * 1.8 + storm * smoothstep(0.25, 0.72, cloud) * (0.55 + skirt * 1.5))
            * (1.0 - board * 0.55);
        tint = mix(shadow_color.rgb, sunlit_color.rgb, 0.58 + folds * 0.4);
        float grit = grains(pixel, 31.0, wind_travel * 1.7) * 0.42
            + grains(pixel + vec2(73.0, 29.0), 67.0, wind_travel * 2.9) * 0.65; // 两档速度产生纵深。
        float sparkle = grit * intensity * (0.45 + gust * 0.3); // 阵风中更明显的砂粒。
        tint = mix(tint, sunlit_color.rgb, clamp(sparkle * 2.0, 0.0, 1.0));
        alpha = alpha + sparkle * (1.0 - alpha);
    }
    COLOR = vec4(tint, clamp(alpha, 0.0, 0.82));
}
