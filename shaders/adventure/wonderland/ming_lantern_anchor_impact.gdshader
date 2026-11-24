// 巨锚推动的低矮水脊与泡沫。横长面片在棋盘上沿水面扩散并衰减。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// 锚尖触地后经过的战斗秒数。
uniform float elapsed = 0.0;
// 面片在最大冲击半径外保留的边缘比例。
uniform float field_margin = 1.23;
// 各落点使用不同的波脊、衰退水膜与碎沫相位。
uniform float phase = 0.0;
// 棋盘水域的世界坐标边缘，冲击水纹到达边沿时退去。
uniform vec2 water_min;
uniform vec2 water_max;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// [offset] 是到薄水脊的距离，[width] 控制其水膜厚度。
float band(float offset, float width) {
	float position = offset / width; // 用平滑的宽度过渡衔接内外水色。
	return exp2(-position * position);
}

void fragment() {
	vec2 point = (UV * 2.0 - 1.0) * field_margin; // 压缩纵深后的归一化地面坐标。
	float radial = length(point); // 到撞击中心的水面距离。
	float pressure = 1.0 - exp(-elapsed * 5.1); // 触地冲力使水脊先猛然外扩，再被水阻减速。
	float front = 0.065 + 0.935 * pressure; // 与场景受光共用波前位置。
	vec2 shore = min(world_position - water_min, water_max - world_position); // 到最近水域边界的距离。
	float edge = smoothstep(-14.0, 19.0, min(shore.x, shore.y)); // 贴近边缘时从水脊过渡到薄水膜。
	float opacity = edge * smoothstep(0.0, 0.033, elapsed) * (1.0 - smoothstep(0.18, 1.10, elapsed)); // 碎沫退去后只剩很薄的水迹。
	if (opacity < 0.001 || radial > front + 0.22) {
		discard;
	}
	float angle = atan(point.y, point.x + 0.00001); // 分辨沿棋盘左右展开的水股。
	float fold = sin(angle * 9.0 + phase - elapsed * 10.0) + 0.48 * sin(angle * 18.0 - phase + radial * 9.0 + elapsed * 5.0); // 水脊由不等高的挤压隆起组成。
	float ridge = radial - front + fold * (0.014 + 0.03 * pressure); // 带起伏的主波前距离。
	float lateral = 0.66 + 0.34 * cos(angle) * cos(angle); // 视角下水花更明显地被推向左右两侧。
	float broad = band(ridge + 0.035, 0.085) * lateral; // 被猛推向棋盘的半透明厚水脊。
	float breaks = smoothstep(-0.47, 0.88, sin(angle * 14.0 + phase + sin(angle * 5.0) * 1.37 - elapsed * 5.2)); // 波峰的泡沫不是连续描边。
	float crest = band(ridge, 0.021) * (0.25 + 0.75 * breaks) * lateral; // 主水脊上碎开的白沫。
	float rim = band(ridge + 0.097 - fold * 0.012, 0.012) * (0.37 + 0.45 * sin(angle * 7.0 + phase) + 0.18 * breaks); // 回落的水膜卷成较细的第二道纹。
	float side = band(ridge + 0.162 + 0.016 * sin(angle * 13.0 + elapsed * 5.2), 0.016) * breaks; // 几股贴地流沫往前散开。
	float disturbed = band(radial - 0.13 * pressure, 0.26 + 0.18 * pressure) * (1.0 - smoothstep(0.075, 0.43, elapsed)); // 冲击留下的暂时浑水托住落点。
	float alpha = clamp(broad * 0.40 + crest * 0.66 + rim * 0.35 + side * 0.23 + disturbed * 0.23, 0.0, 1.0) * opacity; // 水量先铺开，再留下细碎反光。
	vec3 color = mix(vec3(0.18, 0.45, 0.53), vec3(0.82, 0.96, 0.97), clamp(crest + rim * 0.63 + side * 0.43, 0.0, 1.0)); // 蓝绿水脊上覆上泡沫亮边。
	COLOR = vec4(color * alpha, alpha);
}
