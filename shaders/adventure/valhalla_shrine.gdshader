shader_type canvas_item;
render_mode unshaded;

// 神龛展开进度。1 为完整圆光，退场回到 0 时光冕收回。
uniform float arrival : hint_range(0.0, 1.0) = 0.0;
// 展区宽高比，用来保持圆光、穹顶和星芒的实际比例。
uniform float stage_aspect : hint_range(0.4, 1.4) = 0.804780876;

// 暗金用在建筑的内凹刻线。
const vec3 BRONZE = vec3(0.39, 0.25, 0.14);
// 香槟金用于迎光的铜边和圆光。
const vec3 GOLD = vec3(0.98, 0.76, 0.43);
// 珍珠色用于星心和入场波前。
const vec3 PEARL = vec3(1.0, 0.92, 0.73);

// 将有符号距离变成带平滑边缘的线条。半宽和过渡宽度均以展区半宽为单位。
float engraved_line(float distance_from_line, float half_width, float antialias) {
	return 1.0 - smoothstep(half_width, half_width + antialias, abs(distance_from_line));
}

// 两段相交圆弧形成尖拱，正值在拱内。拱脚以下的圆弧延续为竖直壁柱。
float arch_distance(vec2 point) {
	vec2 arch = vec2(abs(point.x) + 0.42, min(point.y - 0.015, 0.0)); // 最近的圆弧截面。
	return 1.15 - length(arch);
}

// 一条从尖端向两侧渐宽的十字星芒。尺寸以展区半宽为单位。
float star_glint(vec2 offset, float span, float antialias) {
	vec2 local = abs(offset); // 到星心的横纵距离。
	float arms = min(local.x * 4.9 + local.y, local.x + local.y * 6.2); // 竖向星芒略长。
	return engraved_line(arms, span * 0.10, span + antialias);
}

// 镜面光只沿环的一段转动，两端平滑隐去。
float orbit_arc(vec2 direction, float heading, float length_cosine) {
	vec2 tangent = vec2(cos(heading), sin(heading)); // 亮弧中心相对徽章的方向。
	return smoothstep(length_cosine, 0.999, dot(direction, tangent));
}

void fragment() {
	vec2 point = (UV - vec2(0.5, 0.47)) * vec2(2.0, 2.0 / stage_aspect); // 徽章中心为原点，单位为展区半宽。
	float cross_axis = abs(point.x); // 合并建筑左右对称的距离运算。
	float antialias = max(fwidth(point.x) * 0.8, 0.003); // 线条缩放时保留亚像素过渡。
	float aperture = arch_distance(point); // 尖拱内侧到拱缘的距离。
	float recess = smoothstep(0.07, 0.17, aperture); // 照明留在拱门内侧，柱面保持较暗。
	float overhead = 1.0 - smoothstep(-0.95, 0.64, point.y); // 穹顶由上至下逐渐暗下。
	float inner_glow = 1.0 - smoothstep(0.16, 1.04, length(point * vec2(1.0, 0.83))); // 拱内的靛蓝环境光。
	vec3 color = mix(vec3(0.015, 0.017, 0.038), vec3(0.070, 0.076, 0.155), overhead * 0.58); // 神龛外侧的阴影石材。
	color = mix(color, vec3(0.039, 0.047, 0.112) + vec3(0.070, 0.058, 0.103) * inner_glow, recess * 0.94);

	// 三道逐级内收的拱券，厚的暗槽在窄金边背后提供深度。
	float carved_stone = engraved_line(aperture - 0.055, 0.047, antialias); // 拱券的主要切面。
	float shadow_groove = engraved_line(aperture - 0.084, 0.013, antialias); // 内侧凹槽投下的阴影。
	float vault_rims = engraved_line(aperture - 0.008, 0.0045, antialias)
		+ 0.64 * engraved_line(aperture - 0.034, 0.0050, antialias)
		+ 0.44 * engraved_line(aperture - 0.113, 0.0035, antialias); // 朝前和朝内的三层铜边。
	float vault_end = 1.0 - smoothstep(0.75, 0.84, point.y); // 拱脚在底座之前渐入柱面。
	color = mix(color, vec3(0.092, 0.078, 0.123), carved_stone * vault_end);
	color *= 1.0 - shadow_groove * vault_end * 0.49;
	color += mix(BRONZE, GOLD, overhead * 0.64) * vault_rims * vault_end * 0.59;

	float column_height = smoothstep(-0.66, -0.61, point.y)
		* (1.0 - smoothstep(0.76, 0.80, point.y)); // 柱身上下边界。
	float column_face = engraved_line(cross_axis - 0.825, 0.048, antialias); // 左右两根方柱。
	float column_flutes = engraved_line(cross_axis - 0.785, 0.006, antialias)
		+ engraved_line(cross_axis - 0.857, 0.004, antialias) * 0.78
		+ engraved_line(cross_axis - 0.811, 0.002, antialias) * 0.32; // 石柱不同深度的竖槽。
	float capitals = (engraved_line(point.y + 0.634, 0.021, antialias)
		+ engraved_line(point.y - 0.761, 0.022, antialias))
		* engraved_line(cross_axis - 0.825, 0.064, antialias); // 柱头和柱脚压住竖槽。
	color = mix(color, vec3(0.090, 0.073, 0.109), column_face * column_height * 0.8);
	color += BRONZE * (column_flutes * column_height * 0.38 + capitals * 0.54);

	float dais_band = engraved_line(point.y - 0.805, 0.013, antialias)
		+ engraved_line(point.y - 0.874, 0.008, antialias) * 0.72; // 底座的两级水平铜檐。
	float dais_width = 1.0 - smoothstep(0.865, 0.895, cross_axis); // 台阶留在外框内。
	float dais_face = smoothstep(0.805, 0.825, point.y)
		* (1.0 - smoothstep(0.868, 0.928, point.y)); // 铜檐之间的阴影石阶。
	color = mix(color, vec3(0.050, 0.047, 0.070), dais_face * dais_width);
	color += BRONZE * dais_band * dais_width * (0.48 + 0.31 * (1.0 - cross_axis));

	// 外框的双层斜角和外侧留边。
	vec2 from_case_center = abs(vec2(point.x, point.y - 0.06 / stage_aspect)); // 展区几何中心到像素的距离。
	float frame_top = 1.0 / stage_aspect - 0.062; // 展区纵向可用半高。
	float frame_edge = min(min(0.950 - from_case_center.x, frame_top - from_case_center.y),
		0.950 + frame_top - 0.098 - from_case_center.x - from_case_center.y); // 外框内侧为正，斜线裁掉四角。
	float frame_inlay = engraved_line(frame_edge - 0.008, 0.0035, antialias)
		+ 0.52 * engraved_line(frame_edge - 0.039, 0.0025, antialias); // 两条大小不同的嵌铜线。
	float lighting = clamp(0.56 - point.y * 0.27 - point.x * 0.08, 0.18, 1.0); // 框缘上方比下方更亮。
	color *= mix(0.54, 1.0, smoothstep(0.015, 0.05, frame_edge));
	color += mix(BRONZE, GOLD, lighting * 0.62) * frame_inlay * lighting;

	float radius = length(point); // 圣徽中心到当前像素的距离。
	vec2 direction = point / max(radius, 0.001); // 极坐标方向，中心像素避免除零。
	float angle = atan(direction.y, direction.x + 0.00001); // 径向光线、雕刻和节奏使用统一角度。
	float progress = clamp(arrival, 0.0, 1.0); // 入场参数安全范围。
	float settled = smoothstep(0.18, 0.95, progress); // 入场后固定圆光平滑接过波前。
	float reveal_radius = mix(0.30, 0.99, progress); // 加冕光环从徽章背后扩散到穹顶。
	float swell = smoothstep(0.0, 0.17, progress) * (1.0 - smoothstep(0.70, 1.0, progress)); // 波前在终点消散。
	float breathing = 0.92 + 0.08 * sin(TIME * 1.18); // 常驻光线缓慢呼吸。

	float shafts = smoothstep(0.70, 0.99, cos(angle * 13.0 + 0.26 * sin(TIME * 0.35)))
		* (0.55 + 0.45 * cos(angle * 4.0 + 0.8)); // 宽窄错开的圣光射线。
	float ray_range = smoothstep(0.25, 0.59, radius)
		* (1.0 - smoothstep(0.67, 1.12, radius)); // 射线在拱内远端消散。
	float lit_air = (1.0 - smoothstep(0.20, 0.86, radius)) * recess; // 徽章背后被照亮的空气。
	color += mix(vec3(0.36, 0.28, 0.48), GOLD, 0.51) * lit_air * (0.07 + settled * 0.25) * breathing;
	color += GOLD * shafts * ray_range * recess * (0.05 + settled * 0.16) * breathing;

	float inner_ring = engraved_line(radius - 0.564, 0.008, antialias); // 最靠近圣徽的厚金主环。
	float outer_ring = engraved_line(radius - 0.686, 0.005, antialias); // 外层留出两道旋转亮弧。
	float hairline = engraved_line(radius - 0.726, 0.0038, antialias); // 强光之外的暗金刻线。
	float ring_glow = engraved_line(radius - 0.564, 0.013, 0.064)
		+ 0.52 * engraved_line(radius - 0.686, 0.009, 0.045); // 金环附近窄而柔的外溢光。
	float ring_ticks = smoothstep(0.86, 0.99, cos(angle * 48.0))
		* engraved_line(radius - 0.659, 0.011, antialias); // 薄环之间的辐射金纹。
	float inner_arc = orbit_arc(direction, TIME * 0.49 - 1.6, -0.31); // 主环顺时针转动的亮段。
	float outer_arc = orbit_arc(direction, -TIME * 0.36 + 0.86, 0.14); // 第二层反向慢转。
	float far_arc = orbit_arc(direction, -TIME * 0.36 + 4.00, 0.52); // 第二层在对侧反射较弱的光。
	float crown_mask = smoothstep(0.013, 0.061, aperture); // 圆光受穹顶遮挡，画在拱内。
	color += (GOLD * (inner_ring * 0.41 + outer_ring * 0.40 + ring_glow * 0.22)
		+ BRONZE * (hairline * 0.53 + ring_ticks * 0.85)
		+ PEARL * (inner_arc * inner_ring * 0.62 + outer_ring * (outer_arc * 0.73 + far_arc * 0.38)))
		* crown_mask * settled * breathing;

	float petal_radius = 0.747 + 0.074 * (0.5 + 0.5 * cos(angle * 8.0)); // 锻造成八瓣冠纹的最外层曲线。
	float petals = engraved_line(radius - petal_radius, 0.0035, antialias)
		* (0.55 + 0.45 * abs(direction.y)); // 冠纹上下展开，两侧收进拱壁。
	float petal_keys = smoothstep(0.974, 1.0, cos(angle * 8.0))
		* engraved_line(radius - 0.804, 0.015, antialias); // 每个瓣尖都有一枚短金簧。
	color += (BRONZE * petals * 0.9 + GOLD * petal_keys * 0.64) * crown_mask * settled;

	float crest_wave = engraved_line(radius - reveal_radius, 0.009, antialias); // 入场波前的亮边。
	float echo_wave = engraved_line(radius - reveal_radius + 0.083, 0.006, antialias); // 第一环之后稍慢的回响。
	float wave_glow = engraved_line(radius - reveal_radius, 0.014, 0.104); // 让波前带着一层暖空气扩开。
	float wave_crown = 0.62 + 0.38 * smoothstep(0.35, 0.98, cos(angle * 8.0)); // 入场波前呼应定型后的八瓣冠纹。
	color += (PEARL * crest_wave * 0.89 + GOLD * (echo_wave * 0.37 + wave_glow * 0.42))
		* swell * wave_crown * crown_mask;

	vec2 crest = point - vec2(0.0, -0.977); // 尖拱顶端的金色宝石。
	vec2 foot = point - vec2(0.0, 0.832); // 下方的倒映宝石。
	float crest_diamond = engraved_line(abs(crest.x) * 1.54 + abs(crest.y) - 0.079, 0.005, antialias); // 上方外镶边。
	float foot_diamond = engraved_line(abs(foot.x) * 1.48 + abs(foot.y) - 0.054, 0.005, antialias); // 下方外镶边。
	float jewels = star_glint(crest, 0.074, antialias) + 0.75 * star_glint(foot, 0.050, antialias); // 透过宝石的珍珠亮芯。
	vec2 side_jewel = vec2(cross_axis - 0.827, point.y + 0.46); // 两侧柱头下方的金钉。
	float side_stars = star_glint(side_jewel, 0.039, antialias); // 上下方宝石保持视觉主次。
	color += GOLD * (crest_diamond * 0.67 + foot_diamond * 0.57 + side_stars * 0.60);
	color += PEARL * jewels * (0.25 + settled * 0.51 + swell * 0.21);

	float motes = 0.0; // 上升微尘的累计亮度。
	for (int i = 0; i < 10; i++) { // 固定十粒，每粒使用独立的漂移速度和起点。
		float seed = float(i) + 1.0; // 粒子的稳定序号。
		float life = fract(TIME * (0.086 + 0.045 * fract(seed * 0.73)) + seed * 0.618); // 从拱内地面升向穹顶。
		float center_x = (fract(seed * 0.75488) - 0.5) * 1.30
			+ 0.065 * sin(TIME * 0.67 + seed * 2.0); // 微尘随升流稍向两侧飘动。
		vec2 offset = point - vec2(center_x, mix(0.84, -1.03, life)); // 粒子中心到像素的距离。
		float opacity = smoothstep(0.0, 0.16, life) * (1.0 - smoothstep(0.57, 1.0, life)); // 循环切换发生在透明时。
		float size = mix(0.007, 0.014, fract(seed * 0.39)); // 明暗粒群混合不同尺寸。
		float distance_squared = dot(offset, offset); // 用平方距离避免每颗微尘再开方。
		float spark = 1.0 - smoothstep(size * size * 0.37, size * size + antialias * antialias, distance_squared); // 微尘亮芯。
		float bloom = 1.0 - smoothstep(0.0, size * size * 8.0, distance_squared); // 亮芯外围的低亮度暖雾。
		motes += opacity * (spark * 0.64 + bloom * 0.31);
	}
	float star_phase = fract(TIME * 0.19); // 两颗大星芒在一个慢周期内轮流亮起。
	float left_glint = smoothstep(0.05, 0.19, star_phase)
		* (1.0 - smoothstep(0.20, 0.42, star_phase)); // 左上星芒淡入淡出。
	float right_glint = smoothstep(0.47, 0.62, star_phase)
		* (1.0 - smoothstep(0.63, 0.89, star_phase)); // 右下星芒错峰出现。
	float glints = star_glint(point - vec2(-0.448, -0.535), 0.096, antialias) * left_glint
		+ star_glint(point - vec2(0.414, 0.544), 0.087, antialias) * right_glint; // 两颗星分别落在圆光附近。
	color += (GOLD * motes + PEARL * glints * 0.78) * (0.19 + 0.81 * settled) * crown_mask;
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), COLOR.a);
}
