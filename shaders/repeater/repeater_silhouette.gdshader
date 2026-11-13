// 处决副本先变为完整白剪影，再沿连续世界噪声切面瓦解。
shader_type canvas_item;
render_mode unshaded;

// 变白、破碎分别由同一演出时钟提供。
uniform float whitening = 0.0;
uniform float dissolve = 0.0;
// 世界坐标种子让不同死者的裂纹错开。
uniform float phase = 0.0;
// 保存出土或入水时的原生裁切，白影不会突然显示被遮住的腿部。
uniform bool mask_enabled = false;
uniform float mask_cutoff = 0.0;
uniform bool mask_world = false;
uniform bool mask_above = false;
uniform float mask_fade = 0.0;
// 原姿态各部件颜色与世界坐标。
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
	float cloud = noise_field(world_point * vec2(0.04, 0.06) + vec2(phase, 0.0));
	float flakes = noise_field(world_point * vec2(0.17, 0.14) + vec2(0.0, phase));
	float field = cloud * 0.60 + flakes * 0.40;
	float threshold = mix(-0.16, 1.06, dissolve);
	float coverage = smoothstep(threshold, threshold + 0.06, field);
	float crack = coverage * (1.0 - smoothstep(threshold + 0.04, threshold + 0.14, field));
	vec3 color = mix(art.rgb * tint.rgb, vec3(0.96, 0.98, 1.0), whitening);
	color += vec3(0.30, 0.31, 0.36) * crack;
	float mask_alpha = 1.0;
	if (mask_enabled) {
		float clip_y = mask_world ? world_point.y : VERTEX.y;
		float distance = mask_above ? clip_y - mask_cutoff : mask_cutoff - clip_y;
		mask_alpha = mask_fade > 0.0 ? smoothstep(0.0, mask_fade, distance) : step(0.0, distance);
	}
	COLOR = vec4(color, art.a * tint.a * coverage * mask_alpha);
}
