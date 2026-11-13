// 辉夜可暂停的星系薄雾：在单张局部贴片中表现冲击、旋臂、坍缩，不参与命中。
shader_type canvas_item;
render_mode unshaded, blend_add;

// 战斗场每次刷新视觉时传入的年龄与总寿命，不使用全局TIME。
uniform float age = 0.0;
uniform float lifetime = 3.0;
// 等级0完整、1中等、2廉价；着色器不修改任何伤害几何。
uniform int quality = 0;
// 顶点原本的颜色与透明度须保持可用。
varying vec4 tint;
void vertex() {
	tint = COLOR;
}

void fragment() {
	// UV各轴直接与本地格距映射；长宽受主场控制，避免全屏后处理。
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float radius = length(q / vec2(0.94, 0.80));
	float open = 1.0 - pow(1.0 - clamp(age / 0.32, 0.0, 1.0), 3.0);
	float collapse = 1.0 - smoothstep(lifetime - 0.42, lifetime, age);
	float r = radius / max(open * collapse, 0.03);
	float theta = atan(q.y, q.x) - r * 3.35 - age * 0.30;
	float arm = 1.0 - smoothstep(0.08, 0.79, abs(sin(theta * 1.5)));
	float wave = 0.70;
	if (quality < 2) {
		wave = 0.72 + 0.28 * sin(theta * 5.0 + r * 7.0 - age * 1.3);
	}
	float rim = 1.0 - smoothstep(0.69, 0.98, r);
	float center_gap = smoothstep(0.045, 0.20, r);
	float body = (0.12 + arm * 0.82) * rim * center_gap * wave;
	float core = exp(-radius * radius * 56.0) * (1.0 - smoothstep(0.0, 0.35, age));
	float onset = smoothstep(0.0, 0.10, age);
	float decay = smoothstep(0.0, 0.29, lifetime - age);
	vec3 ice = vec3(0.14, 0.52, 0.99);
	vec3 violet = vec3(0.47, 0.18, 0.96);
	vec3 rose = vec3(0.86, 0.24, 0.73);
	vec3 gas = mix(ice, violet, smoothstep(0.22, 0.92, arm));
	if (quality == 0) {
		gas = mix(gas, rose, 0.13 + 0.18 * wave);
	}
	float alpha = clamp(body * 0.61 + core * 0.72, 0.0, 0.78) * onset * decay;
	COLOR = vec4(mix(gas, vec3(0.96, 0.95, 1.0), core), alpha) * tint;
}
