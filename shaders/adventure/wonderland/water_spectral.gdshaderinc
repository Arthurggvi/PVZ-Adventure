// 致幻介质只改变局部反射光；光程、视角与同一波面决定颜色，没有独立色相时钟。
uniform float spectral_strength : hint_range(0.0, 1.0) = 0.42;
uniform float film_thickness_nm : hint_range(120.0, 1400.0) = 520.0;

// 平滑标量密度用于搬运介质厚度，不直接输出颜色或覆盖原画。
float medium_hash(vec2 cell) {
    vec3 value = fract(vec3(cell.xyx) * 0.1031);
    value += dot(value, value.yzx + 33.33);
    return fract((value.x + value.y) * value.z);
}

float medium_noise(vec2 point) {
    vec2 cell = floor(point);
    vec2 fraction = fract(point);
    fraction = fraction * fraction * (3.0 - 2.0 * fraction);
    return mix(mix(medium_hash(cell), medium_hash(cell + vec2(1.0, 0.0)), fraction.x),
               mix(medium_hash(cell + vec2(0.0, 1.0)), medium_hash(cell + vec2(1.0)), fraction.x), fraction.y);
}

float optical_medium(vec2 point) {
    // 两个连续尺度的密度，避免等宽条纹和逐像素闪点。
    vec2 bend = vec2(medium_noise(point * 0.65 + 8.2), medium_noise(point * 0.65 - 5.7));
    return 0.72 * medium_noise(point + bend * 1.6) + 0.28 * medium_noise(point * 2.1 + 17.4);
}

vec3 water_to_linear(vec3 value) {
    return mix(value / 12.92, pow((value + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), value));
}

vec3 water_to_srgb(vec3 value) {
    value = max(value, vec3(0.0));
    return mix(value * 12.92, 1.055 * pow(value, vec3(1.0 / 2.4)) - vec3(0.055), step(vec3(0.0031308), value));
}

// Belcour/Barla 的傅里叶域 CIE 灵敏度拟合：以微米重标定，避免大指数及稀疏 RGB 波长混叠。
// 公式依据：https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_iridescence
vec3 integrated_spectrum(float optical_path_um) {
    float phase = 6.28318530718 * optical_path_um;
    float squared_phase = phase * phase;
    vec3 xyz = vec3(0.8465900, 1.0002219, 1.0011225)
        * cos(phase * vec3(1.6810, 1.7953, 2.2084))
        * exp(-squared_phase * vec3(0.0043278, 0.0093046, 0.0066121));
    xyz.x += 0.1538683 * cos(phase * 2.2399) * exp(-squared_phase * 0.0045282);
    return vec3(dot(xyz, vec3(3.2404542, -1.5371385, -0.4985314)),
                dot(xyz, vec3(-0.9692660, 1.8760108, 0.0415560)),
                dot(xyz, vec3(0.0556434, -0.2040259, 1.0572252)));
}

// 空气—致幻透明微层—水两界面；反射级数保留两阶，厚膜自然趋向柔和低饱和色。
// 折射率1.62是虚构介质的美术设定，不能当作普通水天然会产生的虹彩。
vec3 film_reflectance(float thickness_nm, float incident_cosine, float thickness_spread_nm) {
    float layer_index = 1.62;
    float water_index = 1.333;
    float cosine = clamp(incident_cosine, 0.08, 1.0);
    float inside_cosine = sqrt(1.0 - (1.0 - cosine * cosine) / (layer_index * layer_index));
    float outer_base = pow((layer_index - 1.0) / (layer_index + 1.0), 2.0);
    float inner_base = pow((water_index - layer_index) / (water_index + layer_index), 2.0);
    float outer = outer_base + (1.0 - outer_base) * pow(1.0 - cosine, 5.0);
    float inner = inner_base + (1.0 - inner_base) * pow(1.0 - inside_cosine, 5.0);
    float transmitted = 1.0 - outer;
    float product = clamp(outer * inner, 0.000001, 0.9999);
    float internal_energy = transmitted * transmitted * inner / (1.0 - product);
    float path_um = 0.002 * layer_index * thickness_nm * inside_cosine;
    // 用中心可见波长近似像素内厚度方差，聚光核心趋向珍珠白而非高饱和白切边。
    float spread_phase = 6.28318530718 * 0.002 * layer_index * thickness_spread_nm * inside_cosine / 0.55;
    float coherence = exp(-0.5 * spread_phase * spread_phase);
    float coefficient = (internal_energy - transmitted) * sqrt(product);
    // 两界面相移之和为2π；高于水的薄层折射率使这里的余弦不需另加相移。
    vec3 result = vec3(outer + internal_energy);
    result += 2.0 * coefficient * coherence * integrated_spectrum(path_um);
    result += 2.0 * coefficient * sqrt(product) * pow(coherence, 4.0) * integrated_spectrum(path_um * 2.0);
    return clamp(result, vec3(0.0), vec3(1.0));
}

// 亚像素波高的重力—毛细短波只细分光学法线，不改变已验收的原画位移。
// 世界单位下g≈1.2、sigma/rho≈0.1，omega²=g*k+(sigma/rho)*k³；取最近整数谐波以共用18秒周期。
vec2 capillary_slope(vec2 point, float phase) {
    vec2 k0 = vec2(0.9285, 0.3714) * (6.28318530718 / 4.8);
    vec2 k1 = vec2(0.6594, -0.7518) * (6.28318530718 / 7.5);
    vec2 k2 = vec2(-0.19996, 0.9798) * (6.28318530718 / 3.3);
    vec3 angles = vec3(dot(k0, point), dot(k1, point) + 1.7, dot(k2, point) + 4.1)
        - phase * vec3(4.0, 3.0, 5.0);
    // 像素足迹越大越抑制未解析的短波，避免窗口缩小时闪烁和细条纹混叠。
    vec3 footprint = fwidth(angles);
    vec3 slopes = cos(angles) * exp(-0.5 * footprint * footprint) * vec3(0.034, 0.027, 0.020);
    return normalize(k0) * slopes.x + normalize(k1) * slopes.y + normalize(k2) * slopes.z;
}

// 仅将新增反射光在线性空间合成；零强度严格保持已经验收的水面和HDR底图映射。
vec3 spectral_water_light(vec3 original, vec2 point, vec4 surface, vec3 normal,
        vec3 view_direction, vec3 light_direction, vec2 flow_direction, vec2 medium_scale,
        float phase_a, float phase_b, float phase_blend, float speed, float shore, float focus) {
    if (spectral_strength <= 0.0) {
        return original;
    }
    // 与水纹使用相同双相输运权重；重置中的层权重为零，无新增计时器或色相动画。
    vec2 transport = flow_direction * (22.0 + 18.0 * speed);
    vec2 material_point = point + surface.xy * 16.0;
    float density_a = optical_medium((material_point - transport * (phase_a - 0.5)) / medium_scale);
    float density_b = optical_medium((material_point - transport * (phase_b - 0.5)) / medium_scale);
    float density = mix(density_a, density_b, phase_blend);
    // 固定投影面积内的微层随曲面面积增加而变薄，代替无关联的时间色相滚动。
    float area_ratio = sqrt(1.0 + 36.0 * dot(surface.xy, surface.xy));
    float thickness = film_thickness_nm * (0.24 + 1.12 * smoothstep(0.24, 0.76, density)) / area_ratio;
    // 原始Jacobian聚光强度在1附近小幅起伏；不拿已限幅的美术增强值挑选脊线。
    float footprint = max(fwidth(focus), 0.001);
    float ridge = smoothstep(1.002 - footprint, 1.022 + footprint, focus);
    float core = smoothstep(1.008 - footprint, 1.024 + footprint, focus);

    // GGX宽高光和固定大面积天光只由法线响应；不绘制悬浮的彩带或独立粒子。
    vec2 fine_slope = capillary_slope(point + surface.xy * 10.0, phase_a * 6.28318530718);
    vec3 optical_normal = normalize(normal + vec3(-fine_slope, 0.0));
    vec3 halfway = normalize(view_direction + light_direction);
    vec3 iridescence = film_reflectance(thickness, dot(view_direction, halfway), 5.0 + 60.0 * core + fwidth(thickness));
    float nh = max(dot(optical_normal, halfway), 0.0);
    float nv = max(dot(optical_normal, view_direction), 0.08);
    float nl = max(dot(optical_normal, light_direction), 0.0);
    float alpha_squared = 0.012;
    float denominator = nh * nh * (alpha_squared - 1.0) + 1.0;
    float distribution = alpha_squared / (3.14159265 * denominator * denominator);
    float view_masking = 2.0 * nv / (nv + sqrt(alpha_squared + (1.0 - alpha_squared) * nv * nv));
    float light_masking = 2.0 * nl / max(nl + sqrt(alpha_squared + (1.0 - alpha_squared) * nl * nl), 0.001);
    float geometry = view_masking * light_masking;
    float sun = distribution * geometry / (4.0 * nv);
    sun /= 1.0 + sun / 3.0;
    vec3 reflected = reflect(-view_direction, optical_normal);
    vec2 sky_delta = (reflected.xy - vec2(-0.20, 0.55)) / vec2(0.72, 0.46);
    float sky_window = exp(-dot(sky_delta, sky_delta) * 1.4);
    float coverage = (0.35 + 0.65 * smoothstep(0.30, 0.72, density)) * ridge;
    float weight = spectral_strength * shore * coverage * step(0.0, dot(normal, view_direction));
    float illumination = (0.08 * sky_window + 0.92 * sun) * (0.7 + 0.55 * ridge) * 10.0;
    vec3 reflected_light = iridescence * illumination * weight;
    // 使用最大分量扣除透射能量，避免给水底引入反相颜色。
    float reflected_fraction = max(iridescence.r, max(iridescence.g, iridescence.b)) * weight;
    vec3 base = water_to_linear(clamp(original, vec3(0.0), vec3(1.0))) * (1.0 - reflected_fraction);
    // SDR内只压新增高光的肩部，保留原画的显示曲线，避免硬截断为白斑。
    vec3 headroom = max(vec3(1.0) - base, vec3(0.001));
    return water_to_srgb(base + headroom * (vec3(1.0) - exp(-reflected_light / headroom)));
}
