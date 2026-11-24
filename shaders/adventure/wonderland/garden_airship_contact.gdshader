shader_type canvas_item;
render_mode unshaded;

// 同一主战斗画布中的草皮边界，按左、上、右、下打包。保留未使用的零槽。
uniform vec4 receivers[9];
// 当前资源实际存在的接收平台数量。
uniform int receiver_count = 0;
// 局部角色滞空时的投影强度，贴地时为 1。
uniform float projection_strength = 1.0;
// 保留原阴影纹理和脚点。普通阴影有效范围由约 64×28 压到约 49×14 世界像素。
uniform vec2 footprint_scale = vec2(0.76, 0.52);
// 重型车辆使用整片车底和各轮胎接触点。
uniform bool vehicle_footprint = false;
// 裁切到甲板接收面。没有分离路面的地图可关闭裁切。
uniform bool clip_to_receivers = true;
// 正值压向车头、负值回弹至车尾，随悬挂动作变化。
uniform float vehicle_load = 0.0;
// 发射后坐产生的轮轴水平位移，单位为未缩放的角色局部像素。
uniform float axle_shift = 0.0;

// 画布世界坐标中的阴影片元和现有 Sprite2D 脚点。
varying vec2 world_point;
varying flat vec2 foot_point;
// 保留原精灵的透明度动画和淡入淡出。
varying vec4 shadow_tint;

void vertex() {
	shadow_tint = COLOR;
	foot_point = MODEL_MATRIX[3].xy;
	VERTEX *= footprint_scale;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 普通角色仍以脚点选平台；车辆各轮在经过草皮边界时逐个接地。
float receiver_coverage() {
	float coverage = 0.0; // 车辆足迹可能横跨两个接收面。
	for (int index = 0; index < receiver_count; index++) { // 接收面与甲板一起移动。
		vec4 bounds = receivers[index]; // 当前随动平台的实际接收边。
		if (vehicle_footprint) {
			bounds += vec4(-6.0, 0.0, 6.0, 0.0); // 大轮胎的接触面含草皮左右的窄木包边。
		}
		vec2 heel_margin = min(foot_point - bounds.xy, bounds.zw - foot_point); // 真实脚点到阴影面边缘。
		float heel_distance = min(heel_margin.x, heel_margin.y); // 脚跨边界时逐步收掉，而不是跳到下一个平台。
		if (vehicle_footprint || heel_distance >= 0.0) {
			vec2 margin = min(world_point - bounds.xy, bounds.zw - world_point); // 当前像素的边缘距离。
			float patch = smoothstep(0.0, 2.5, min(margin.x, margin.y)); // 草皮边缘内的软化宽度。
			if (!vehicle_footprint) {
				return patch * smoothstep(0.0, 4.0, heel_distance);
			}
			coverage = max(coverage, patch);
		}
	}
	return coverage;
}

// 车底的软遮蔽和胎面下沿的硬接触同处一个地面平面，不随车身俯仰。
float shadow_oval(vec2 point, vec2 radius, float softness) {
	vec2 local = point / radius; // 点到椭圆中心的归一化坐标。
	return 1.0 - smoothstep(softness, 1.0, dot(local, local));
}

// p 为炮塔阴影精灵的局部像素坐标，三处接触位置来自各轮胎的下沿。
float vehicle_profile(vec2 p) {
	p.x -= axle_shift;
	float belly = 0.31 * shadow_oval(p - vec2(-2.0, -7.5), vec2(72.0, 24.0), 0.01); // 底盘间的宽软阴影。
	float far_tire = shadow_oval(p - vec2(-43.0, -13.0), vec2(14.0, 6.8), 0.12); // 画面后侧前轮。
	float near_tire = shadow_oval(p - vec2(3.0, 1.5), vec2(15.0, 7.4), 0.16); // 可见前轮承接制动重量。
	float rear_tire = shadow_oval(p - vec2(39.0, -7.8), vec2(15.5, 6.7), 0.14); // 后轮回弹时重新受力。
	float tire = max(far_tire * (0.29 + 0.15 * vehicle_load),
		max(near_tire * (0.47 + 0.19 * vehicle_load), rear_tire * (0.42 - 0.16 * vehicle_load))); // 重叠处只取最深一层。
	return belly + (1.0 - belly) * tire;
}

void fragment() {
	float coverage = clip_to_receivers ? receiver_coverage() : 1.0; // 无独立接收面的地形使用完整阴影。
	float profile = vehicle_footprint
		? vehicle_profile((UV - 0.5) * vec2(163.4, 64.8) + vec2(0.0, -5.0))
		: min(texture(TEXTURE, UV).a * 2.0, 1.0) * 0.25; // 保留普通脚点的纹理渐变和强度。
	float alpha = profile * shadow_tint.a * coverage * projection_strength; // 保留角色透明度及滞空衰减。
	COLOR = vec4(0.115, 0.12, 0.095, alpha);
}
