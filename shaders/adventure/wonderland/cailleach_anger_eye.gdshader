// 白眼在雪中积光，星爆以白芯、光芒和漫射晕圈向外展开。
shader_type canvas_item;
render_mode unshaded, blend_add;

// 距离星爆的游戏秒，负值表示最后的蓄光。
uniform float strike_age = -0.33;

void fragment() {
	vec2 ray = (UV - vec2(0.5)) * vec2(2.06, 1.0); // 与平面的宽高比对齐，原点锁在亮眼。
	float age = max(0.0, strike_age);
	float radius = length(ray);
	float charge = smoothstep(-0.33, -0.024, strike_age); // 第一拍白影里只有眼睛看得清。
	float halo = exp(-radius * 29.0) * charge * 0.54;
	float hot = exp(-radius * 105.0) * charge * 0.88;
	float blast = step(0.0, strike_age) * (1.0 - smoothstep(0.027, 0.63, age));
	float span = mix(0.36, 0.93, 1.0 - exp(-age * 14.0)); // 迅速拉开的长横星芒。
	float streak = exp(-abs(ray.y) * 194.0 - abs(ray.x) * 4.6)
		* (1.0 - smoothstep(span * 0.60, span, abs(ray.x)));
	float vertical = exp(-abs(ray.x) * 165.0 - abs(ray.y) * 13.0);
	vec2 angle = vec2(ray.x + ray.y, ray.x - ray.y) * 0.70710678; // 两道较冷的斜芒比主光短。
	float facets = exp(-abs(angle.x) * 112.0 - abs(angle.y) * 11.3)
		+ exp(-abs(angle.y) * 129.0 - abs(angle.x) * 13.5);
	float scatter = exp(-radius * (12.0 - 3.0 * smoothstep(0.0, 0.28, age)));
	float front = 0.09 + 0.29 * (1.0 - exp(-age * 8.0)); // 白浪扩开的冷色晕边。
	float ring = exp(-abs(length(ray * vec2(0.64, 1.0)) - front) * 73.0);
	float echo = smoothstep(0.05, 0.16, age) * (1.0 - smoothstep(0.16, 0.62, age));
	float light = hot + halo + blast * (1.15 * streak + 0.81 * vertical + 0.58 * facets + 0.70 * scatter)
		+ 0.19 * ring * echo;
	light *= 1.0 - smoothstep(0.57, 0.94, age); // 冲击后留一点眼光再交回风雪。
	float border = 1.0 - max(smoothstep(0.36, 0.49, abs(ray.y)),
		smoothstep(0.87, 1.02, abs(ray.x)));
	vec3 cold = mix(vec3(0.51, 0.81, 1.0), vec3(1.0, 0.995, 0.982), smoothstep(0.16, 0.82, light));
	COLOR = vec4(cold, clamp(light * border, 0.0, 1.0));
}
