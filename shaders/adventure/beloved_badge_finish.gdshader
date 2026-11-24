shader_type canvas_item;
render_mode unshaded;

// true 用于徽章原画，false 用于背包和装备槽的绒面底板。
uniform bool icon_finish = false;
// 悬停和选中时提高边缘反光，0 为常态，1 为完全点亮。
uniform float focus_strength : hint_range(0.0, 1.0) = 0.0;

// 绒盒四角的阴影色。
const vec3 ROSEWOOD = vec3(0.126, 0.038, 0.053);
// 绒盒中央的红色环境光。
const vec3 VELVET = vec3(0.405, 0.104, 0.149);
// 金属暗槽的玫瑰金。
const vec3 COPPER = vec3(0.54, 0.25, 0.19);
// 镶边迎光面的香槟金。
const vec3 CHAMPAGNE = vec3(1.0, 0.79, 0.54);

// [param offset] 相对于宝石星心，[param size] 为光臂的最大长度，单位为图标宽度。
float fine_glint(vec2 offset, float size) {
	vec2 delta = abs(offset); // 纵向光臂略长于横向。
	float rays = min(delta.x * 5.75 + delta.y, delta.x * 1.35 + delta.y * 6.5); // 两根细光臂在切面相交。
	return 1.0 - smoothstep(size * 0.055, size, rays);
}

void fragment() {
	float rhythm = fract(TIME * 0.59); // 与展台扣件共用约 1.7 秒的两拍节奏。
	float beat = (1.0 - smoothstep(0.005, 0.104, abs(rhythm - 0.11)))
		+ 0.61 * (1.0 - smoothstep(0.006, 0.081, abs(rhythm - 0.28))); // 用间隔不同的两次暖光表现心跳。
	if (icon_finish) {
		vec4 art = COLOR; // 保留原画和节点的颜色、覆盖度与淡入淡出。
		vec2 ruby_offset = UV - vec2(0.503, 0.786); // 对准羽饰之间的心形宝石。
		vec2 ruby_axes = ruby_offset * vec2(9.8, 11.7); // 局部约束红光，避开下方的缎带。
		float ruby_area = 1.0 - smoothstep(0.10, 1.0, dot(ruby_axes, ruby_axes)); // 胸针宝石的软遮罩。
		float red_gem = smoothstep(0.02, 0.25, art.r - art.g) * smoothstep(0.29, 0.62, art.r); // 让红色切面比金属框先受光。
		float ruby_light = red_gem * ruby_area * (0.13 + 0.42 * beat); // 留一层常亮红光，随两拍缓慢回落。
		vec3 color = art.rgb + (vec3(1.0) - art.rgb) * vec3(1.0, 0.43, 0.33) * ruby_light; // 以原画亮度为上限，保留暗部纹理。

		float phase = min(fract(TIME * 0.176) * 2.85, 1.0); // 每轮短时横掠，光带余下时间在画外。
		float from_sheen = abs(dot(UV, vec2(1.0, 0.38)) - mix(-0.24, 1.60, phase)); // 暖金反射从左上向右下移动。
		float sheen = 1.0 - smoothstep(0.007, 0.076, from_sheen); // 窄的反射带更接近抛光金属。
		vec2 portrait = (UV - vec2(0.50, 0.46)) * vec2(3.0, 2.80); // 人脸和衣领的半径范围。
		float border = smoothstep(0.52, 0.95, dot(portrait, portrait)); // 让扫光留在金属与羽饰边缘。
		float gold_surface = smoothstep(0.14, 0.41, art.r - art.b) * smoothstep(0.31, 0.75, art.r); // 筛选已有的暖色切面。
		float polish = border * gold_surface * sheen * (0.23 + 0.12 * focus_strength); // 聚焦时保留一点额外镜面反光。
		color += (vec3(1.0) - color) * CHAMPAGNE * polish;

		float crest_twinkle = 1.0 - smoothstep(0.01, 0.12, abs(fract(TIME * 0.184 + 0.24) - 0.32)); // 顶端金饰在扫光经过前短促亮起。
		float crest = fine_glint(UV - vec2(0.501, 0.074), 0.034) * crest_twinkle; // 顶端的原画星心。
		float gem_star = fine_glint(ruby_offset, 0.052) * beat; // 宝石内的光臂只在两次心跳时延展。
		color += (vec3(1.0) - color) * vec3(1.0, 0.91, 0.73) * (0.68 * gem_star + 0.58 * crest);
		COLOR = vec4(color, art.a);
	} else {
		vec2 point = UV - vec2(0.5); // 底板中心为原点。
		vec2 corner = abs(point) - vec2(0.345); // 直边延伸到圆角开始的位置。
		float edge = 0.134 - length(max(corner, vec2(0.0))) - min(max(corner.x, corner.y), 0.0); // 圆角框内侧的有符号距离。
		float aa = max(fwidth(edge) * 0.58, 0.002); // 圆角和描边共用像素抗锯齿宽度。
		float silhouette = smoothstep(-aa, aa, edge); // 框外保留透明，让格子间距与现有 UI 一致。
		float velvet_light = 1.0 - smoothstep(0.06, 0.53, length(point * vec2(1.07, 0.81))); // 红光沿小格子的纵向缓慢衰减。
		vec3 velvet = mix(ROSEWOOD, VELVET, velvet_light * (0.30 + 0.17 * focus_strength + 0.065 * beat)); // 心跳透过徽章底部映上绒面。
		float pressed = 1.0 - smoothstep(0.002, 0.009 + aa, abs(edge - 0.070)); // 金属内侧用烫印线压出一层绒面边。
		velvet = mix(velvet, COPPER, pressed * 0.56);

		float ambient = clamp(0.58 - point.y * 0.60 - point.x * 0.29, 0.17, 0.93); // 金框左上侧的常驻光源。
		float rim_width = 1.0 - smoothstep(0.032 - aa, 0.032 + aa, edge); // 圆角外缘留出一圈薄金属。
		float outer_lip = 1.0 - smoothstep(0.003, 0.016 + aa, abs(edge - 0.004)); // 面向光源的外侧切面。
		float inner_lip = smoothstep(0.018 - aa, 0.027 + aa, edge); // 暗槽内另一道反向切面。
		float gilding = clamp(outer_lip * (0.18 + 0.58 * ambient) + inner_lip * 0.37 + focus_strength * 0.23, 0.0, 1.0); // 悬停和选中时两个切面一起提亮。
		vec3 rim = mix(COPPER * (0.62 + ambient * 0.34), CHAMPAGNE, gilding); // 金色切面和它们之间的暗槽。
		vec3 frame = mix(velvet, rim, rim_width); // 绒面嵌在金边以内。
		float accent = fine_glint(point - vec2(0.0, 0.431), 0.084) * (0.37 + 0.29 * beat + 0.19 * focus_strength); // 徽章下方露出的单颗星芒。
		COLOR *= vec4(mix(frame, CHAMPAGNE, accent), silhouette);
	}
}
