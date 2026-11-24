// 连续的极光介质体色；零强度恢复已有水面，颜色不是叠加的薄膜干涉层。
uniform float dream_strength : hint_range(0.0, 1.0) = 0.9;

// 沿海洋背景流加两组散度为零的旋流扰动。只搬运介质坐标，不改变原画或烘焙波面。
vec2 aurora_velocity(vec2 point) {
    vec2 relative = point - vec2(170.0, 760.0);
    vec2 current = 0.65 * vec2(-relative.y, relative.x) / max(length(relative), 24.0) + vec2(-0.45, 0.72);
    vec2 k0 = vec2(0.016, 0.026);
    vec2 k1 = vec2(-0.031, 0.012);
    vec2 eddies = vec2(-k0.y, k0.x) / length(k0) * cos(dot(point, k0) + 1.4) * 0.38
        + vec2(-k1.y, k1.x) / length(k1) * cos(dot(point, k1) - 2.1) * 0.27;
    return current + eddies;
}

// 两个中点回溯步近似平流特征线，颜色块沿流线弯曲迁移，不用独立色相时钟。
vec2 aurora_material_point(vec2 point, float phase) {
    float step_length = (phase - 0.5) * 112.0 * 0.5;
    for (int step_index = 0; step_index < 2; step_index++) {
        vec2 midpoint = point - aurora_velocity(point) * step_length * 0.5;
        point -= aurora_velocity(midpoint) * step_length;
    }
    return point;
}

// 虚构发光介质的线性RGB散射色：翠绿、青蓝、紫罗兰与玫红连续混合。
// 这是美术设定的入射光谱近似，不把薄膜反射公式当作体积发光。
vec3 aurora_chroma(vec2 material) {
    vec3 green = vec3(0.04, 0.70, 0.34);
    vec3 cyan = vec3(0.04, 0.43, 0.78);
    vec3 violet = vec3(0.34, 0.11, 0.78);
    vec3 rose = vec3(0.92, 0.15, 0.42);
    vec3 cool = mix(cyan, green, smoothstep(0.25, 0.73, material.x));
    vec3 warm = mix(violet, rose, smoothstep(0.36, 0.70, material.x));
    return mix(cool, warm, smoothstep(0.36, 0.78, material.y));
}

// 使用等尺度的主流横向和纵向坐标；低速旋流中心不会被流函数坐标挤成大片纯色。
// RGB为散射色、A为宽广介质浓度；色域覆盖整个湿域，明暗褶皱只有柔和的相对变化。
vec4 aurora_material(vec2 point, vec2 scale) {
    vec2 relative = point - vec2(170.0, 760.0);
    float across = dot(relative, normalize(vec2(0.72, 0.45)));
    float along = dot(relative, normalize(vec2(-0.45, 0.72)));
    vec2 coordinate = vec2(across, along) / (scale * vec2(0.55, 2.1));
    vec2 curl = vec2(medium_noise(coordinate * 0.78 + 5.3), medium_noise(coordinate * 0.78 - 8.1)) - vec2(0.5);
    vec2 folded = coordinate + curl * 1.8;
    vec2 substance = vec2(medium_noise(folded + vec2(12.6, 4.7)),
        medium_noise(folded * vec2(0.83, 1.12) - vec2(8.2, 3.4)));
    // 细尺度浓度褶皱也随同一特征线搬运，打散整片单色块而不增加独立光条。
    substance += (vec2(medium_noise(folded * vec2(2.8, 0.85) - 13.2),
        medium_noise(folded * vec2(2.4, 0.92) + 19.8)) - vec2(0.5)) * 0.20;
    float concentration = 0.60 + 0.40 * smoothstep(0.18, 0.82, optical_medium(folded * vec2(1.4, 0.6) + 7.1));
    return vec4(aurora_chroma(substance), concentration);
}

// 在同一线性光路径中合成介质、焦散、天光和GGX反射，最后仅转换一次显示颜色。
// 介质是原水纹的光谱增益，不直接用纯调色板铺满水面；二维参数仍为美术尺度。
vec3 dream_water_light(vec3 original, vec2 point, vec4 surface, vec3 normal,
        vec3 view_direction, vec3 light_direction, vec2 medium_scale,
        float phase_a, float phase_b, float phase_blend, float shore_distance,
        float surface_coverage) {
    if (dream_strength <= 0.0) {
        return original;
    }
    vec3 view_ray = refract(-view_direction, normal, 1.0 / 1.333);
    vec3 light_ray = refract(-light_direction, normal, 1.0 / 1.333);
    vec2 view_shift = view_ray.xy / max(-view_ray.z, 0.35);
    vec3 base = water_to_linear(clamp(original, vec3(0.0), vec3(1.0)));
    float luminance = dot(base, vec3(0.2126, 0.7152, 0.0722));
    float transmittance = 1.0;
    vec3 volume = vec3(0.0);
    float shallow = smoothstep(0.0, 14.0, shore_distance);
    for (int layer = 0; layer < 3; layer++) {
        float depth = 2.0 + float(layer) * 5.0;
        vec2 sample_point = point + (view_shift * depth + surface.xy * 28.0) * shallow;
        vec2 sample_uv = sample_point / map_world_size;
        vec3 coast = texture(region_mask, sample_uv).rgb;
        // 每相先生成完整介质颜色再混合，回卷层的颜色及其导数在回卷时都不可见。
        vec4 medium_a = aurora_material(aurora_material_point(sample_point, phase_a), medium_scale);
        vec4 medium_b = aurora_material(aurora_material_point(sample_point, phase_b), medium_scale);
        vec4 medium = mix(medium_a, medium_b, phase_blend);
        vec3 source = medium.rgb * exp(-vec3(0.022, 0.009, 0.004) * depth / max(-light_ray.z, 0.35));
        // 彩光先调制原像素各通道，再保留其明暗；不同原水纹不会被同一纯色覆盖。
        source /= max(dot(source, vec3(0.2126, 0.7152, 0.0722)), 0.06);
        vec3 tinted = base / vec3(0.70, 1.0, 1.10) * pow(max(source, vec3(0.02)), vec3(0.82));
        tinted *= luminance / max(dot(tinted, vec3(0.2126, 0.7152, 0.0722)), 0.00001);
        float illumination = 1.08 + 0.24 * medium.a;
        // 浅水光程渐短，体色随岸距缓慢增强；尺度也随输运浓度变化，避免等宽描边。
        float depth_weight = 1.0 - exp(-coast.b * 64.0 / (17.0 + 9.0 * medium.a));
        // G仅由最终覆盖使用一次；样点越岸时B岸距自然归零，不再次把体色乘成硬圈。
        float optical_depth = medium.a * 0.38 * depth_weight * dream_strength / max(-view_ray.z, 0.45);
        float segment = exp(-optical_depth);
        volume += transmittance * (1.0 - segment) * tinted * illumination;
        transmittance *= segment;
    }
    vec3 body = base * transmittance + volume;
    float energy = shimmer_strength / 0.045;
    // 焦散只改变同一水体的受光，不再另叠色散亮条或只沿聚光脊出现的珠光贴片。
    float focusing = clamp(1.0 + (surface.w - 1.0) * 4.0, 0.76, 1.30);
    float diffuse = 1.0 + (dot(normal, light_direction) - light_direction.z) * 0.30;
    body *= mix(1.0, focusing * diffuse, surface_coverage * energy);
    vec2 fine_slope = capillary_slope(point + surface.xy * 10.0, phase_a * 6.28318530718);
    // 短波只微扰受光，避免大面积同频波交叉形成规则格纹。
    vec3 optical_normal = normalize(normal + vec3(-fine_slope * 0.16, 0.0));
    vec3 halfway = normalize(view_direction + light_direction);
    float nv = max(dot(optical_normal, view_direction), 0.08);
    float nl = max(dot(optical_normal, light_direction), 0.0);
    float nh = max(dot(optical_normal, halfway), 0.0);
    float alpha_squared = 0.038;
    float denominator = nh * nh * (alpha_squared - 1.0) + 1.0;
    float distribution = alpha_squared / (3.14159265 * denominator * denominator);
    float masking = 2.0 * nv / (nv + sqrt(alpha_squared + (1.0 - alpha_squared) * nv * nv))
        * 2.0 * nl / max(nl + sqrt(alpha_squared + (1.0 - alpha_squared) * nl * nl), 0.001);
    float fresnel = 0.0204 + 0.9796 * pow(1.0 - nv, 5.0);
    float sun = distribution * masking / (4.0 * nv);
    sun /= 1.0 + sun / 3.0;
    // 表面反射仅借用当前水体的弱色偏，白芯留中性；不再读取第二份薄膜颜色场。
    vec3 shared_tint = body / max(dot(body, vec3(0.2126, 0.7152, 0.0722)), 0.02);
    vec3 reflection_tint = mix(vec3(1.0), clamp(shared_tint, vec3(0.0), vec3(2.0)), spectral_strength * 0.25);
    vec3 sky = vec3(0.38, 0.52, 0.65) * reflection_tint;
    float reflected_fraction = fresnel * surface_coverage;
    vec3 lit = body * (1.0 - reflected_fraction) + sky * reflected_fraction;
    lit += reflection_tint * sun * fresnel * surface_coverage * energy * (0.65 + spectral_strength);
    // 只对本层超过SDR余量的饱和色作等比例柔和压缩，保持色相，不重调地图底图。
    float peak = max(lit.r, max(lit.g, lit.b));
    // 无介质的岸边及趋零强度不重新压暗原图高光，仅压缩新增光超出原亮度的部分。
    float knee = max(0.78, max(base.r, max(base.g, base.b)));
    float headroom = max(1.0 - knee, 0.00001);
    float compressed = knee + headroom * (1.0 - exp(-(max(peak, knee) - knee) / headroom));
    lit *= min(1.0, compressed / max(peak, 0.00001));
    return water_to_srgb(lit);
}
