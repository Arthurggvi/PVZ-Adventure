shader_type canvas_item;
render_mode unshaded;

// 从 0 到 1 沿带噪声的切面瓦解；1 时完全透明。
uniform float dissolve = 0.0;
// 越亮的形态，紫灰轮廓越明显。
uniform float intensity = 1.0;
// 不同残影不在同一处断裂。
uniform float phase = 0.0;

varying vec4 tint;
varying vec2 world_point;

void vertex() {
	tint = COLOR;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

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

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
	float inner_alpha = min(texture(TEXTURE, UV - vec2(px.x, 0.0)).a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	inner_alpha = min(inner_alpha, min(texture(TEXTURE, UV - vec2(0.0, px.y)).a, texture(TEXTURE, UV + vec2(0.0, px.y)).a));
	float contour = clamp(art.a - inner_alpha, 0.0, 1.0);

	// 以世界坐标采样，各肢体的裂纹能够接在一起。
	float cloud = noise_field(world_point * vec2(0.035, 0.050) + vec2(phase, 0.0));
	float flakes = noise_field(world_point * vec2(0.12, 0.18) + vec2(0.0, phase));
	float field = cloud * 0.74 + flakes * 0.26;
	float edge = mix(-0.13, 1.01, dissolve);
	float coverage = smoothstep(edge, edge + 0.10, field);
	float fracture = coverage * (1.0 - smoothstep(edge + 0.07, edge + 0.17, field));
	float luminance = dot(art.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 soot = mix(vec3(0.026, 0.018, 0.044), vec3(0.17, 0.11, 0.24), luminance * 0.85);
	vec3 violet = vec3(0.42, 0.28, 0.55) * intensity;
	vec3 rim = violet * contour * (0.60 + 0.40 * cloud);
	vec3 crack = vec3(0.64, 0.42, 0.78) * fracture * intensity;
	COLOR = vec4((soot + rim + crack) * tint.rgb, art.a * tint.a * coverage);
}
