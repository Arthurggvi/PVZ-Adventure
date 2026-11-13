// 地狱弹的空间裂口：纵向撕裂入场、立体漩涡吸入、中心坍缩，只有一张局部画布。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 可暂停的战斗时间和完整五秒寿命。
uniform float age = 0.0;
uniform float lifetime = 5.0;
// 高并发时省略次级流线，不修改吸血逻辑。
uniform int quality = 0;
// 保留宿主淡出和透明度。
varying vec4 tint;
void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float enter = smoothstep(0.0, 0.25, age);
	float leave = 1.0 - smoothstep(lifetime - 0.50, lifetime, age);
	// 起初是一条黑暗纵向裂缝，随后横向撕开成被俯视的黑洞。
	vec2 elliptical = vec2(q.x / max(enter * leave * 0.92, 0.035), q.y / (0.79 * max(leave, 0.035)));
	float radius = length(elliptical);
	float angle = atan(elliptical.y, elliptical.x);
	float turn = angle + radius * 6.5 + age * 1.48;
	float arms = pow(0.5 + 0.5 * sin(turn * 3.0), 3.0);
	float inner_rim = exp(-pow((radius - 0.54) * 5.5, 2.0));
	float outer_rim = exp(-pow((radius - 0.76) * 7.0, 2.0));
	float glare = inner_rim * arms;
	float wave = 1.0;
	if (quality < 2) {
		wave = 0.80 + 0.20 * sin(angle * 8.0 - age * 2.6 + radius * 8.0);
	}
	float corona = (glare * 0.75 + outer_rim * 0.32) * wave;
	float vortex_mask = 1.0 - smoothstep(0.80, 1.02, radius);
	float abyss = 1.0 - smoothstep(0.25, 0.55, radius);
	float fade = smoothstep(0.0, 0.09, age) * smoothstep(0.0, 0.15, lifetime - age);
	vec3 ink = vec3(0.025, 0.006, 0.041);
	vec3 violet = vec3(0.36, 0.07, 0.70);
	vec3 ember = vec3(0.73, 0.13, 0.29);
	vec3 color = mix(ink, violet, clamp(corona, 0.0, 0.85));
	color = mix(color, ember, outer_rim * (0.15 + 0.20 * arms));
	color = mix(color, ink * 0.18, abyss);
	float alpha = clamp(vortex_mask * (0.40 + 0.24 * corona) + abyss * 0.57, 0.0, 0.97) * fade;
	COLOR = vec4(color, alpha) * tint;
}
