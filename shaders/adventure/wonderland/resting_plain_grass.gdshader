shader_type canvas_item;

// 草尖横向摆幅，单位为原贴图像素；低处几乎不位移。
uniform float amplitude_px : hint_range(0.0, 12.0) = 8.2;
// 草丛间的相位差让风从一侧掠过另一侧。
varying flat float grass_phase;
// 顶点色保留各处花草的原有调色与透明度。
varying vec4 grass_tint;

void vertex() {
	grass_phase = MODEL_MATRIX[3].x * 0.0073;
	grass_tint = COLOR;
}

void fragment() {
	float tip = 1.0 - UV.y; // 贴图顶部为草尖，底部固定在地面。
	float gust = sin(TIME * 0.69 - grass_phase + UV.x * 4.5); // 大片草随同一股轻风弯曲。
	float flutter = sin(TIME * 1.76 - grass_phase + UV.x * 14.0); // 草尖带有稍快而细碎的摆动。
	float bend = tip * tip * (0.72 * gust + 0.28 * flutter); // 摆幅从草根到草尖逐渐增加。
	vec2 sample_uv = UV - vec2(amplitude_px * bend, abs(bend) * 1.5) * TEXTURE_PIXEL_SIZE; // 轻风也会让叶尖稍低。
	vec2 inside = step(vec2(0.0), sample_uv) * step(sample_uv, vec2(1.0)); // 贴图外沿保持透明。
	COLOR = texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0))) * grass_tint;
	COLOR.a *= inside.x * inside.y;
}
