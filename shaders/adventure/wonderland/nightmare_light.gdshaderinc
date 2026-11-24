#include "res://shaders/adventure/wonderland/current_light.gdshaderinc"

// 阶段环境强度与声画事件能量；不携带屏幕光源位置。
uniform float abyss_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ambient_energy : hint_range(0.0, 1.0) = 0.0;
// 噩梦场景的真实秒数，暂停冻结；用于各裂隙独立且不等长的明暗事件。
uniform float light_clock_seconds = 0.0;

// 地板交点的固定身份决定随机节奏，镜头移动不改变光源位置或时间。
float nightmare_point_energy(vec2 cell) {
    float seed = current_hash(cell + vec2(4.7, 9.1)); // 每个交点拥有独立、可重现的序列。
    float clock = light_clock_seconds / (18.0 + seed * 14.0) + seed * 9.7; // 十八至三十二秒候选周期，错开进入时刻。
    float cycle = floor(clock); // 只在完整暗场间隙更换本次候选结果。
    float p = fract(clock); // 本次亮起、停留和消退的连续进度。
    float enabled = step(0.38, current_hash(vec2(seed * 71.0, cycle + 0.73))); // 有些交点整轮保持暗，避免格网轮流机械点灯。
    float envelope = smoothstep(0.0, 0.08, p) * (1.0 - smoothstep(0.16, 0.34, p)); // 一至两秒点亮，三至六秒柔和熄灭。
    float peak = 0.72 + current_hash(vec2(seed * 31.0 + 3.7, cycle)) * 0.65; // 各处亮度不同。
    return enabled * envelope * peak * (1.0 + ambient_energy * 0.32);
}

// 天幕仍独立缓慢翻卷；只点亮原图云缝，不向地面投屏幕空间聚光灯。
vec2 nightmare_cloud_uv(vec2 uv) {
    vec2 drift = vec2(sin(motion.z) * 0.018, sin(motion.w + 1.0) * 0.009); // 两个深度的宽云层。
    float folds = current_fbm(uv * vec2(7.0, 9.0) + vec2(sin(motion.y), cos(motion.z))); // 连续云褶。
    vec2 movement = drift + vec2(folds - 0.5, sin(uv.x * 9.0 + motion.y)) * vec2(0.012, 0.005);
    return clamp(uv + movement * mix(1.0, 0.60, abyss_strength), vec2(0.001), vec2(0.999));
}
