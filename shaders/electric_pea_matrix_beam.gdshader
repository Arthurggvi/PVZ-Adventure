// 四层连续矩阵主线以同一横截面绘制，维持线段实际起止点。
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec4 rim_tones[5];
uniform vec4 core_tones[5];
uniform vec4 glow_tones[5];

// 实例等阶和父 CanvasItem 的颜色乘数。
varying float rank_index;
varying vec4 beam_tint;

void vertex() {
	rank_index = INSTANCE_CUSTOM.r * 4.0;
	beam_tint = COLOR;
}

// [solid] 为实体半宽，[fade] 为一侧羽化宽度，二者均为世界像素。
float coverage(float distance_from_axis, float solid, float fade) {
	return 1.0 - clamp((distance_from_axis - solid) / fade, 0.0, 1.0);
}

void fragment() {
	int rank = clamp(int(rank_index + 0.5), 0, 4);
	float radius = abs(UV.y - 0.5) * 8.0;
	// 数值沿用原四层笔画扣除羽化后的实体宽度。
	float glow = 0.035 * coverage(radius, 3.375, 0.5);
	float pale_rim = 0.08 * coverage(radius, 1.875, 0.5);
	float rim = 0.32 * coverage(radius, 0.875, 0.5);
	float core = 0.62 * coverage(radius, 0.2125, 0.2125);
	// 先在同一片元合成四层透明度，结果直接参与 Canvas 的预乘混合。
	float rim_combined = rim + pale_rim * (1.0 - rim);
	float halo = glow * (1.0 - rim_combined) * (1.0 - core);
	float edge = rim_combined * (1.0 - core);
	vec3 rgb = glow_tones[rank].rgb * halo + rim_tones[rank].rgb * edge + core_tones[rank].rgb * core;
	COLOR = vec4(rgb * beam_tint.rgb, halo + edge + core) * beam_tint.a;
}
