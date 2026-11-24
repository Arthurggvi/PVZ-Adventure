shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/adventure/wonderland/current_light.gdshaderinc"

// 战斗实体之后、卡槽和 UI 之前；柔焦、散射和前景悬浮物复用这一次合成。
uniform sampler2D screen_image : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D medium_field : filter_linear, repeat_disable;
uniform float strength = 0.0;
uniform float threshold = 0.46;
uniform vec2 gains = vec2(0.20, 0.065);
uniform vec2 radii = vec2(8.0, 38.0);
uniform vec4 board_rect = vec4(0.0, 0.1, 1.0, 0.9);
uniform vec3 haze_color : source_color = vec3(0.043, 0.149, 0.235);
uniform float veil_strength = 0.0;
uniform float clock_seconds = 0.0;
uniform float afterglow = 0.0;

vec3 emission(vec2 uv, vec2 screen_pixel, float lod, float brightness_floor) {
    vec3 color = textureLod(screen_image, clamp(uv, screen_pixel, vec2(1.0) - screen_pixel), lod).rgb; // 使用引擎生成的连续模糊层，避免离散取样复制出角色轮廓。
    float peak = max(color.r, max(color.g, color.b)); // 较亮的实际光源。
    float cyan = smoothstep(0.07, 0.20, min(color.g, color.b) - color.r); // 海青光不误选绿色植物。
    float amber = smoothstep(0.08, 0.22, color.r - color.g) * smoothstep(0.24, 0.52, color.g); // 船灯的暖色传播。
    float white = smoothstep(0.83, 0.99, min(color.r, min(color.g, color.b))) * 0.45; // 压低普通眼白辉光，保留真正高亮技能。
    return color * smoothstep(brightness_floor, brightness_floor + 0.22, peak) * max(max(cyan, amber), white);
}

// 稀疏、柔焦的近景悬浮物；只有流光或附近发光物经过时才看得明显。
float suspension(vec2 uv, float depth, float illumination) {
    vec2 parallax = uv - board_rect.xy * depth; // 两层不同幅度的视差，空间不贴死在镜头上。
    vec2 p = parallax * mix(vec2(19.0, 11.0), vec2(12.0, 7.0), depth - 1.0)
        + vec2(clock_seconds * 0.035, -clock_seconds * 0.022) * depth; // 缓慢输运，不受战斗倍速影响。
    vec2 cell = floor(p); // 固定粒子身份，无运行时节点或纹理缓存。
    float seed = current_hash(cell + vec2(depth * 19.0, 7.4)); // 同一水层只留下少量微粒。
    vec2 center = vec2(current_hash(cell + 5.7), current_hash(cell + 13.1)) * 0.6 + 0.2; // 避开格子边缘，粒子位置不形成点阵。
    vec2 delta = fract(p) - center; // 当前微粒的软光斑。
    float radius = mix(0.025, 0.065, depth - 1.0); // 近镜头更虚，较远层细小。
    float grain = exp(-dot(delta, delta) / (radius * radius)); // 连续软边避免闪烁噪点。
    float visibility = smoothstep(0.015, 0.18, illumination) * (0.7 + 0.3 * sin(clock_seconds * 0.11 + seed * 6.28)); // 微粒被光照亮而非自己闪烁。
    return grain * step(0.94, seed) * visibility;
}

void fragment() {
    vec3 base = textureLod(screen_image, SCREEN_UV, 0.0).rgb; // 单位原轮廓保持未模糊的中心采样。
    vec4 field = texture(medium_field, SCREEN_UV); // 与远背景共享水体密度及声画事件。
    vec2 art_uv = (SCREEN_UV - board_rect.xy) / board_rect.zw; // 近远关系随相机位置保持。
    float depth = 1.0 - smoothstep(0.12, 0.97, art_uv.y); // 较远行的实体轻微融入水中。
    vec2 pixel = vec2(1.0, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x) / 1920.0; // 参考像素尺度。
    vec2 soft_radius = pixel * (0.7 + depth * 1.8); // 实体比背景更清晰，只做轻微柔焦。
    vec3 soft = (texture(screen_image, clamp(SCREEN_UV + soft_radius, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb
        + texture(screen_image, clamp(SCREEN_UV - soft_radius, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb
        + texture(screen_image, clamp(SCREEN_UV + soft_radius * vec2(1.0, -1.0), SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb
        + texture(screen_image, clamp(SCREEN_UV + soft_radius * vec2(-1.0, 1.0), SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE)).rgb) * 0.25;
    base = mix(base, soft, strength * veil_strength * (0.6 + depth)); // 柔焦不吞掉格位和目标轮廓。
    float veil = strength * veil_strength * (0.38 + depth * 0.62) * (0.65 + field.b * 0.60); // 实体与镜头之间比远景更薄的介质。
    base = mix(base, haze_color * (1.0 + field.a * 0.5), veil); // 低对比蓝青中间层，并非白雾。
    vec2 blur_lod = max(log2(max(radii / (1920.0 * SCREEN_PIXEL_SIZE.x), vec2(1.0))) - vec2(0.5), vec2(0.0)); // 模糊半径按实际分辨率换算为连续 mip 层级。
    vec3 tight = emission(SCREEN_UV, SCREEN_PIXEL_SIZE, blur_lod.x, threshold * 0.72); // 较小范围的柔光保持局部光色。
    vec3 wide = emission(SCREEN_UV, SCREEN_PIXEL_SIZE, blur_lod.y, threshold * 0.32); // 大范围水体扩散已平均亮度，提取阈值相应降低。
    vec3 glow = (tight * gains.x + wide * gains.y * (0.7 + field.b + depth * 0.4)) * strength; // 光先照亮浑浊水，再被距离吸收。
    glow += haze_color * afterglow * veil * 0.18; // 微弱且延迟恢复的散射余辉。
    float illumination = max(wide.g * 2.0, field.a * 0.22) + tight.g * 0.5; // 微粒响应实际光场，暗处基本不可见。
    float particles = suspension(SCREEN_UV, 1.05, illumination) * 0.07 + suspension(SCREEN_UV, 1.65, illumination) * 0.045; // 两种深度的稀疏近景。
    glow += vec3(0.25, 0.58, 0.63) * particles * strength * min(veil_strength / 0.14, 1.0);
    COLOR = vec4(vec3(1.0) - (vec3(1.0) - base) * exp(-glow), 1.0);
}
