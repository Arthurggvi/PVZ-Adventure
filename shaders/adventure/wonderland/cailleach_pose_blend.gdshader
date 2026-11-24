// 先按杖身、关节与披风对齐原画，在柔和全身泛光的峰值交接纹理。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D idle_sheet : source_color, filter_linear, repeat_disable;
uniform sampler2D staff_sheet : source_color, filter_linear, repeat_disable;
// xy 为帧左上角的图集 UV，zw 为一个原画像素对应的 UV 步长。
uniform vec4 idle_region;
uniform vec4 staff_region;
// xy 为待机原画像素，zw 为杖击对应像素。第 11～13 点跟随待机披风。
uniform vec4 pose_points[13];
// 0 完整显示待机，1 完整显示杖击。
uniform float amount = 0.0;
// 合成平面四周为泛光留出的原画像素。
uniform vec2 bloom_margin = vec2(0.0);

// 原画单帧的像素尺寸。
const vec2 FRAME_SIZE = vec2(384.0);
// 光源接近中性白，离开身体后渐变为略冷的散射色。
const vec3 CORE_LIGHT = vec3(1.0, 0.993, 0.976);
const vec3 HALO_LIGHT = vec3(0.83, 0.93, 1.0);

// [point] 属于单帧像素坐标，将采样点夹在该帧的半纹素边界内。
vec2 frame_uv(vec4 region, vec2 point) {
	vec2 pixel = clamp(point, vec2(0.5), FRAME_SIZE - vec2(0.5));
	return region.xy + pixel * region.zw;
}

// 形变伸出原画格子的部分应当透明。
float frame_coverage(vec2 point) {
	return step(0.0, point.x) * step(point.x, FRAME_SIZE.x)
		* step(0.0, point.y) * step(point.y, FRAME_SIZE.y);
}

// [rest_pixel] 和 [tap_pixel] 已有形变位移，[handoff] 只在最亮时切换轮廓。
float silhouette(vec2 rest_pixel, vec2 tap_pixel, float handoff) {
	float rest = texture(idle_sheet, frame_uv(idle_region, rest_pixel)).a * frame_coverage(rest_pixel);
	float tap = texture(staff_sheet, frame_uv(staff_region, tap_pixel)).a * frame_coverage(tap_pixel);
	return mix(rest, tap, handoff);
}

// 在 [radius] 原画像素的范围收集实际轮廓。三层采样近似逐渐展开的光学扩散。
float bloom_ring(vec2 rest_pixel, vec2 tap_pixel, float handoff, float radius) {
	vec2 dx = vec2(radius, 0.0); // 横向点。
	vec2 dy = vec2(0.0, radius); // 竖向点。
	vec2 diagonal = vec2(radius * 0.7071068); // 等半径的斜向点。
	vec2 opposite = vec2(diagonal.x, -diagonal.y); // 与第一组斜向点垂直。
	return (silhouette(rest_pixel + dx, tap_pixel + dx, handoff)
		+ silhouette(rest_pixel - dx, tap_pixel - dx, handoff)
		+ silhouette(rest_pixel + dy, tap_pixel + dy, handoff)
		+ silhouette(rest_pixel - dy, tap_pixel - dy, handoff)
		+ silhouette(rest_pixel + diagonal, tap_pixel + diagonal, handoff)
		+ silhouette(rest_pixel - diagonal, tap_pixel - diagonal, handoff)
		+ silhouette(rest_pixel + opposite, tap_pixel + opposite, handoff)
		+ silhouette(rest_pixel - opposite, tap_pixel - opposite, handoff)) * 0.125;
}

void fragment() {
	vec2 pixel = UV * (FRAME_SIZE + 2.0 * bloom_margin) - bloom_margin; // 留边之外仍以原画脚点为准。
	vec2 displacement = vec2(0.0); // 插值姿态的局部位移。
	float total_weight = 0.0; // 归一化锚点贡献。
	for (int i = 0; i < 13; i++) {
		vec4 pose = pose_points[i]; // 一个身体或道具部位的起止像素。
		vec2 delta = pixel - mix(pose.xy, pose.zw, amount); // 到当前插值锚点的距离。
		float weight = 625.0 / (625.0 + dot(delta, delta)); // 邻近关节主导，远处变化平滑衰减。
		weight *= weight * weight;
		displacement += (pose.zw - pose.xy) * weight;
		total_weight += weight;
	}
	displacement /= max(total_weight, 0.0001);
	vec2 idle_pixel = pixel - displacement * amount;
	vec2 staff_pixel = pixel + displacement * (1.0 - amount);
	vec4 idle = texture(idle_sheet, frame_uv(idle_region, idle_pixel)) * frame_coverage(idle_pixel);
	vec4 staff = texture(staff_sheet, frame_uv(staff_region, staff_pixel)) * frame_coverage(staff_pixel);

	// 曝光平滑升降。原画只在曝亮峰值的短窗口交接，亮处仍保有少量层次。
	float handoff = smoothstep(0.42, 0.58, amount);
	float light = smoothstep(0.04, 0.47, amount) * (1.0 - smoothstep(0.53, 0.96, amount));
	float coverage = mix(idle.a, staff.a, handoff);
	vec3 premul = mix(idle.rgb * idle.a, staff.rgb * staff.a, handoff) * COLOR.rgb;
	float center = exp(-length((pixel - vec2(167.0, 169.0)) / vec2(173.0, 233.0))); // 肩身区域最亮，向袍脚与杖尖渐淡。
	float exposure = 1.0 - exp(-light * (2.55 + 2.10 * center));
	premul = mix(premul, CORE_LIGHT * coverage, exposure);

	// 轮廓扩散产生连续的宽柔边，光弱时沿用原画的精确边缘。
	float body = coverage;
	float halo = 0.0;
	if (light > 0.002 && coverage < 0.995) {
		float inner = bloom_ring(idle_pixel, staff_pixel, handoff, 5.0);
		float middle = bloom_ring(idle_pixel, staff_pixel, handoff, 13.0);
		float outer = bloom_ring(idle_pixel, staff_pixel, handoff, 23.0);
		body = mix(coverage, inner, light * 0.30);
		float emission = light * (0.71 * inner + 0.47 * middle + 0.26 * outer);
		halo = (1.0 - exp(-2.4 * emission)) * (1.0 - body);
	}
	float alpha = body + halo;
	vec3 body_rgb = coverage > 0.0001 ? premul / coverage : CORE_LIGHT;
	COLOR = vec4((body_rgb * body + HALO_LIGHT * halo) / max(alpha, 0.0001), alpha * COLOR.a);
}
