shader_type canvas_item;
render_mode unshaded;

// 可见轨迹的世界宽度。UV 左侧贴着冲锋者，右侧是已经走过的路线。
uniform float width_px = 1.0;
// 战斗秒数，暂停时停止火线流动。
uniform float elapsed = 0.0;
// 本体为 1，分路黑影较低。
uniform float strength = 1.0;
// 收势后从 1 降到 0，火线变细，烟层逐渐断开。
uniform float energy = 1.0;

float hash_cell(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031);
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}

float noise_field(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0)), f.x), f.y);
}

float filament(float height, float center, float thickness) {
	return 1.0 - smoothstep(thickness * 0.30, thickness, abs(height - center));
}

void fragment() {
	// 地面位于画布底部上方 27 像素，烟带沿高度分层。
	float x = UV.x * width_px;
	float h = 159.0 - UV.y * 186.0;
	float curl = noise_field(vec2(x * 0.021 - elapsed * 2.2, h * 0.036 + elapsed * 0.55));
	float grain = noise_field(vec2(x * 0.058 + elapsed * 2.9, h * 0.082 - elapsed * 1.7));
	float length_mask = smoothstep(0.0, 11.0, x) * (1.0 - smoothstep(0.23, 1.0, UV.x));
	float breakup = smoothstep((1.0 - energy) * 0.70, (1.0 - energy) * 0.70 + 0.32, curl);
	float height_scale = mix(0.56, 1.0, energy) * mix(0.72, 1.0, strength);
	float low = filament(h, 5.0 + curl * 13.0, (22.0 + grain * 10.0) * height_scale);
	float upper = filament(h, 41.0 + curl * 46.0, (32.0 + grain * 21.0) * height_scale);
	float veil = (low * 0.64 + upper * 0.45) * (0.36 + 0.64 * grain) * breakup;

	// 长短不同的亮线穿过烟层，保留冲锋方向和横向速度感。
	float stream = noise_field(vec2(x * 0.034 - elapsed * 7.0, 11.0));
	float torn = noise_field(vec2(x * 0.024 - elapsed * 5.2, 23.0));
	float line = filament(h, 4.0 + 2.6 * sin(x * 0.09 - elapsed * 8.0), 2.8 * height_scale) * stream;
	line += filament(h, 27.0 + curl * 20.0, 2.5 * height_scale) * smoothstep(0.43, 0.76, torn) * 0.73;
	line += filament(h, 65.0 + 9.0 * sin(x * 0.04 + elapsed * 6.0), 2.0 * height_scale)
		* smoothstep(0.63, 0.83, stream) * 0.47;
	line *= energy * energy;

	vec3 soot = mix(vec3(0.027, 0.019, 0.043), vec3(0.19, 0.10, 0.26), upper * grain * 0.65);
	vec3 light = mix(vec3(0.36, 0.23, 0.50), vec3(0.73, 0.53, 0.87), stream * strength);
	float alpha = clamp(veil + line * 0.72, 0.0, 0.94) * length_mask * energy * strength;
	COLOR = vec4(mix(soot, light, clamp(line * 1.15, 0.0, 1.0)), alpha);
}
