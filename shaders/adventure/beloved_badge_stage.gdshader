shader_type canvas_item;
render_mode unshaded;

// 0 为合拢，1 为打开。同一进度反向播放时，让金线和缎带沿原路径收回。
uniform float arrival : hint_range(0.0, 1.0) = 0.0;
// 展区宽高比，保证心匣、宝石和花瓣不随版面拉长。
uniform float stage_aspect : hint_range(0.4, 1.4) = 0.804780876;

// 暗槽内的玫瑰金。
const vec3 COPPER = vec3(0.47, 0.20, 0.15);
// 金属迎光面的暖香槟金。
const vec3 CHAMPAGNE = vec3(0.97, 0.69, 0.41);
// 雕刻亮沿和宝石星心的象牙色。
const vec3 IVORY = vec3(1.0, 0.92, 0.76);
// 深红缎面的受光色，也用于匣底的红宝石。
const vec3 RUBY = vec3(0.75, 0.16, 0.25);

// 按距线距离绘制细金线；[param half_width] 和 [param softness] 均以展区半宽为单位。
float line_mask(float distance_to_line, float half_width, float softness) {
	return 1.0 - smoothstep(half_width, half_width + softness, abs(distance_to_line));
}

// 返回心匣轮廓的距离，内侧为负。[param point] 的原点为徽章中心，坐标向下为正。
float heart_distance(vec2 point) {
	vec2 heart = vec2(abs(point.x) / 1.34, (0.82 - point.y) / 1.54); // 将左右折叠后，轮廓由圆弧和通向底端的斜边组成。
	vec2 lobe = heart - vec2(0.25, 0.75); // 拱肩的圆心。
	vec2 cleft = heart - vec2(0.0, 1.0); // 两片拱肩之间的转折点。
	vec2 taper = heart - 0.5 * max(heart.x + heart.y, 0.0); // 斜边在线上的垂直投影。
	float tip_distance = sqrt(min(dot(cleft, cleft), dot(taper, taper))) * sign(heart.x - heart.y); // 靠近凹口或尖端时取较近距离。
	return (heart.x + heart.y > 1.0 ? length(lobe) - 0.353553 : tip_distance) * 1.34;
}

// [param offset] 为距星心的横纵距离，[param span] 为最长光臂的长度。
float jewelry_glint(vec2 offset, float span, float softness) {
	vec2 delta = abs(offset); // 金属切面上的纵轴比横轴稍长。
	float rays = min(delta.x * 5.9 + delta.y, delta.x * 1.40 + delta.y * 6.1); // 两条由中心收尖的光臂。
	return 1.0 - smoothstep(span * 0.06, span + softness, rays);
}

void fragment() {
	vec2 point = (UV - vec2(0.5, 0.47)) * vec2(2.0, 2.0 / stage_aspect); // 原点对齐徽章中心，以展区半宽为单位。
	float across = abs(point.x); // 左右两片吊坠和丝带围绕中轴对称。
	float aa = max(fwidth(point.x) * 0.84, 0.003); // 细线在缩放下保留均匀的抗锯齿宽度。
	float progress = clamp(arrival, 0.0, 1.0); // 统一驱动宝石和金线展开。
	float jewelry = smoothstep(0.04, 0.30, progress); // 底端心匣扣最先亮起。
	float radiance = smoothstep(0.17, 0.86, progress); // 匣内灯光比扣件稍晚亮起。

	vec2 velvet_axes = point * vec2(1.03, 0.74); // 绒布反光沿纵向延伸。
	float velvet_falloff = 1.0 - smoothstep(0.08, 1.37, length(velvet_axes)); // 让装饰性亮部集中在徽章四周。
	float nap = sin(point.x * 121.0 + point.y * 5.0) * sin(point.y * 83.0 - point.x * 6.0); // 低对比的经纬绒纹。
	float velvet_folds = cos(point.x * 22.0 + sin(point.y * 4.4) * 0.52)
		* (0.62 + 0.38 * cos(point.x * 8.5 - point.y * 2.9)); // 宽窄略错开的绒面折光。
	vec3 color = vec3(0.092, 0.023, 0.037)
		+ vec3(0.27, 0.064, 0.090) * velvet_falloff * (0.52 + 0.20 * radiance + 0.11 * velvet_folds + 0.026 * nap); // 玫瑰木红的丝绒盒面。
	float warm_pool = 1.0 - smoothstep(0.04, 1.0, length((point - vec2(-0.20, -0.48)) * vec2(1.12, 0.90))); // 左上暖光让两边金线有明暗变化。
	color += vec3(0.18, 0.061, 0.039) * warm_pool * radiance;

	vec2 frame_point = abs((UV - vec2(0.5)) * vec2(2.0, 2.0 / stage_aspect)); // 珠宝盒外缘以展区几何中心为基准。
	float side = 0.941 - frame_point.x; // 两侧压边的留距。
	float cap = 1.0 / stage_aspect - 0.063 - frame_point.y; // 顶部和底部保持相同的像素外边距。
	float frame_distance = min(min(side, cap), (side + cap - 0.060) * 0.7071); // 四角斜切，内侧距离为正。
	float frame_bands = line_mask(frame_distance, 0.0025, aa)
		+ 0.48 * line_mask(frame_distance - 0.037, 0.0020, aa); // 外金线稍亮，内线烫印较淡。
	color *= mix(0.48, 1.0, smoothstep(-0.01, 0.044, frame_distance));
	color += mix(COPPER, CHAMPAGNE, warm_pool * 0.50) * frame_bands * 0.50;

	vec2 corner = vec2(side - 0.119, cap - 0.117); // 四角小饰钉以两条金线的内角为参考。
	float corner_diamond = line_mask(abs(corner.x) * 1.3 + abs(corner.y) - 0.045, 0.0025, aa); // 刻出细菱形。
	float corner_rays = jewelry_glint(corner, 0.042, aa); // 细长珠光位于菱形内部。
	float corner_thread = line_mask(corner.x, 0.0016, aa)
		* (1.0 - smoothstep(0.039, 0.065, abs(corner.y - 0.064))); // 菱形向盒边延伸的短刻针。
	color += COPPER * (corner_diamond * 0.65 + corner_thread * 0.46) + CHAMPAGNE * corner_rays * 0.38;

	float heart_edge = heart_distance(point); // 心匣的主要铜边轮廓。
	float inner_velvet = 1.0 - smoothstep(-0.055, -0.005, heart_edge); // 铜边内部压出较柔和的绒面阴影。
	float velvet_light = 1.0 - smoothstep(0.19, 0.92, length(point * vec2(0.99, 0.85))); // 徽章背面的暗红光晕。
	color *= 1.0 - inner_velvet * 0.30 * radiance;
	color += vec3(0.29, 0.067, 0.076) * velvet_light * inner_velvet * radiance;

	float draw_order = clamp((0.82 - point.y) * 0.51 + across * 0.20, 0.0, 1.0); // 镶边从心尖沿两侧向上描到凹口。
	float metal_head = mix(-0.16, 1.14, smoothstep(0.10, 0.83, progress)); // 金线在入场期间的位置。
	float traced = 1.0 - smoothstep(metal_head - 0.072, metal_head + 0.012, draw_order); // 亮头后留下完整的铜边。
	float gilded_head = line_mask(draw_order - metal_head + 0.014, 0.003, 0.037); // 扫过铜边的两道短暂亮头。
	float heart_relief = line_mask(heart_edge, 0.017, 0.019); // 在主线下面保留暗色凸缘。
	float heart_gold = line_mask(heart_edge - 0.005, 0.004, aa)
		+ 0.61 * line_mask(heart_edge + 0.055, 0.0028, aa)
		+ 0.42 * line_mask(heart_edge - 0.037, 0.0022, aa); // 镀金斜面和衬线配成三道细边。
	float reflected = smoothstep(-0.65, 0.84, sin(TIME * 0.75 + point.y * 3.4 - point.x * 2.2)); // 镶边上的镜面反光随时间移过。
	vec3 heart_metal = mix(COPPER, CHAMPAGNE, 0.32 + 0.46 * reflected); // 刻线留在徽章原画亮度之下。
	color *= 1.0 - heart_relief * traced * 0.47;
	color += (heart_metal * heart_gold * 0.75 + RUBY * heart_relief * 0.18) * traced;
	color += (IVORY * heart_gold * 0.69 + CHAMPAGNE * heart_relief * 0.27) * gilded_head;

	float ribbon_end = mix(0.04, 1.04, smoothstep(0.16, 0.82, progress)); // 两片丝带从扣件处向外舒展。
	float ribbon_reveal = (1.0 - smoothstep(ribbon_end - 0.079, ribbon_end + 0.013, across)) * jewelry; // 保留宽软的带尖。
	float ribbon_axis = 0.884 - 1.22 * across * across + 0.095 * sin(across * 7.3); // 横过心尖，再向两侧翻出的主缎带。
	float ribbon_width = mix(0.046, 0.009, smoothstep(0.53, 0.88, across)); // 丝带收窄至两端末梢。
	float ribbon_distance = point.y - ribbon_axis; // 缎面横截面，上沿为负、下沿为正。
	float ribbon_face = line_mask(ribbon_distance, ribbon_width, aa)
		* (1.0 - smoothstep(0.81, 0.94, across)); // 主缎带的表面遮罩。
	float satin = 1.0 - smoothstep(0.0, 1.35, abs(ribbon_distance / ribbon_width + 0.39)); // 折痕沿上沿留下狭长软反光。
	float ribbon_trim = line_mask(abs(ribbon_distance) - ribbon_width * 0.78, 0.0027, aa) * ribbon_face; // 上下两侧的勾金边。
	vec3 ribbon_color = mix(vec3(0.26, 0.029, 0.083), RUBY, satin * 0.66); // 暗红缎面与洋红反射。
	color = mix(color, ribbon_color, ribbon_face * ribbon_reveal * 0.86);
	color += mix(COPPER, CHAMPAGNE, satin * 0.73) * ribbon_trim * ribbon_reveal * 0.77;

	float loose_thread_axis = 0.937 - 0.78 * across * across + 0.119 * sin(across * 8.4); // 主缎带下方的金线绕过缎带尾端。
	float loose_thread = line_mask(point.y - loose_thread_axis, 0.0030, aa)
		* smoothstep(0.09, 0.30, across) * (1.0 - smoothstep(0.73, 0.93, across)); // 将细线两端收进绒面。
	float traveling_light = line_mask(across - ribbon_end + 0.038, 0.004, 0.059) * jewelry; // 两束亮反光随缎带展开。
	color += CHAMPAGNE * (loose_thread * ribbon_reveal * 0.51 + ribbon_trim * traveling_light * 0.39);

	vec2 clasp = point - vec2(0.0, 0.851); // 窄金线汇聚到匣底的扣件，保留与原画心形宝石的间距。
	float clasp_outline = abs(clasp.x) * 1.35 + abs(clasp.y); // 金叶压出的菱形轮廓。
	float clasp_body = 1.0 - smoothstep(0.087, 0.087 + aa, clasp_outline); // 红宝石表面。
	float clasp_setting = line_mask(clasp_outline - 0.088, 0.0040, aa)
		+ 0.57 * line_mask(clasp_outline - 0.112, 0.0022, aa); // 两道包住宝石的金线。
	float heartbeat = fract(TIME * 0.59); // 每组心跳约 1.7 秒，两次窄峰后留有停顿。
	float pulse = line_mask(heartbeat - 0.11, 0.005, 0.099)
		+ 0.61 * line_mask(heartbeat - 0.28, 0.006, 0.075); // 主拍和错后的次拍。
	float clasp_glow = 1.0 - smoothstep(0.0, 0.245, length(clasp * vec2(1.04, 1.27))); // 宝石在绒布上的散射红光。
	vec3 clasp_color = mix(vec3(0.34, 0.032, 0.106), RUBY, smoothstep(-0.082, 0.068, -clasp.y) * 0.85); // 宝石上半部反射柔红暖光。
	color += RUBY * clasp_glow * (0.12 + 0.14 * pulse) * jewelry;
	color = mix(color, clasp_color, clasp_body * jewelry);
	color += (CHAMPAGNE * clasp_setting * 0.73 + IVORY * jewelry_glint(clasp, 0.063, aa) * (0.38 + 0.38 * pulse)) * jewelry;

	vec3 petals = vec3(0.0); // 远离人像轮廓的花瓣和微小红宝石反光。
	for (int i = 0; i < 8; i++) { // 固定八片；只在这一块肖像区域求值。
		float seed = float(i) + 1.0; // 稳定的尺寸、路线和初始相位。
		float life = fract(TIME * (0.067 + 0.008 * fract(seed * 0.73)) + seed * 0.618); // 花瓣从上方飘向底部。
		float airflow = sin(life * 6.283185 + seed * 2.83); // 花瓣的横向飘动。
		float bank = mod(seed, 2.0) * 2.0 - 1.0; // 粒子分到舞台两侧。
		vec2 center = vec2(bank * (0.675 + 0.17 * fract(seed * 0.419) + airflow * 0.053),
			mix(-0.99, 0.86, life)); // 常驻粒子留在徽章外侧的窄带。
		vec2 offset = point - center; // 像素相对花瓣的位置。
		float size = 0.012 + 0.017 * fract(seed * 0.387); // 混合柔粉花瓣与更小的亮点。
		float shimmer = cos(TIME * (1.5 + fract(seed * 0.79)) + seed * 2.7); // 翻面时宽窄改变，正面反光增强。
		vec2 leaf = vec2(offset.x + offset.y * airflow * 0.84,
			offset.y * (1.73 + 0.61 * shimmer)); // 倾斜椭圆近似翻折的花瓣。
		float folded = (1.0 - smoothstep(size * 0.62, size + aa, length(leaf))); // 边缘柔化，保留清晰的瓣心。
		float blossom = 1.0 - smoothstep(size * size, size * size * 7.0, dot(offset, offset)); // 花瓣外的低亮红雾。
		float opacity = smoothstep(0.01, 0.19, life) * (1.0 - smoothstep(0.69, 0.99, life)); // 花瓣消失之后才回到顶端。
		vec3 petal_color = mix(RUBY, vec3(1.0, 0.64, 0.60), 0.49 + 0.28 * shimmer); // 花瓣正面偏粉，翻面露出深红。
		petals += (petal_color * folded * 0.71 + RUBY * blossom * 0.22) * opacity;
	}
	color += petals * smoothstep(0.48, 0.94, progress);

	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), COLOR.a);
}
