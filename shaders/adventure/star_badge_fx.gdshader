shader_type canvas_item;
render_mode unshaded;
// One global clock for all instances. No per-card time offsets, timers, or random phase.
const float FX_PERIOD = 8.0;
const float CROWN_PERIOD = 16.0;
uniform int effect_mode = 0; // 0: body, 1: glint, 2: 10-star halo.
uniform float rank = 5.0;
uniform sampler2D sweep_mask : filter_linear;
uniform sampler2D number_guard : filter_linear;
uniform sampler2D rainbow_mask : filter_linear;

vec3 rotate_hue(vec3 c, float angle) {
	vec3 axis = vec3(0.57735026919);
	return clamp(c * cos(angle) + cross(axis, c) * sin(angle)
		+ axis * dot(axis, c) * (1.0 - cos(angle)), 0.0, 1.0);
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	vec4 result = original;
	float phase = mod(TIME, FX_PERIOD);
	if (effect_mode == 1) {
		float glint = smoothstep(1.03, 1.18, phase) *
			(1.0 - smoothstep(1.40, 1.62, phase));
		result.a *= glint;
	} else if (effect_mode == 2) {
		float crown_phase = mod(TIME, CROWN_PERIOD);
		float ambient = 0.17 + 0.07 * (0.5 + 0.5 * sin(TIME * 0.79));
		float burst = exp(-pow((crown_phase - 2.3) / 0.48, 2.0));
		result.a *= ambient + 0.48 * burst;
	} else {
		float guard = 1.0 - texture(number_guard, UV).r;
		if (rank >= 9.5) {
			float region = texture(rainbow_mask, UV).r * guard;
			vec3 rotated = rotate_hue(result.rgb,
				6.2831853 * mod(TIME, CROWN_PERIOD) / CROWN_PERIOD);
			result.rgb = mix(result.rgb, rotated, region * 0.52);
		}
		float center = mix(-0.45, 1.45, clamp(phase / 0.80, 0.0, 1.0));
		float distance = (UV.x + UV.y * 0.38 - center) / 0.085;
		float stripe = exp(-distance * distance);
		float sweep = stripe * (1.0 - step(0.80, phase)) *
			texture(sweep_mask, UV).r * guard * original.a;
		result.rgb = mix(result.rgb, vec3(1.0, 0.97, 0.83), sweep * 0.46);
		if (rank >= 9.5) {
			float crown_phase = mod(TIME, CROWN_PERIOD);
			float burst = exp(-pow((crown_phase - 2.3) / 0.38, 2.0));
			vec2 distance_to_top = UV - vec2(0.50, 0.18);
			float flash = exp(-dot(distance_to_top, distance_to_top) * 45.0)
				* burst * guard * 0.42;
			result.rgb = mix(result.rgb, vec3(1.0, 0.97, 0.80), flash);
		}
	}
	COLOR = result;
}
