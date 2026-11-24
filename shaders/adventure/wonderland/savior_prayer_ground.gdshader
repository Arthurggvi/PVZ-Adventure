shader_type canvas_item;
render_mode unshaded, blend_mix;

// 起手时间、黑泪释放后的时间和主滴飞行时间，单位为战斗秒。
uniform float age = 0.0;
uniform float released_time = -1.0;
uniform float flight_seconds = 0.28;
varying vec2 surface;
varying flat vec2 tile;

void vertex() {
	// 以真实网格顶点为坐标。每格各自保留传播延迟和固定裂纹种子。
	surface = VERTEX;
	tile = INSTANCE_CUSTOM.rg;
}

// 按像素宽度软化刻痕边缘。
float groove(float value, float center, float width, float aa) {
	return 1.0 - smoothstep(width, width + aa, abs(value - center));
}

float grit(vec2 point) {
	vec3 p = fract(vec3(point.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec2 p = surface;
	float radius = length(p);
	if (radius > 1.0 || age <= 0.03) {
		discard;
	}
	float theta = atan(p.y, p.x + 0.00001);
	float aa = clamp(fwidth(radius) * 0.53, 0.012, 0.048);
	float phase = theta + 0.42 * tile.y;
	float hit = released_time - flight_seconds - tile.x;
	float wet = smoothstep(0.0, 0.085, hit) * (1.0 - smoothstep(0.25, 0.69, hit));
	float chipped_edge = 0.020 * sin(phase * 5.0 + tile.y * 7.0) + 0.013 * sin(phase * 13.0);
	float spill_lobes = 0.059 * sin(phase * 3.0 + tile.y * 9.0) + 0.041 * sin(phase * 7.0 - 0.7)
		+ 0.025 * sin(phase * 11.0 + tile.y);
	float reach = mix(0.30, 0.83, smoothstep(0.0, 0.24, hit));
	float carved_radius = radius + chipped_edge;
	float wax_radius = carved_radius + wet * spill_lobes;
	// 反光只留在缺口的两边，主体是渗进石面的深色蜡迹。
	float missing_arc = smoothstep(-0.81, -0.58, sin(phase - 0.35));
	float chipped = smoothstep(-0.76, -0.28, sin(phase * 6.0 + 0.55 * sin(phase * 9.0)));
	float scar = groove(carved_radius, 0.73, mix(0.013, 0.031, chipped), aa) * missing_arc;
	float edge = groove(carved_radius, 0.765, 0.008, aa) * missing_arc * chipped;
	// 一道弯折主裂痕在近端分叉，各格的分叉角度轻微错开。
	float incision = p.x + 0.21 * p.y + 0.039 * sin(p.y * 13.0 + tile.y * 4.0);
	float tip = 1.0 - smoothstep(0.31, 0.54, radius);
	float trunk = groove(incision, 0.0, 0.014, aa * 0.8) * tip;
	float fork = groove(incision - (p.y + 0.05) * (0.63 + 0.15 * tile.y), 0.0, 0.010, aa)
		* smoothstep(-0.08, 0.03, p.y) * (1.0 - smoothstep(0.24, 0.40, radius));
	float line_amount = smoothstep(0.03, 0.27, age);
	float cracks = groove(sin(phase * 5.0 + radius * 2.5), 0.0, 0.075, 0.09)
		* smoothstep(0.20, 0.32, radius) * (1.0 - smoothstep(0.67, 0.91, radius));
	float flecks = smoothstep(0.88, 1.0, grit(floor(p * vec2(27.0, 16.0) + 61.0 * tile.y)));
	float broken = 1.0 - smoothstep(0.37, 0.69, hit);
	float dry = mix(1.0, 0.29 + 0.71 * flecks, smoothstep(0.29, 0.63, hit));
	float porosity = 0.92 + 0.08 * sin(p.x * 22.0 + sin(p.y * 21.0) * 0.46);
	float stain = (1.0 - smoothstep(reach - 0.17, reach + aa, wax_radius)) * wet * dry * porosity;
	float strike = groove(wax_radius, reach - 0.042, 0.014, aa) * chipped * wet;
	float grain_edges = flecks * wet * smoothstep(0.54, 0.70, radius) * (1.0 - smoothstep(0.86, 0.98, radius));
	float dark = clamp((scar * 0.66 + trunk * 0.58 + fork * 0.49) * line_amount * broken
		+ stain * 0.80 + cracks * wet * 0.18, 0.0, 0.91);
	float silver = edge * 0.41 * line_amount * broken + strike * 0.55 + cracks * wet * 0.24 + grain_edges * 0.22;
	vec3 wax = vec3(0.050, 0.038, 0.065);
	vec3 etched = vec3(0.58, 0.53, 0.62);
	float alpha = dark + silver * (1.0 - dark);
	COLOR = vec4(mix(wax, etched, silver / max(dark + silver, 0.001)), alpha);
}
