shader_type canvas_item;
render_mode unshaded, blend_add;

// 实例数据为归一化时间、真光强度、光心离地高度、照到石面的程度。
varying flat vec4 light_state;
varying flat vec2 seed_and_exit;
varying vec2 section;

void vertex() {
	light_state = INSTANCE_CUSTOM;
	seed_and_exit = COLOR.rg;
	section = VERTEX;
}

// 固定在世界里的少量尘埃。偏移量由落点决定，镜头移动时不会重排。
float dust(vec2 grid, float seed) {
	float random = fract(sin(dot(floor(grid), vec2(16.71, 58.23)) + seed) * 4375.37);
	vec2 shift = vec2(fract(random * 9.71), fract(random * 13.39)) * 0.6 + 0.2;
	vec2 position = (fract(grid) - shift) * vec2(6.9, 5.3);
	return exp2(-dot(position, position) * 4.4) * smoothstep(0.48, 0.96, random);
}

void fragment() {
	float height = 0.64 - section.y * 0.86;
	float t = light_state.r;
	float offset = height - light_state.b;
	float lit_air = exp2(-4.5 * offset * offset);
	float air_bounds = smoothstep(0.035, 0.20, height) * (1.0 - smoothstep(1.02, 1.44, height));

	// 窗上方落下的斜向微光分散成两道疏密不一的空气纹理，脚边由真正的光场照亮。
	float sway = sin(height * 3.5 + seed_and_exit.x * 6.2831853) * 0.10;
	float slant = section.x + height * 0.22 + sway * (1.0 - light_state.a * 0.5);
	float thin_band = (slant + 0.13) * 5.9;
	float soft_band = (slant - 0.29) * 3.4;
	float thin = exp2(-thin_band * thin_band);
	float soft = exp2(-soft_band * soft_band);
	float folding_air = 0.68 + 0.32 * sin(height * 9.6 + section.x * 11.3 + seed_and_exit.x * 5.3);
	float haze = (0.23 * thin + 0.155 * soft) * folding_air;

	// 尘埃以缓慢的侧移伴随光上升/下移，完全融入世界曝光而非在 HUD 层加亮。
	float movement = t * mix(1.12, -1.95, seed_and_exit.y);
	vec2 grains = vec2((slant + 1.0) * 11.0 - t * 0.76,
		height * 12.0 + movement + 0.25 * sin(section.x * 9.0));
	float motes = dust(grains, seed_and_exit.x * 25.1) * (0.61 * thin + 0.43 * soft);
	float side_fade = 1.0 - smoothstep(0.61, 0.97, abs(section.x));
	float density = (haze + motes) * air_bounds * side_fade * lit_air * light_state.g;
	vec3 ivory = mix(vec3(0.83, 0.85, 0.91), vec3(1.0, 0.92, 0.74), 0.25 + 0.52 * thin);
	COLOR = vec4(ivory, density);
}
