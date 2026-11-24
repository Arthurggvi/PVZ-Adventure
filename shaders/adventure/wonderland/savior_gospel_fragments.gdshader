shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// 同一株活体的最后一帧被切成静态微片，真实战斗秒驱动全部顶点。
uniform float fracture_age = 0.0;
uniform vec2 source_origin;
uniform vec2 frame_position;
uniform vec2 frame_size;
uniform float cell_span = 64.0;
uniform vec4 pose_tint = vec4(1.0);
varying flat float fragment_life;
varying flat float fragment_heat;

void vertex() {
	vec2 center = frame_position + COLOR.rg * frame_size;
	float seed = COLOR.b;
	vec2 radial = (center - source_origin) / cell_span;
	float delay = 0.048 * clamp(0.42 + radial.y * 0.52, 0.0, 1.0) + 0.043 * seed;
	float lifetime = mix(0.48, 0.68, seed);
	float t = clamp((fracture_age - delay) / lifetime, 0.0, 1.0);
	float release = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
	float entrain = smoothstep(0.20, 0.86, t);
	float turn = seed * TAU;
	vec2 jitter = vec2(cos(turn), sin(turn));
	vec2 burst = cell_span * (radial * vec2(0.58, 0.27) + jitter * mix(0.12, 0.38, seed)) * release;
	vec2 spread = burst;
	// 初段沿植物轮廓向外剥离，细片再随柱内气流转向、上卷。
	spread.x *= 1.0 - 0.59 * entrain;
	spread.x += (source_origin.x - center.x) * 0.71 * entrain;
	spread.x += sin(t * 5.4 + turn) * t * cell_span * 0.15;
	spread.y -= cell_span * mix(0.37, 0.94, seed) * t * t;
	float angle = (seed - 0.5) * 6.6 * release;
	mat2 tumble = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	float remnant = mix(1.0, 0.16, smoothstep(0.18, 0.96, t));
	VERTEX = center + tumble * (VERTEX - center) * remnant + spread;
	fragment_life = 1.0 - smoothstep(0.23, 1.0, t);
	fragment_heat = mix(0.89, 0.13, smoothstep(0.02, 0.68, t));
}

void fragment() {
	vec4 frame = texture(TEXTURE, UV) * pose_tint;
	float alpha = frame.a * fragment_life;
	if (alpha <= 0.007) {
		discard;
	}
	float pigment = dot(frame.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 ember = vec3(1.0, 0.19, 0.23) * (0.24 + 0.76 * pigment);
	vec3 color = mix(frame.rgb * vec3(0.84, 0.51, 0.51), ember, 0.56 * fragment_heat + (1.0 - fragment_life) * 0.24);
	color += vec3(0.21, 0.065, 0.048) * fragment_heat * pigment;
	COLOR = vec4(color * alpha, alpha);
}
