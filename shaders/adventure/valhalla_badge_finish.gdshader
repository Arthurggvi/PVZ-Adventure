shader_type canvas_item;
render_mode unshaded;

// 底板四角的深蓝底色。
uniform vec4 night_color : source_color = vec4(0.039, 0.065, 0.135, 1.0);
// 中央光晕偏冷，与金色主体区分。
uniform vec4 halo_color : source_color = vec4(0.24, 0.29, 0.46, 1.0);
// 外缘的暗金与内层刻线。
uniform vec4 bronze_color : source_color = vec4(0.59, 0.35, 0.14, 1.0);
// 外缘最亮处与图标扫光使用同一暖金。
uniform vec4 gold_color : source_color = vec4(1.0, 0.88, 0.58, 1.0);
// 图标只为原画的金属和圣焰增光，底板另绘切角金边。
uniform bool icon_finish = false;
// 选中为 1.0，悬停向 0.72 渐亮，离开后回落到 0.0。
uniform float focus_strength : hint_range(0.0, 1.0) = 0.0;

// 根据到星心的局部距离和亮度，在靠近金边的位置绘出一枚细小星芒。
float star_glint(vec2 delta, float intensity, float antialias) {
	vec2 d = abs(delta); // 星心至像素的水平与垂直距离。
	float cross_light = max(0.023 - d.x - 2.7 * d.y, 0.031 - 2.7 * d.x - d.y); // 两条相交的光束。
	return smoothstep(-antialias, 0.022 + antialias, cross_light) * intensity;
}

void fragment() {
	if (icon_finish) {
		vec4 original = COLOR; // 以原画和节点调制色为底，保留原始透明度。
		float phase = min(mod(TIME, 7.8) / 2.15, 1.0); // 每轮短暂掠过画面，光带两端都在图标之外。
		float axis = dot(UV, vec2(1.0, 0.52)); // 斜向光带从左上掠向右下。
		float offset = abs(axis - mix(-0.21, 1.73, phase)); // 像素到光带轴线的距离。
		float gleam = (1.0 - smoothstep(0.010, 0.063, offset)) * 0.25
			+ (1.0 - smoothstep(0.020, 0.159, offset)) * 0.11; // 窄亮芯和漫反射肩部。
		float warmth = original.r - original.b; // 用红蓝差分出金色和蓝色阴影。
		float metal = smoothstep(0.19, 0.56, warmth)
			* smoothstep(0.35, 0.80, original.r); // 仅在暖色亮处表现镜面反光。
		vec3 lit = original.rgb + (vec3(1.0) - original.rgb) * vec3(1.0, 0.87, 0.62) * gleam * metal; // 补亮金属，同时保留原画明暗。

		vec2 hearth = (UV - vec2(0.5, 0.598)) * vec2(8.8, 6.1); // 椭圆罩住神殿门洞内的圣焰。
		float flame = (1.0 - smoothstep(0.12, 1.0, dot(hearth, hearth)))
			* smoothstep(0.18, 0.60, original.r) * smoothstep(0.10, 0.44, warmth); // 只让门洞本来受暖光照亮的部分起伏。
		float firelight = flame * (0.16 + 0.075 * sin(TIME * 1.62 + UV.y * 5.0)); // 让上下部位错开亮度，表现圣焰缓慢起伏。
		lit += (vec3(1.0) - lit) * vec3(1.0, 0.63, 0.14) * firelight;
		COLOR = vec4(lit, original.a);
	} else {
		vec2 centered = UV - vec2(0.5); // 以底板中心为原点的局部坐标。
		vec2 distance_to_center = abs(centered); // 取绝对值得到四角对称的轮廓。
		float edge = min(0.479 - max(distance_to_center.x, distance_to_center.y),
			0.82 - distance_to_center.x - distance_to_center.y); // 内侧为正的切角边缘距离。
		float antialias = max(fwidth(edge) * 0.60, 0.002); // 描边与细刻线共用的像素平滑宽度。
		float silhouette = smoothstep(-antialias, antialias, edge); // 边缘以外完全透明。

		float breath = 0.5 + 0.5 * sin(TIME * 1.24); // 圆光和两侧星芒以同一慢周期呼吸。
		vec2 halo_axes = centered * vec2(1.0, 0.94); // 略拉长圆光，让它顺着徽章的竖向轮廓展开。
		float radius_squared = dot(halo_axes, halo_axes); // 径向距离的平方，供圆光和细环共用。
		float halo = 1.0 - smoothstep(0.018, 0.26, radius_squared); // 夜蓝从徽章背后向四角渐暗。
		float arc = 1.0 - smoothstep(0.0025, 0.012, abs(radius_squared - 0.171)); // 可从原画两侧看到的细环。
		float arc_light = smoothstep(-0.40, 0.48, dot(centered, vec2(0.76, -0.65)) + (breath - 0.5) * 0.32); // 细环亮部随呼吸轻微偏移。
		vec3 backdrop = mix(night_color.rgb, halo_color.rgb, halo * (0.42 + breath * 0.10 + focus_strength * 0.19)); // 中央晕光为原画的金色轮廓提供冷色背景。
		backdrop = mix(backdrop, halo_color.rgb, arc * (0.17 + arc_light * 0.28));

		float engraving = 1.0 - smoothstep(0.001, 0.007 + antialias, abs(edge - 0.052)); // 金边内侧留一道压刻细线。
		backdrop = mix(backdrop, bronze_color.rgb, engraving * (0.42 + focus_strength * 0.16));
		float rim = 1.0 - smoothstep(0.033 - antialias, 0.033 + antialias, edge); // 金属面比原画外沿略宽。
		float outer_lip = 1.0 - smoothstep(0.002, 0.012 + antialias, abs(edge - 0.005)); // 外切面在轮廓处形成窄亮边。
		float inner_lip = smoothstep(0.015 - antialias, 0.026 + antialias, edge); // 窄暗槽过渡至朝内的斜面。
		float facet = 0.5 + dot(centered, vec2(-0.32, -0.66)); // 左上切面受光，右下反光较暗。
		vec3 rim_color = mix(bronze_color.rgb * 0.58, bronze_color.rgb, facet); // 自然受光的金属基底和暗槽。
		float gilding = clamp(outer_lip * (0.20 + facet * 0.58) + inner_lip * (0.41 - facet * 0.23) + focus_strength * 0.20, 0.0, 1.0); // 两道切面的高光从相反方向起伏。
		rim_color = mix(rim_color, gold_color.rgb, gilding);

		vec3 plate = mix(backdrop, rim_color, rim); // 将金属压边和底板合成，再在靠边位置叠入星芒。
		float stars = star_glint(centered - vec2(-0.435, -0.167), 0.13 + breath * 0.55, antialias)
			+ star_glint(centered - vec2(0.435, 0.165), 0.13 + (1.0 - breath) * 0.51, antialias); // 对角高光交替起伏，避开原画的翼尖。
		COLOR *= vec4(mix(plate, gold_color.rgb, stars), silhouette);
	}
}
