shader_type canvas_item;
render_mode unshaded;

// 动画由战斗时间驱动。正面尺寸来自碰撞盒，着色平面另外留出侧框和余光。
uniform float elapsed = 0.0;
uniform float width_px = 84.0;
uniform float view_width = 186.0;
uniform float height_px = 560.0;
uniform float rows = 5.0;
uniform float exit_progress = 0.0;
uniform float broken = 0.0;

// 一直保持平顶、平底和直侧边；只削掉转角的几个像素。
float frame_edge(vec2 pos, vec2 half_size) {
	vec2 edge = abs(pos) - half_size;
	return max(max(edge.x, edge.y), (edge.x + edge.y + 8.0) * 0.7071);
}

float stroke(float offset, float width) {
	return 1.0 - smoothstep(width, width + 0.8, abs(offset));
}

void fragment() {
	vec2 panel = vec2((UV.x - 0.5) * view_width, UV.y * height_px);
	vec2 anchor = vec2(0.0, height_px * 0.5);
	vec2 edge_size = vec2(width_px * 0.5 - 1.0, height_px * 0.5 - 7.0);
	float edge = frame_edge(panel - anchor, edge_size);
	float rear = frame_edge(panel - anchor - vec2(11.0, -6.0), edge_size);
	float glass_mask = 1.0 - smoothstep(-0.7, 0.7, edge);
	float rear_mask = (1.0 - glass_mask) * (1.0 - smoothstep(-0.7, 0.7, rear));

	// 横梁在等距花窗间连接两根直立边柱，首尾以水平梁封边。
	float pitch = (height_px - 26.0) / max(rows, 1.0);
	float bay = clamp((panel.y - 13.0) / pitch, 0.0, rows - 0.0001);
	float course = fract(bay);
	float divider = min(course, 1.0 - course) * pitch;
	float ends = min(panel.y - 7.0, height_px - 7.0 - panel.y);
	float column = glass_mask * stroke(abs(panel.x) - edge_size.x + 6.0, 0.85);
	float girder = glass_mask * max(stroke(divider, 1.2), stroke(ends - 4.5, 1.15));
	float corner = glass_mask * stroke(abs(panel.x) + divider - edge_size.x + 11.0, 0.65) * (1.0 - smoothstep(9.0, 16.0, divider));
	float facing = abs(panel.x) / edge_size.x;

	// 每扇以宽菱形玻璃和五瓣蚀纹组成，边框之间保留透明区域。
	float row_center = abs(course - 0.5) * 2.0;
	float facet_edge = abs(panel.x) - (32.0 - row_center * 29.0);
	float facet = (1.0 - smoothstep(-1.0, 0.6, facet_edge)) * glass_mask;
	float lead = glass_mask * stroke(facet_edge, 0.55);
	vec2 rosette = vec2(panel.x, (course - 0.5) * pitch);
	float petals = 7.5 + 3.7 * cos(atan(rosette.y, rosette.x + 0.0001) * 5.0);
	float engraving = glass_mask * (stroke(length(rosette) - petals, 0.38) + 0.6 * stroke(length(rosette), 1.0));
	float glint = pow(sin(panel.y * 0.036 - elapsed * 3.35 + panel.x * 0.048) * 0.5 + 0.5, 9.0);
	float rail = stroke(edge, 1.4);

	// 立面先成形，Cut-in 退出时中段闭锁，光沿横梁传向两端。
	float seam = 1.09 - clamp(elapsed / 0.61, 0.0, 1.0) * 1.24;
	float visible = smoothstep(seam - 0.15, seam + 0.08, UV.y);
	float rising = exp(-abs(UV.y - seam) * 34.0) * (1.0 - smoothstep(0.46, 0.72, elapsed));
	float travel = max(0.0, elapsed - 1.07) * 2.4;
	float sealing = exp(-abs(abs(UV.y - 0.45) - travel) * 34.0) * smoothstep(0.96, 1.13, elapsed)
			* (1.0 - smoothstep(1.36, 1.61, elapsed));

	// 到时由上向下逐扇拆解，破裂则沿玻璃接缝散开。
	float shard = fract(sin(floor(panel.x * 0.13) * 14.21 + floor(panel.y * 0.075) * 23.45) * 15731.94);
	float erode = mix(0.18 + floor(bay) / max(rows, 1.0) * 0.52 + course * 0.14 + shard * 0.12,
			0.27 + shard * 0.63, broken);
	float opacity = visible * (1.0 - smoothstep(erode - 0.075, erode + 0.06, exit_progress));
	float hot_edge = stroke((exit_progress - erode) * 50.0, 1.1) * glass_mask;

	vec3 jade = vec3(0.19, 0.64, 0.43);
	vec3 amber = vec3(1.0, 0.66, 0.26);
	vec3 alabaster = vec3(1.0, 0.96, 0.79);
	vec3 base = mix(jade, amber, facet * 0.46 + glint * 0.19 + facing * 0.09);
	float thread = girder * 0.72 + column * 0.46 + corner * 0.78 + lead * 0.38 + engraving * 0.69;
	float shine = clamp(rail * 0.87 + thread + rising + sealing + hot_edge, 0.0, 1.0);
	vec3 front_color = mix(base, alabaster, shine);
	float front_alpha = max(rail * 0.73 + thread * 0.47, glass_mask * (0.24 + facet * 0.10 + sealing * 0.37));
	front_alpha = max(front_alpha, exp(-max(edge, 0.0) * 0.12) * (0.15 + (rising + sealing) * 0.42));
	float rear_alpha = rear_mask * (0.25 + stroke(rear, 1.0) * 0.43 + girder * 0.14);
	vec3 rear_color = mix(jade * 0.69, amber, 0.58 + glint * 0.25);
	float depth = rear_alpha / max(front_alpha + rear_alpha, 0.001);
	COLOR = vec4(mix(front_color, rear_color, depth), min(front_alpha + rear_alpha, 0.97) * opacity);
}
