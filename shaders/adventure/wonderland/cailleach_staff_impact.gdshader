// 贴地的双道冲击光和从杖尖展开的冷白星芒。坐标单位为世界像素。
shader_type canvas_item;
render_mode unshaded, blend_add;

// 从原画的触地帧开始计时。
uniform float age_seconds = 0.0;

float luminous_edge(float radius, float center, float width) {
	return 1.0 - smoothstep(width * 0.20, width, abs(radius - center));
}

void fragment() {
	// 与世界平面的 544×330 范围和杖尖偏移对齐。
	vec2 p = UV * vec2(544.0, 330.0) - vec2(272.0, 210.0);
	vec2 floor_point = p * vec2(1.0, 2.75);
	float radius = length(floor_point);
	float angle = atan(floor_point.y, floor_point.x + 0.0001);
	float age = age_seconds;
	float first_front = 14.0 + 210.0 * (1.0 - exp(-3.9 * age));
	float echo_age = max(age - 0.12, 0.0);
	float second_front = 10.0 + 215.0 * (1.0 - exp(-2.8 * echo_age));
	float first_fade = 1.0 - smoothstep(0.20, 0.88, age);
	float second_fade = smoothstep(0.0, 0.055, echo_age) * (1.0 - smoothstep(0.22, 0.83, echo_age));
	float ripple = (0.72 * luminous_edge(radius, first_front, 2.1 + 4.0 * age)
		+ 0.23 * luminous_edge(radius, first_front, 10.5)) * first_fade;
	ripple += luminous_edge(radius, second_front, 3.4) * second_fade * 0.47;

	// 起裂时沿地面逐段点亮，窄折线溶进后一道冰光。
	float fractures = pow(0.5 + 0.5 * cos(angle * 9.0 + sin(radius * 0.092 + angle * 7.0) * 0.34), 31.0);
	float fracture_reach = (66.0 + 42.0 * sin(angle * 3.0 + 0.5)) * (1.0 - exp(-16.0 * age));
	fractures *= smoothstep(3.0, 14.0, radius) * (1.0 - smoothstep(0.72 * fracture_reach, fracture_reach + 1.0, radius));
	fractures *= (1.0 - smoothstep(0.22, 0.72, age)) * 0.68;

	// 主十字保留窄亮芯，两道斜芒像同一颗星的折射。
	float gleam = 1.0 - smoothstep(0.10, 0.58, age);
	float falloff = exp(-length(p) / (48.0 + age * 72.0));
	vec2 diagonal = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	float cross = exp(-abs(p.x) * 0.33 - abs(p.y) * 0.029)
		+ exp(-abs(p.y) * 0.45 - abs(p.x) * 0.021) * 0.78;
	float refraction = (exp(-abs(diagonal.x) * 0.54 - abs(diagonal.y) * 0.046)
		+ exp(-abs(diagonal.y) * 0.54 - abs(diagonal.x) * 0.046)) * 0.38;
	// 白闪退开时，杖尖留下向左倾的冰光和短暂的星形亮芯。
	float height = max(-p.y, 0.0);
	float reach = 77.0 + 110.0 * (1.0 - exp(-9.0 * age));
	float beam_axis = p.x + height * 0.18;
	float taper = mix(14.0, 1.1, clamp(height / reach, 0.0, 1.0));
	float beam_fade = smoothstep(0.025, 0.15, age) * (1.0 - smoothstep(0.32, 0.72, age));
	float beam_shape = (1.0 - smoothstep(reach * 0.56, reach, height)) * smoothstep(2.0, 20.0, height);
	float lance = exp(-abs(beam_axis) / taper) * beam_shape * beam_fade;
	float prism = exp(-abs(beam_axis) * 0.55 - abs(height - 67.0) * 0.057)
		+ 0.76 * exp(-abs(beam_axis) * 0.033 - abs(height - 67.0) * 0.52);
	float flare = (cross + refraction) * gleam * 0.95 + lance * 0.66 + prism * beam_fade * 0.69;
	float scattered = falloff * (0.51 * gleam + 0.07 * first_fade) + lance * 0.16;
	float edge_fade = 1.0 - max(smoothstep(200.0, 272.0, abs(p.x)), smoothstep(92.0, 120.0, p.y));
	float alpha = min(1.0, ripple + fractures + flare + scattered) * edge_fade;
	vec3 cold_light = vec3(0.33, 0.72, 1.0);
	vec3 hot_light = vec3(1.0, 0.983, 0.89);
	COLOR = vec4(mix(cold_light, hot_light, clamp(flare + ripple * 0.44 + fractures * 0.62, 0.0, 1.0)), alpha);
}
