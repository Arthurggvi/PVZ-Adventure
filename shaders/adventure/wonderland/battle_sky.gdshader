shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/adventure/wonderland/current_light.gdshaderinc"

// 天空自身的运动和极光强度，独立于海浪。
uniform float sky_strength : hint_range(0.0, 2.0) = 1.0;
// 独立保留精灵调制色，防止输出重复乘入原图。
varying vec4 sprite_tint;

void vertex() {
    sprite_tint = COLOR;
}

void fragment() {
    float height = (UV.y * 600.0 - 94.0) / 132.0; // 场景天空可见带中的高度，保留原精灵布局。
    if (height > 1.03) { // 下方已被不透明海面覆盖，避免重复计算整片不可见天空。
        discard;
    }
    vec2 celestial_motion = vec2(sin(motion.z * 2.0) * 0.025, cos(motion.z * 2.0) * 0.007) * sky_strength; // 上层天幕约四倍可见漂移，保留星球长宽比例。
    vec2 cloud_motion = vec2(sin(motion.y * 2.0) * 0.038, cos(motion.y * 2.0) * 0.010) * sky_strength; // 云层以不同周期穿过天幕，形成清楚的层次。
    float horizon_lock = 1.0 - smoothstep(0.60, 0.96, height); // 远山和海天接缝保持稳定。
    vec2 celestial_uv = UV + celestial_motion; // 天幕整体平移，不把星球扭成果冻。
    vec2 horizon_uv = vec2(UV.x, 0.70 + height * 0.21) + cloud_motion * horizon_lock; // 云层位移向地平线平滑收敛。
    vec3 celestial = texture(TEXTURE, clamp(celestial_uv, vec2(0.0), vec2(1.0))).rgb; // 近处天幕。
    vec3 horizon = texture(TEXTURE, clamp(horizon_uv, vec2(0.0), vec2(1.0))).rgb; // 远处云层。
    vec3 sky = mix(celestial, horizon, smoothstep(0.38, 0.94, height)); // 以云光柔接两种深度。

    vec2 p = vec2(UV.x * 1.7768, height * 0.30); // 可见天空中的空间比例。
    float cloud = current_fbm(p * 5.0 + vec2(sin(motion.z * 2.0), cos(motion.y * 2.0))); // 可见云光随独立层运动。
    float arc = 0.14 + 0.075 * sin(UV.x * 5.5 - motion.y * 2.0) + 0.025 * sin(UV.x * 11.0 + motion.z * 2.0); // 主极光在可见天窗中展开，不藏在卡栏背后。
    float second_arc = 0.18 + 0.065 * sin(UV.x * 4.0 + motion.z * 3.0 + 1.5); // 第二道宽光带反向穿行。
    float curl = current_fbm(vec2(UV.x * 9.0 + sin(motion.y * 2.0), height * 1.7)) - 0.5; // 连贯的大幅翻卷。
    float distance_a = abs(p.y - arc - curl * 0.060); // 第一层极光中心。
    float distance_b = abs(p.y - second_arc - curl * 0.035); // 第二层极光中心。
    float veil = exp(-distance_a * 26.0) * (0.42 + cloud * 0.58); // 宽幅彩色光幕。
    float second_veil = exp(-distance_b * 34.0) * (0.35 + cloud * 0.45); // 叠合时仍可分辨的第二层光幕。
    float filament = exp(-distance_a * 85.0) * 0.32; // 主光带的柔亮边。
    float curtains = 0.70 + 0.30 * current_noise(vec2(UV.x * 26.0 + sin(motion.y * 2.0) * 2.0, height * 2.0)); // 连贯光幕，避免重新产生碎闪。
    vec3 light = current_spectrum(UV.x, cloud) * (veil + filament) * curtains * 1.05; // 主光带与水面共用光谱。
    light += current_spectrum(UV.x, cloud + 1.8) * second_veil * 0.65; // 交织的青紫粉光。
    light += vec3(1.0, 0.52, 0.28) * exp(-pow((UV.x - 0.55 - sin(motion.z) * 0.03) * 5.0, 2.0))
        * exp(-pow((height - 0.90) * 6.0, 2.0)) * (0.28 + cloud * 0.24); // 地平线暖光及呼吸。

    vec2 star_grid = vec2(UV.x * 90.0, height * 15.0); // 固定星位，不跟随云层滑动。
    vec2 star_cell = floor(star_grid); // 当前星区。
    float seed = current_hash(star_cell); // 星区稀疏度与相位。
    vec2 star_position = vec2(seed, current_hash(star_cell + 4.2)) * 0.7 + 0.15; // 单元内星位。
    vec2 star_delta = fract(star_grid) - star_position; // 星心距离。
    float star = exp(-dot(star_delta, star_delta) * 480.0) * step(0.91, seed)
        * pow(0.5 + 0.5 * sin(motion.x + seed * 31.0), 3.0); // 少量柔和闪烁，无全屏闪变。
    light += vec3(0.55, 0.85, 1.0) * star * (1.0 - smoothstep(0.40, 0.90, height));
    COLOR = vec4(current_expose(sky, light * sky_strength), 1.0) * sprite_tint;
}
