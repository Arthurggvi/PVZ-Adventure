// 辉夜的星云背景：与24枚真实星核共用旋臂、展开和自转曲线，纯美术而无碰撞。
shader_type canvas_item;
render_mode unshaded, blend_add;

// 外部可暂停的战斗时钟和生命周期，禁止使用全局TIME。
uniform float age = 0.0;
uniform float lifetime = 3.0;
// 保留场本身的透明度，局部云雾始终在真实星核后面。
varying vec4 tint;
void vertex() {
	tint = COLOR;
}

// 两层连续噪声让星臂边界碎成有纹理的气体，而不是几何宽线。
float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise_field(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	// 容器的240×200等比例画布已经由战场格距缩放，UV按各轴归一化即可。
	vec2 q = (UV - vec2(0.5)) * vec2(2.0 / 0.94, 2.0 / 0.78);
	float radial_guess = length(q);
	float growth = 1.0 - pow(1.0 - clamp(age / (0.46 + radial_guess * 0.34), 0.0, 1.0), 3.0);
	float radius = radial_guess / max(growth, 0.001);
	float spin = 0.31 * max(0.0, age - 0.1) * (0.46 + radius * 0.54);
	float uncoil = -(1.0 - growth) * 1.25;
	float angle = atan(q.y, q.x) - (radius * 2.95 + spin + uncoil);
	float noisy = noise_field(q * 15.0 + vec2(age * -0.12, age * 0.09));
	float grains = noise_field(q * 51.0 + vec2(age * 0.14, 0.8));
	float arm_distance = abs(sin((angle + (noisy - 0.5) * 0.18) * 1.5));
	float fine = exp(-pow(arm_distance / mix(0.25, 0.15, clamp(radius, 0.0, 1.0)), 2.0));
	float diffuse = exp(-pow(arm_distance / mix(0.55, 0.40, clamp(radius, 0.0, 1.0)), 2.0));
	float broken = mix(0.22, 1.0, smoothstep(0.24, 0.83, noisy));
	broken *= mix(0.55, 1.0, grains);
	float rim = 1.0 - smoothstep(0.67, 0.96, radius);
	float center_exclusion = smoothstep(0.035, 0.18, radius);
	float arrival = smoothstep(0.0, 0.14, age);
	float departure = smoothstep(0.0, 0.56, lifetime - age);
	float fade = arrival * departure;
	float gas = (fine * broken * 0.86 + diffuse * (0.27 + noisy * 0.38)) * rim * center_exclusion;
	float core = exp(-radius * radius * 34.0);
	vec3 cyan = vec3(0.09, 0.52, 1.0);
	vec3 violet = vec3(0.39, 0.22, 0.98);
	vec3 rose = vec3(0.91, 0.19, 0.66);
	vec3 color = mix(cyan, violet, smoothstep(0.15, 0.86, noisy));
	color = mix(color, rose, smoothstep(0.61, 0.91, grains) * 0.45);
	color = mix(color, vec3(0.97, 0.93, 1.0), core * 0.8);
	float alpha = clamp(gas * 1.34 + core * 0.76, 0.0, 0.82) * fade;
	COLOR = vec4(color, alpha) * tint;
}
