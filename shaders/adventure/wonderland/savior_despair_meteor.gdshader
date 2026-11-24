shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// 光束从拱顶持续到下移的前沿。亮纹和照明共用同一战斗时钟。
uniform vec4 head_arc = vec4(0.0);
uniform float flight_time = 0.0;
uniform float shaft_energy = 0.0;
uniform float shaft_drain = 0.0;
varying flat int stream_index;
varying flat float seed;

void vertex() {
	stream_index = int(round(COLOR.r * 3.0));
	seed = COLOR.g;
}

// 暗红柱体内的宽薄亮纹。两股纵向流动跨过同一截面，保留亮暗层次。
float light_strand(float x, float along, float offset, float phase) {
	float axis = x - offset - 0.053 * sin(along * 0.38 + phase);
	float current = 0.5 + 0.5 * sin(along + phase + 0.55 * sin(along * 0.62 + phase));
	return exp2(-51.0 * axis * axis) * current * current;
}

void fragment() {
	float s = UV.x;
	float behind = head_arc[stream_index] - s;
	if (behind < 0.0) {
		discard;
	}
	float x = UV.y * 2.0 - 1.0;
	float distance_to_axis = abs(x);
	float phase = seed * TAU;
	float fresh = 1.0 - smoothstep(0.055, 0.63, behind);
	float width = mix(0.72, 1.0, fresh) * mix(1.0, 0.44, smoothstep(0.018, 0.89, shaft_drain));
	float axis = x / width;
	float slow = s * 30.0 - flight_time * 38.0;
	float fast = s * 47.0 - flight_time * 63.0;
	float flow = 0.57 * light_strand(axis, slow, -0.27, phase)
		+ 0.43 * light_strand(axis, fast, 0.26, phase + 1.75);
	float sides = 1.0 - smoothstep(0.58, 1.0, distance_to_axis);
	float body = exp2(-2.65 * axis * axis) * sides;
	// 前沿以透光率渐隐，整个下缘保留宽截面。上段留在拱顶阴影中。
	float front = smoothstep(0.0, 0.040 + 0.034 * x * x, behind);
	float canopy = smoothstep(0.0, 0.20, s);
	float hot = exp2(-10.0 * behind) * exp2(-6.2 * axis * axis);
	// 光芯向落点回收，宽而暗的外层稍慢消散。两层都沿原弧长推进。
	float upper = mix(-0.18, 1.19, shaft_drain);
	float stagger = (0.077 + 0.021 * sin(x * 5.9 + phase)) * sin(shaft_drain * PI);
	float filament_reveal = smoothstep(upper - 0.105, upper + 0.088, s);
	float haze_reveal = smoothstep(upper - stagger - 0.18, upper - stagger + 0.065, s);
	float trail = max(smoothstep(0.055, 0.49, behind), shaft_drain * 0.52);
	float haze = exp2(-2.24 * x * x) * sides * trail * (0.125 + 0.065 * flow);
	float inner = clamp(0.47 * body + 0.30 * hot + 0.46 * flow, 0.0, 1.0);
	vec3 color = mix(vec3(0.34, 0.015, 0.058), vec3(0.96, 0.125, 0.209), inner);
	color = mix(color, vec3(1.0, 0.64, 0.51), hot * (0.18 + flow * 0.32));
	float veil = front * canopy * shaft_energy;
	float core_alpha = veil * body * filament_reveal * (0.47 + 0.27 * hot + 0.22 * flow);
	float haze_alpha = veil * haze * haze_reveal * (1.0 - core_alpha);
	COLOR = vec4(color * core_alpha + vec3(0.47, 0.023, 0.105) * haze_alpha, core_alpha + haze_alpha);
}
