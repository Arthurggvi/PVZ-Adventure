// 浪脚扫过的地方铺下浅水与泡沫，留在原地向两侧散开。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 使用明灯浪头的战斗时钟、加速度和归一方向的世界 X。
uniform float clock_seconds = 0.0;
uniform float front_offset = 0.0;
uniform vec2 board_edges = vec2(0.0);
uniform float start_speed = 150.0;
uniform float acceleration = 0.0;
uniform float lifetime = 1.85;
uniform float phase = 0.0;
// 浪头到达终止线后的秒数；最后一截水边随摊平变软。
uniform float stopped_for = 0.0;

float band(float distance, float width) {
	float ratio = distance / width;
	return exp2(-ratio * ratio);
}

void fragment() {
	float distance = max(0.0, -UV.x); // 自出发点沿前进方向的实际像素。
	float passage = 2.0 * distance / (start_speed + sqrt(start_speed * start_speed + 2.0 * acceleration * distance));
	float age = clock_seconds - passage;
	float behind = UV.x - front_offset;
	float front_softness = mix(24.0, 41.0, smoothstep(0.04, 0.48, stopped_for));
	float envelope = smoothstep(1.0, front_softness, behind) * smoothstep(0.0, 0.055, age)
		* (1.0 - smoothstep(0.55, lifetime, age));
	float shore = smoothstep(board_edges.x, board_edges.x + 21.0, UV.x)
		* (1.0 - smoothstep(board_edges.y - 16.0, board_edges.y, UV.x));
	if (envelope * shore <= 0.002) {
		discard;
	}

	float settle = clamp(age / lifetime, 0.0, 1.0);
	float run = smoothstep(0.0, 0.55, settle); // 水顺着地面摊宽，再逐步隐去。
	float flow = UV.x * 0.044 + phase - settle * 3.6;
	float center = 0.70 + 0.052 * sin(flow) + 0.024 * sin(flow * 1.93 - 0.6);
	float y = UV.y - center;
	float width = mix(0.20, 0.29, run) + 0.035 * sin(flow * 1.23 + 0.6);
	float water = 1.0 - smoothstep(width * 0.65, width + 0.082, abs(y));
	float lane_edge = smoothstep(0.10, 0.32, UV.y) * (1.0 - smoothstep(0.93, 0.995, UV.y));
	float flecks = smoothstep(-0.4, 0.83, sin(flow * 2.8 + y * 20.0 + sin(flow * 1.18)));
	float banks = band(abs(y) - width * 0.82 + sin(flow * 1.76) * 0.035, 0.019);
	float streams = band(y + 0.065 * sin(flow * 2.20), 0.030)
		+ 0.57 * band(y + 0.12 - sin(flow * 1.36 + 0.8) * 0.058, 0.014);
	float ripples = band(sin(flow * 1.62 - (y * y * 29.0)), 0.22) * water * 0.54;
	float foam = max(banks * (0.48 + 0.45 * flecks), (streams + ripples) * (0.52 + 0.38 * flecks));
	foam *= 1.0 - 0.38 * settle;
	float reflection = 0.5 + 0.5 * sin(flow * 1.1 - y * 16.0); // 较宽的水膜有明暗，而细泡沫刻画流向。
	vec3 tint = mix(vec3(0.045, 0.25, 0.40), vec3(0.12, 0.55, 0.70), reflection * 0.63);
	vec3 color = mix(tint, vec3(0.77, 0.98, 0.98), min(foam, 0.93));
	COLOR = vec4(color, max(water * 0.80, foam * 0.91) * shore * lane_edge * envelope);
}
