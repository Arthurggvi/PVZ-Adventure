shader_type canvas_item;

// x 为告警覆盖强度，y 从黑相过渡到白相。
instance uniform vec2 warning = vec2(0.0);
// x 为焦化程度，y 为来自火场的反射光。
instance uniform vec2 wreck_heat = vec2(0.0);
// 0 为完整飞机，1 为机舱，2 和 3 为离散的两翼。
instance uniform int hull_section = 0;
varying vec4 hull_tint;

void vertex() {
	hull_tint = COLOR;
}

void fragment() {
	vec4 sprite = texture(TEXTURE, UV);
	vec3 lit = sprite.rgb * hull_tint.rgb;
	float luma = dot(clamp(lit, vec3(0.0), vec3(1.0)), vec3(0.2126, 0.7152, 0.0722));
	float shadow = 0.035 + 0.44 * luma;
	float highlight = 0.47 + 0.53 * pow(luma, 0.67);
	float monochrome = mix(shadow, highlight, warning.y);
	vec3 painted = mix(lit, vec3(monochrome), warning.x);
	vec3 scorch = vec3(0.064, 0.046, 0.041) + luma * vec3(0.24, 0.18, 0.145);
	painted = mix(painted, scorch, wreck_heat.x);
	painted += wreck_heat.y * (0.27 + 0.73 * luma) * vec3(0.92, 0.42, 0.12);

	float coverage = 1.0;
	if (hull_section != 0) {
		// 切线沿机翼与座舱拼缝，左右子片共用同一原图。
		vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
		float torn = sin(pixel.x * 0.62) * 2.1 + sin(pixel.x * 0.19) * 3.6;
		float seam_far = 125.0 + max(pixel.x - 300.0, 0.0) * 0.38 + torn;
		float seam_near = 405.0 - max(pixel.x - 265.0, 0.0) * 0.46 - torn;
		float far_wing = smoothstep(-0.8, 0.8, seam_far - pixel.y);
		float near_wing = smoothstep(-0.8, 0.8, pixel.y - seam_near);
		if (hull_section == 2) {
			coverage = far_wing;
		} else if (hull_section == 3) {
			coverage = near_wing;
		} else {
			coverage = (1.0 - far_wing) * (1.0 - near_wing);
		}
	}
	COLOR = vec4(painted, sprite.a * hull_tint.a * coverage);
}
