shader_type canvas_item;
render_mode unshaded;

// 与海滨主景共用的环境光显示值，不另读系统时钟。
uniform vec3 ambient_rgb = vec3(0.57, 0.64, 0.76);
// 与海滨主景共用的主光显示值，固定近景受光面权重。
uniform vec3 key_rgb = vec3(0.63, 0.50, 0.31);
// 同一日周期的灯光能量，白天为零，深夜约为 0.92。
uniform float window_energy = 0.0;
// 宿主显式动作时间，暂停与回放时保持一致。
uniform float effect_seconds = 0.0;
// 原生交互驱动的木牌聚焦强度，范围为 0 至 1。
uniform float hover_amount = 0.0;

// 将 [param color] 从显示色转为线性空间，保持夜间木纹和植物明暗层次。
vec3 to_linear(vec3 color) {
    return mix(color / 12.92, pow((color + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}

// 将 [param color] 从线性空间还原为显示色。
vec3 to_srgb(vec3 color) {
    color = max(color, vec3(0.0));
    return mix(color * 12.92, 1.055 * pow(color, vec3(1.0 / 2.4)) - vec3(0.055), step(vec3(0.0031308), color));
}

// 只让植物头部随风轻摆；地图、木牌、车轮和接触阴影始终固定。
void fragment() {
    // 原始 UV 仅用于确定固定的局部动作范围。
    vec2 uv = UV;
    // 豌豆头部连同探险帽，向下接近茎部时逐渐固定。
    float pea = 1.0 - smoothstep(0.80, 1.0, length((UV - vec2(0.215, 0.210)) / vec2(0.185, 0.215)));
    pea *= 1.0 - smoothstep(0.32, 0.42, UV.y);
    // 向日葵外圈和脸部共享极轻微摆动，避开左下地图卷轴。
    float flower = 1.0 - smoothstep(0.82, 1.02, length((UV - vec2(0.831, 0.247)) / vec2(0.157, 0.182)));
    flower *= 1.0 - smoothstep(0.34, 0.43, UV.y);
    // 最大位移约为原纹理两像素，不摇动整辆车。
    uv.x += sin(effect_seconds * 0.83) * 0.00125 * pea;
    uv.x += sin(effect_seconds * 0.71 + 1.4) * 0.00110 * flower;
    uv.y += sin(effect_seconds * 0.71 + 0.8) * 0.00035 * flower;
    // 实际透明前景采样，边缘跟随局部植物动作。
    vec4 source = texture(TEXTURE, uv);
    // 以白天画面为基准，在相同日周期下保持近景稍清晰的月光层次。
    vec3 illumination = max(ambient_rgb + key_rgb * 0.50, vec3(0.07)) / vec3(0.885, 0.890, 0.915);
    illumination = clamp(illumination, vec3(0.12, 0.17, 0.24), vec3(1.15));
    // 原画暗部与纹理保留，不用整图颜色叠盖模拟夜间。
    vec3 lit = to_linear(source.rgb) * illumination;
    // 只在窗灯进入夜间能量后补光，已确认的白天与黄昏观感不变。
    float night_fill = smoothstep(0.42, 0.88, window_energy);
    // 地图纸面使用柔边局部范围，补光不延伸到木牌、车轮与接地阴影。
    float map_fill = smoothstep(0.24, 0.30, UV.x) * (1.0 - smoothstep(0.71, 0.77, UV.x));
    map_fill *= smoothstep(0.30, 0.37, UV.y) * (1.0 - smoothstep(0.50, 0.56, UV.y));
    // 角色沿用已有头部范围；等比提升线性能量，保留夜色的冷暖比例和原画表情。
    float welcome_fill = max(max(pea, flower), map_fill);
    lit *= 1.0 + welcome_fill * night_fill * 0.60;
    // 灯笼玻璃中心在原图右下角，距离按素材比例校正。
    vec2 lantern_delta = (UV - vec2(0.887, 0.840)) / vec2(0.085, 0.125);
    // 暖光主要照亮灯笼与附近车轮，远离灯具后平滑衰减。
    float lantern_field = exp(-dot(lantern_delta, lantern_delta) * 1.7) * window_energy;
    // 小面积灯芯能量，白天不附加灯光。
    vec2 core_delta = (UV - vec2(0.887, 0.840)) / vec2(0.025, 0.047);
    float lantern_core = exp(-dot(core_delta, core_delta) * 1.4) * window_energy;
    lit += to_linear(source.rgb) * vec3(1.0, 0.51, 0.13) * lantern_field * 0.72;
    lit += vec3(1.0, 0.54, 0.16) * lantern_core * 0.54;
    // 仅木牌内部的柔和暖色反馈，地图纸面和整车不泛黄。
    float plank = smoothstep(0.252, 0.277, UV.x) * (1.0 - smoothstep(0.744, 0.772, UV.x));
    plank *= smoothstep(0.570, 0.605, UV.y) * (1.0 - smoothstep(0.725, 0.760, UV.y));
    lit += to_linear(source.rgb) * vec3(0.18, 0.115, 0.045) * plank * hover_amount;
    // 极弱空气光晕随透明度平滑消散，不产生矩形背景。
    float halo_alpha = lantern_field * 0.055 * (1.0 - source.a);
    // 透明区仅保留暖色散射；实体区域仍使用真实前景透明度。
    vec3 final_rgb = mix(to_srgb(lit), vec3(1.0, 0.65, 0.25), halo_alpha / max(source.a + halo_alpha, 0.001));
    COLOR = vec4(clamp(final_rgb, 0.0, 1.0), source.a + halo_alpha);
}
