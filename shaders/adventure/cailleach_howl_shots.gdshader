// 单个实例可作为带寒光拖尾的真实雪弹，或接触植物时短促散开的碎雪。
shader_type canvas_item;
render_mode unshaded;

// X 选择贴图式形状，Y 是外观种子，Z 是撞击寿命比例。
varying vec3 shot_data;

void vertex() {
	shot_data = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	float seed = shot_data.y;
	float glow;
	float shine;
	if (shot_data.x < 0.5) {
		// 左侧的小雪核对应真实碰撞位置，右侧的拖尾随风拉长。
		vec2 offset = UV - vec2(0.258, 0.50);
		vec2 ellipse = offset * vec2(8.8, 2.6);
		float core = 1.0 - smoothstep(0.18, 0.59, abs(ellipse.x + ellipse.y * 0.19) + abs(ellipse.y) * 2.1);
		float halo = 1.0 - smoothstep(0.08, 1.0, dot(ellipse, ellipse));
		float trail_length = 0.30 + seed * 0.44;
		float stream = smoothstep(-0.055, 0.072, offset.x) * (1.0 - smoothstep(0.13, trail_length, offset.x));
		float streak = stream * (1.0 - smoothstep(0.030, 0.125 + seed * 0.050, abs(offset.y + offset.x * (seed - 0.5) * 0.17)));
		glow = max(halo * 0.34, streak * 0.56);
		shine = max(core * (0.52 + seed * 0.48), streak * (0.51 + seed * 0.21));
	} else {
		// 只描绘短寿命的近距离碎雪，不产生额外粒子或命中。
		float life = shot_data.z;
		vec2 offset = (UV - vec2(0.36, 0.54)) * vec2(1.06, 1.0);
		float radius = length(offset);
		float edge = 0.12 + life * 0.25;
		float cloud = 1.0 - smoothstep(edge * 0.26, edge * 1.13, radius);
		float value = sin(offset.x * (26.0 + seed * 7.0) + offset.y * 9.0)
			* sin(offset.y * 32.0 - offset.x * 13.0 + seed * 6.0);
		float fragments = smoothstep(0.49, 0.84, value) * (1.0 - smoothstep(edge * 0.82, edge * 1.12, radius));
		float fade = (1.0 - life) * (1.0 - life) * smoothstep(0.31, 0.43, UV.x);
		glow = (cloud * 0.61 + fragments * 0.54) * fade;
		shine = (cloud * 0.45 + fragments * 0.82) * fade;
	}
	COLOR = vec4(mix(vec3(0.67, 0.81, 0.92), vec3(0.975, 0.997, 1.0), clamp(shine * 1.38, 0.0, 1.0)),
		clamp(glow + shine * 0.57, 0.0, 1.0));
}
