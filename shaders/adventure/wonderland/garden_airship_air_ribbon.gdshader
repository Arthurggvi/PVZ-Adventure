shader_type canvas_item;
render_mode unshaded;

// 各条软雾通过实例数据选取预种形态，纹理坐标保持局部 0 至 1。
varying float ribbon_shape;

void vertex() {
	ribbon_shape = INSTANCE_CUSTOM.r * 7.0;
}

void fragment() {
	float along = UV.x; // 从后拖的薄尾到下风侧的圆润头部。
	float shape = floor(ribbon_shape + 0.5); // 还原随机形态编号，兼容较低精度实例存储。
	float crosswise = UV.y * 2.0 - 1.0; // 局部横跨四边形的方向。
	float envelope = smoothstep(0.0, 0.33, along) * (1.0 - smoothstep(0.62, 1.0, along)); // 进出边缘融入来流。
	float bend = 0.22 * sin(along * 6.3 + shape * 1.64) + 0.07 * sin(along * 17.0 + shape); // 不同云丝的卷曲程度。
	float body_width = mix(0.21, 0.72, envelope) * (0.89 + 0.11 * sin(along * 16.0 + shape)); // 收束两端和局部斑驳。
	float body = 1.0 - smoothstep(0.04, 1.0, abs(crosswise - bend) / body_width); // 横向羽化保留凝结的细芯。
	float fray_center = bend * 0.55 - 0.38 + 0.12 * sin(along * 11.0 + shape); // 从主体云缘松脱的一股细雾。
	float fray = (1.0 - smoothstep(0.06, 0.46, abs(crosswise - fray_center)))
		* smoothstep(0.12, 0.30, along) * (1.0 - smoothstep(0.49, 0.80, along));
	float mist = clamp(body * envelope + fray * 0.25, 0.0, 1.0); // 只在局部软边范围着色。
	COLOR.a *= mist;
}
