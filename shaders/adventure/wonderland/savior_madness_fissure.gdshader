shader_type canvas_item;
render_mode unshaded, blend_mul;

// RGB 乘在真实石面上，Alpha 作为透过率传给现有世界捕获。原位精灵覆盖对应的余热。
uniform float battle_clock = 0.0;
uniform float lifetime = 1.8;
// 逐行使用地块外沿。顶沿存 Y 起止及左右 X，底沿存左右 X。
uniform int floor_row_count = 0;
uniform vec4 floor_row_tops[8];
uniform vec2 floor_row_bottoms[8];

varying vec2 ground_point;
varying vec4 fissure_data;

void vertex() {
	ground_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	fissure_data = CUSTOM0;
}

bool on_stone(vec2 point) {
	for (int i = 0; i < floor_row_count; i++) {
		vec4 strip = floor_row_tops[i];
		if (point.y >= strip.x && point.y <= strip.y) {
			vec2 edges = mix(strip.zw, floor_row_bottoms[i], (point.y - strip.x) / (strip.y - strip.x));
			if (point.x >= edges.x && point.x <= edges.y) {
				return true;
			}
		}
	}
	return false;
}

float stone_hash(float index, float seed) {
	return fract(sin(index * 127.13 + seed * 96.61) * 43758.5453);
}

// 沿真实弧长作连续过渡，让每处裂壁的厚度不同，保持同一段的结构稳定。
float along_crack(float coordinate, float seed) {
	float index = floor(coordinate);
	float fraction = fract(coordinate);
	return mix(stone_hash(index, seed), stone_hash(index + 1.0, seed),
		fraction * fraction * (3.0 - 2.0 * fraction));
}

float band(float distance_to_core, float half_width, float aa) {
	return 1.0 - smoothstep(max(0.0, half_width - aa), half_width + aa, distance_to_core);
}

void fragment() {
	// 顶点间插值出生时间，从最早裂开的部位开始冷却。熄灭的几何先丢弃再做材质采样。
	float age = max(0.0, battle_clock - fissure_data.x);
	float aa = clamp(fwidth(UV.y) * 0.67, 0.028, 0.24);
	if (age >= lifetime || !on_stone(ground_point)) {
		discard;
	}
	float seed = fissure_data.w;
	float ragged = along_crack(UV.x * 8.2, seed);
	float flake = along_crack(UV.x * 31.0 + 15.7, seed);
	float cross_section = UV.y - (ragged - 0.5) * 0.16;
	float distance_to_core = abs(cross_section);
	float width = fissure_data.y * mix(0.72, 1.19, ragged);
	float core = band(distance_to_core, 0.136 * width, aa);
	float wall = band(distance_to_core, 0.211 * width, aa);
	float charred = band(distance_to_core, (0.31 + 0.10 * flake) * width, aa);
	float bevel = mix(0.77, 1.0, smoothstep(-0.12, 0.12, cross_section));
	float scatter = exp2(-14.0 * distance_to_core * distance_to_core)
		* (1.0 - smoothstep(0.50, 0.93, distance_to_core));
	float life = 1.0 - smoothstep(lifetime * 0.68, lifetime, age);
	float heat = fissure_data.z * exp2(-1.95 * age) * life;
	float flare = (1.0 - smoothstep(0.13, 0.58, age)) * heat;
	float white = smoothstep(0.85, 0.995, flake) * (1.0 - smoothstep(0.025, 0.12, age)) * heat;
	float embers = mix(0.55, 1.0, smoothstep(0.16, 0.74, ragged));
	float emission = min(0.73, core * (0.40 * heat * embers + 0.35 * flare + 0.49 * white)
		+ max(0.0, wall - core) * bevel * (0.10 * heat + 0.10 * flare)
		+ scatter * (0.013 * heat + 0.018 * flare));
	if (max(charred * life, emission) < 0.003) {
		discard;
	}
	vec3 soot = mix(vec3(1.0), vec3(0.52, 0.39, 0.33), charred * life * (0.43 + flake * 0.27));
	vec3 molten_wall = mix(vec3(0.54, 0.41, 0.35), vec3(0.97, 0.62, 0.41), heat * bevel);
	vec3 stone_filter = mix(soot, molten_wall, wall * life * 0.65);
	stone_filter = mix(stone_filter, mix(molten_wall, vec3(1.0, 0.71, 0.44), flare), core * life * 0.62);
	// 相交时透过率相乘，暗分支不会盖住亮主纹。合成把合并的热量限制在单一上限。
	COLOR = vec4(stone_filter, 1.0 - emission);
}
