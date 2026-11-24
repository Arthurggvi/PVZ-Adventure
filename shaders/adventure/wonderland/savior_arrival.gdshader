shader_type canvas_item;

// 原画保留位置和比例。衣摆先在石面亮起来，退场时明暗从石面向头环退去。
uniform float presence : hint_range(0.0, 1.0) = 0.0;
uniform float ivory : hint_range(0.0, 1.0) = 0.0;
uniform bool retreating = false;
varying vec2 pose_position;

void vertex() {
	pose_position = VERTEX;
}

void fragment() {
	float height = clamp(-pose_position.y / 347.0, 0.0, 1.0);
	float across = (pose_position.x + 20.0) / 120.0;
	float contour = 0.065 * sin(across * 4.3 + height * 3.4);
	float distance_to_light = clamp((retreating ? 1.0 - height : height) + contour, 0.0, 1.0);
	float cloth = smoothstep(-0.19, 0.21, presence * 1.49 - 0.26 - distance_to_light);

	// 白光主要擦过朝向来光的一侧。暗部保持原画中的衣褶和眼窝。
	float source_side = 1.0 - smoothstep(-0.46, 0.96, across);
	float reception = ivory * (0.29 + 0.68 * source_side);
	float luma = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 reflected = vec3(1.0, 0.947, 0.865) * pow(max(luma, 0.0001), 0.65);
	COLOR.rgb = mix(COLOR.rgb, reflected, reception);
	if (reception > 0.001 && COLOR.a > 0.001) {
		float ink = texture(TEXTURE, UV).a;
		float lit_edge = texture(TEXTURE, UV - vec2(1.25, 0.75) * TEXTURE_PIXEL_SIZE).a;
		float bevel = smoothstep(0.13, 0.79, ink - lit_edge) * reception;
		COLOR.rgb += vec3(0.52, 0.44, 0.31) * bevel;
	}
	COLOR.a *= cloth;
}
