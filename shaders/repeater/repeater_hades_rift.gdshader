// 冥弹的黑白冥焰斩痕，使用有限局部采样，所有阶段由战斗时钟控制。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 当前演出秒数，暂停时冻结。
uniform float age = 0.0;
// 普通命中和处决各自的有限寿命。
uniform float lifetime = 0.52;
// 处决增加裂口长度和边缘光量，不读取角色状态。
uniform bool execution = false;
// 子弹来向决定主斩痕的方向。
uniform float heading = 0.0;
// 次级灵魂碎片的绘制质量。
uniform int quality = 0;
// 保留宿主透明度。
varying vec4 tint;

void vertex() { tint = COLOR; }

// 一维连续扰动控制边焰，不需要外部噪声纹理。
float ripple(float value) {
	return sin(value * 13.0) * 0.55 + sin(value * 29.0 + 1.7) * 0.29 + sin(value * 61.0 - 0.9) * 0.16;
}

// 按透明度叠加预乘颜色，避免黑裂口周围被加法混合漂白。
vec4 over(vec4 back, vec3 ink, float opacity) {
	float alpha = clamp(opacity, 0.0, 1.0); // 单层覆盖率。
	return vec4(ink * alpha + back.rgb * (1.0 - alpha), alpha + back.a * (1.0 - alpha));
}

void fragment() {
	vec2 uv_point = (UV - vec2(0.5)) * 2.0; // 相对命中点的局部坐标。
	float turn = heading + 0.34; // 斜切比垂直光柱更具攻击动势。
	vec2 point = vec2(uv_point.x * cos(turn) + uv_point.y * sin(turn), -uv_point.x * sin(turn) + uv_point.y * cos(turn)); // 随来向旋转。
	float time = clamp(age / lifetime, 0.0, 1.0); // 完整生命周期比例。
	float opening = 1.0 - pow(1.0 - clamp(age / 0.13, 0.0, 1.0), 3.0); // 短促地拔出斩痕。
	float closing = 1.0 - smoothstep(0.30, 1.0, time); // 后半程收窄裂缝。
	float fade = (1.0 - smoothstep(0.65, 1.0, time)) * smoothstep(0.0, 0.015, age); // 两端平滑退出。
	float reach = (0.22 + 0.64 * opening) * (0.78 + 0.22 * closing); // 刀锋纵向半长。
	float taper = pow(max(0.0, 1.0 - abs(point.y) / max(reach, 0.001)), 0.68); // 两端形成长尖。
	float curl = ripple(point.y * 1.5 - age * 2.3) * 0.018 * taper; // 银焰边缘连续卷动。
	float blade_width = (0.012 + 0.060 * closing) * taper; // 黑裂口先打开再闭合。
	float distance_to_edge = abs(point.x - curl) - blade_width; // 黑核表面有符号距离。
	float length_mask = 1.0 - smoothstep(reach * 0.92, reach, abs(point.y)); // 长轴末端柔化。
	float void_mask = (1.0 - smoothstep(-0.006, 0.006, distance_to_edge)) * length_mask; // 深色裂口主体。
	float silver = exp(-pow(distance_to_edge * 140.0, 2.0)) * length_mask; // 锐利银边。
	float plume = exp(-pow((distance_to_edge - 0.028 - curl) * 26.0, 2.0)) * length_mask; // 贴附刃口的冷焰。
	float tear = exp(-pow((point.x - point.y * 0.07) * 240.0, 2.0)) * length_mask * exp(-age * 18.0); // 出刀时的一线白光。
	vec4 result = vec4(0.0); // 透明预乘画布。
	result = over(result, vec3(0.14, 0.12, 0.30), plume * 0.48);
	result = over(result, vec3(0.43, 0.68, 0.80), plume * 0.26);
	result = over(result, vec3(0.008, 0.010, 0.023), void_mask * 0.96);
	result = over(result, vec3(0.87, 0.96, 1.0), silver * 0.94);
	result = over(result, vec3(1.0), tear);

	// 两道错开的弯月状震荡，从斩痕向两侧掠开，不绘制完整圆圈。
	float radius = length(point * vec2(1.0, 0.84)); // 略拉长的魂波半径。
	float angle = atan(point.y, point.x); // 波前的角向遮罩。
	float wave_reach = 0.12 + opening * 0.51 + time * 0.12; // 波前随时间外移。
	float arc_mask = pow(abs(sin(angle + 0.48)), 5.0); // 保留两个有方向的弧段。
	float wave = exp(-pow((radius - wave_reach) * 115.0, 2.0)) * arc_mask * exp(-age * 6.0); // 极细银波。
	float shadow_wave = exp(-pow((radius - wave_reach + 0.02) * 34.0, 2.0)) * arc_mask * exp(-age * 6.0); // 深色衬线提高草地可读性。
	result = over(result, vec3(0.035, 0.03, 0.09), shadow_wave * 0.65);
	result = over(result, vec3(0.73, 0.85, 1.0), wave * 0.88);

	// 少量灵魂残痕延迟出现，每片都顺着斩击方向拉长并逐渐消失。
	for (int index = 0; index < 10; index++) {
		if ((quality == 1 && index >= 7) || (quality >= 2 && index >= 4)) { break; }
		float number = float(index); // 确定性碎片编号。
		float direction = number * 2.39996323; // 黄金角分散光屑。
		float travel = (0.22 + fract(number * 0.618) * 0.55) * opening; // 各片离心距离。
		vec2 center = vec2(cos(direction), sin(direction)) * travel; // 当前碎片中心。
		center.x += time * 0.16;
		vec2 shard_point = point - center; // 当前像素相对碎片的位置。
		float sliver = exp(-pow(shard_point.x * 190.0, 2.0) - pow(shard_point.y * (38.0 + number * 2.0), 2.0)); // 丝状魂屑。
		float shard_fade = smoothstep(0.02, 0.12, age) * (1.0 - time) * fade; // 光屑晚于主斩痕出现。
		result = over(result, mix(vec3(0.43, 0.44, 0.69), vec3(0.89, 0.96, 1.0), fract(number * 0.37)), sliver * shard_fade);
	}
	float edge = 1.0 - smoothstep(0.91, 1.0, length(uv_point)); // 局部画布末端完全透明。
	COLOR = vec4(result.rgb / max(result.a, 0.0001), result.a * fade * edge * (execution ? 1.0 : 0.88)) * tint;
}
