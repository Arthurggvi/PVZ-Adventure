shader_type canvas_item;
render_mode unshaded;

// 相同的地面坐标跨越所有精灵部件。裂痕不沿每片素材的 UV 重复。
instance uniform vec2 ash_origin = vec2(0.0);
instance uniform float light_wear = 0.0;
instance uniform float disperse = 0.0;
varying vec2 ash_position;

void vertex() {
	ash_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - ash_origin;
}

float grain(vec2 cell) {
	vec3 mixed = fract(vec3(cell.xyx) * 0.1031);
	mixed += dot(mixed, mixed.yzx + 33.33);
	return fract((mixed.x + mixed.y) * mixed.z);
}

float stone_grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 s = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(mix(grain(cell), grain(cell + vec2(1.0, 0.0)), s.x),
		mix(grain(cell + vec2(0.0, 1.0)), grain(cell + vec2(1.0)), s.x), s.y);
}

void fragment() {
	float cover = smoothstep(0.03, 0.83, COLOR.a);
	float fine = grain(floor(ash_position * 0.84));
	float patch = stone_grain(ash_position * vec2(0.11, 0.19));
	// 让石砖在炭灰的稀疏处露出一点材质，主体仍是沉黑的剪影。
	float opacity = cover * mix(0.88, 0.99, fine * 0.56 + patch * 0.44);
	float wear = smoothstep(0.65, 1.0, light_wear);
	float fissure = 1.0 - smoothstep(0.009, 0.06, abs(patch + fine * 0.10 - 0.49));
	opacity *= 1.0 - 0.35 * wear * fissure;
	if (disperse > 0.0) {
		// 上缘先断，随后碎成仍贴在石面上的细小暗屑。
		float lift = clamp(0.80 + ash_position.y * 0.010, 0.0, 1.0);
		float resist = (patch * 0.56 + fine * 0.44) * 0.70 + lift * 0.30;
		opacity *= smoothstep(disperse - 0.05, disperse + 0.05, resist) * (1.0 - smoothstep(0.86, 1.0, disperse));
	}
	COLOR = vec4(vec3(0.010, 0.009, 0.015), opacity);
}
