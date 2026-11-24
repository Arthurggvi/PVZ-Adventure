// 两张原画共用的四组连续相位，分别对应浪、洋流、天光和潮汐。
uniform vec4 motion = vec4(0.0);
// 光谱变化与亮度分开调节，关闭颜色不会停止波浪。
uniform float color_strength : hint_range(0.0, 1.0) = 1.0;
// 彩光曝光强度，独立于原图与水体明暗。
uniform float light_strength : hint_range(0.0, 2.0) = 1.0;

// 确定性散列用于水纹和星光，避免新增贴图或帧缓存。
float current_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 三次插值噪声，空间和时间上均连续。
float current_noise(vec2 p) {
    vec2 cell = floor(p); // 当前噪声单元。
    vec2 f = fract(p); // 单元内位置。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑插值权重。
    return mix(mix(current_hash(cell), current_hash(cell + vec2(1.0, 0.0)), u.x),
        mix(current_hash(cell + vec2(0.0, 1.0)), current_hash(cell + vec2(1.0)), u.x), u.y);
}

// 周期噪声让洋流持续朝纵向输运，跨周期时既不跳帧也不掉头。
float current_flow_noise(vec2 p, vec2 period) {
    vec2 cell = floor(p); // 周期单元地址。
    vec2 f = fract(p); // 单元内连续位置。
    vec2 u = f * f * (3.0 - 2.0 * f); // 平滑权重。
    return mix(mix(current_hash(mod(cell, period)), current_hash(mod(cell + vec2(1.0, 0.0), period)), u.x),
        mix(current_hash(mod(cell + vec2(0.0, 1.0), period)), current_hash(mod(cell + vec2(1.0), period)), u.x), u.y);
}

// 三个方向的细节使水纹和云光不出现规则棋盘。
float current_fbm(vec2 p) {
    mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)); // 相邻频带的旋转。
    float value = current_noise(p) * 0.57; // 主尺度。
    p = turn * p * 2.03 + vec2(4.2, 1.7);
    value += current_noise(p) * 0.28;
    p = turn * p * 2.01 + vec2(1.3, 7.1);
    return value + current_noise(p) * 0.15;
}

// 同一片天空在同一横向位置投下同色反光，潮汐缓慢改变青紫粉金的占比。
vec3 current_spectrum(float x, float detail) {
    float hue = x * 8.0 + sin(motion.z) * 1.8 + sin(motion.w) + detail; // 连续光谱坐标。
    vec3 cool = mix(vec3(0.035, 0.85, 1.0), vec3(0.44, 0.13, 1.0), 0.5 + 0.5 * sin(hue)); // 青紫底光。
    vec3 warm = mix(vec3(1.0, 0.20, 0.67), vec3(0.78, 1.0, 0.34), 0.5 + 0.5 * sin(hue * 0.71 + 2.0)); // 粉金干涉光。
    vec3 spectrum = mix(cool, warm, 0.48 * pow(0.5 + 0.5 * sin(hue * 1.37 - 1.0), 2.0)); // 主要保留冷色水感。
    return mix(vec3(0.22, 0.73, 0.92), spectrum, clamp(color_strength, 0.0, 1.0));
}

// 指数曝光肩部保留高光颜色，避免多层光相加后变成大片纯白。
vec3 current_expose(vec3 base, vec3 light) {
    return vec3(1.0) - (vec3(1.0) - clamp(base, vec3(0.0), vec3(1.0)))
        * exp(-max(light, vec3(0.0)) * light_strength);
}
