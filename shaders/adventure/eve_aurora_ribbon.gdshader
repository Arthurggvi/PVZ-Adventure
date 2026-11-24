shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float path_units = 1.0; // 完整弧长，以格宽为单位。
uniform float head_u = 0.0; // 针尖所在的归一弧长。
uniform float tail_u = 0.0; // 尾端所在的归一弧长。
uniform float fold_phase = 0.0; // 每发固定的折面初相。
uniform float flow = 0.0; // 着色流动的累积相位，触地后停住。
uniform float collapse = 0.0; // 触地点吸收最后一截极光的短暂相位。
// 移动平台只牵引目标端，飞出的针尖与薄带使用同一段位移。
uniform vec2 landing_offset = vec2(0.0);
uniform vec4 jade_tint : source_color = vec4(0.15, 0.98, 0.64, 1.0); // 正面的薄荷基色及透明度。
uniform vec4 return_violet_tint : source_color = vec4(0.41, 0.24, 0.91, 1.0); // 反面的紫色基色及透明度。

void vertex() {
	VERTEX += landing_offset * UV.x;
}

// 用带符号的线距、笔画半宽和子像素过渡宽度求亮纹覆盖。
float stroke(float distance_to_line, float radius, float aa) {
	return 1.0 - smoothstep(max(0.0, radius - aa), radius + aa, abs(distance_to_line));
}

void fragment() {
	// 原始弧长保持编织相位；裁掉两端前先求抗锯齿宽度。
	float s = UV.x * path_units; // 从发射点起的累计弧长。
	float behind = (head_u - UV.x) * path_units; // 当前片元离针尖的距离。
	float from_tail = (UV.x - tail_u) * path_units; // 当前片元离可见尾端的距离。
	float y = UV.y * 2.0 - 1.0; // 横跨薄带的对称坐标。
	float aa = clamp(fwidth(y) * 0.62, 0.012, 0.17); // 横向抗锯齿宽度。
	float aa_s = clamp(fwidth(s) * 0.62, 0.0005, 0.025); // 沿弧线方向的抗锯齿宽度。
	if (behind < 0.0 || from_tail <= 0.0) {
		discard;
	}
	float phase = s * 3.8 + fold_phase - flow; // 折纹沿未裁切的弧线展开。
	float twist = sin(phase); // 当前折面翻转量。
	float fan = smoothstep(0.02, 0.52, behind); // 从针尖向后展宽的权重。
	float tail_fade = smoothstep(0.0, 0.22, from_tail); // 尾梢逐渐透明。
	float center = fan * (0.10 * sin(phase + 0.8) + 0.055); // 薄带不对称的中心线。
	float width = mix(0.065, 0.64, fan) * (0.35 + 0.65 * abs(twist)); // 当前折面的投影半宽。
	width *= mix(0.38, 1.0, smoothstep(0.0, 0.30, from_tail));
	float r = (y - center) / max(width, 0.035); // 换算到当前投影半宽的横向位置。
	float aa_r = aa / max(width, 0.035); // 同一坐标系下的亮纹柔边。
	float silk_mask = stroke(y - center, width, aa); // 有色薄带的覆盖度。

	// 薄荷正面、青色掠光、紫色反面共用一条偏心的暗折痕。
	float fold = 0.19 + 0.34 * cos(phase + 0.40); // 正反面交界的横向坐标。
	float return_face = smoothstep(fold - aa_r, fold + aa_r, r); // 当前点可见反面的比例。
	float emerald = 1.0 - smoothstep(0.10, 0.92, abs(r + 0.35)); // 正面中心的薄荷色权重。
	vec3 front = mix(vec3(0.035, 0.61, 0.72), jade_tint.rgb, emerald); // 含渐层的正面色。
	float cyan_shoulder = stroke(r + 0.80, 0.12, aa_r); // 正面外侧的掠光覆盖度。
	front = mix(front, vec3(0.32, 0.98, 1.0), cyan_shoulder * 0.87);
	float magenta_lip = smoothstep(0.46, 0.93, r); // 反面外唇的偏紫比例。
	vec3 reverse = mix(return_violet_tint.rgb, vec3(0.84, 0.33, 0.94), magenta_lip); // 反面色。
	vec3 silk = mix(front, reverse, return_face); // 有色薄带的最终色，随后叠亮纹。
	silk = mix(silk, vec3(0.06, 0.21, 0.39), 0.80 * fan * stroke(r - fold, 0.065, aa_r));
	// 在能够分辨的宽折面上保留三到四道亮纹。
	float weave = (r + 1.0) * 1.78 + 0.105 * sin(r * 2.6 + phase * 0.68)
		+ 0.070 * sin(r * 4.1 - phase * 0.41); // 丝织亮纹的横向偏折相位。
	float resolved = (1.0 - smoothstep(0.15, 0.42, aa_r)) * fan; // 小于像素时抑制亮纹闪烁。
	float ridges = cos(weave * 6.283185) * resolved * (0.72 + 0.28 * cos(phase * 0.48 - r)); // 明暗丝纹。
	float far_end = (1.0 - smoothstep(0.12, 0.81, from_tail)) * fan; // 尾梢转向蓝紫的权重。
	silk = mix(silk, vec3(0.28, 0.47, 0.93), far_end * (0.06 + 0.22 * return_face));
	silk *= 1.0 + 0.075 * ridges;
	float near_tip = 1.0 - smoothstep(0.07, 0.42, behind); // 针尖附近的青白过渡。
	silk = mix(silk, vec3(0.49, 1.0, 0.86), 0.76 * near_tip);
	float silk_alpha = silk_mask * tail_fade * (0.85 + 0.08 * cyan_shoulder + 0.045 * ridges); // 合成之前的薄带透明度。
	silk_alpha *= (1.0 - 0.09 * return_face - far_end * (0.12 + 0.12 * return_face));
	silk_alpha *= mix(jade_tint.a, return_violet_tint.a, return_face);

	// 发丝状的银线沿侧缘分合，和主带保持可读间距。
	float strand_window = smoothstep(0.18, 0.46, behind) * smoothstep(0.03, 0.31, from_tail); // 银线只在带的中段游离。
	float gap = strand_window * (0.13 + 0.055 * (1.0 + cos(phase - 0.4))); // 银线与薄带外缘的空隙。
	float strand_y = center - width - gap; // 游离银线的横坐标。
	float strand = strand_window * stroke(y - strand_y, 0.044 * strand_window, aa); // 银线本身的覆盖度。
	vec3 thread = mix(vec3(0.29, 0.87, 1.0), vec3(0.68, 0.48, 1.0), 0.50 + 0.43 * twist); // 银线的青紫色。
	// 三处错开的反光随丝带移动，末段收拢时一起暗去。
	float shift = 0.055 * sin(fold_phase); // 每发亮点在弧长方向的错位。
	float beads = stroke(behind - 0.49 - shift, 0.009, aa_s)
		+ stroke(behind - 0.96 + shift, 0.005, aa_s)
		+ stroke(behind - 1.41 - shift, 0.012, aa_s); // 按弧长叠放的三处窄反光。
	float pearl = strand_window * min(beads, 1.0) * stroke(y - strand_y, 0.10, aa); // 收窄到银线附近的亮点。
	float thread_alpha = max(0.84 * strand, 0.94 * pearl); // 银线和反光共用的透明度。
	thread = mix(thread, vec3(0.75, 0.99, 0.90), pearl);

	// 银针下方的薄晕只在窄条网格中求值。
	float halo_x = (behind - 0.075) / 0.13; // 薄晕的纵向坐标。
	float halo_y = (y - center) / 0.59; // 薄晕的横向坐标。
	float halo = 0.34 * exp(-2.9 * (halo_x * halo_x + halo_y * halo_y)); // 紧贴针尖的柔光覆盖度。
	halo *= smoothstep(0.0, 0.040, behind) * tail_fade;
	float alpha = halo + silk_alpha * (1.0 - halo); // 叠合各层后的透明度。
	vec3 premul = vec3(0.25, 0.97, 0.82) * halo * (1.0 - silk_alpha) + silk * silk_alpha; // 预乘后合成小范围辉光。
	premul = premul * (1.0 - thread_alpha) + thread * thread_alpha;
	alpha += thread_alpha * (1.0 - alpha);
	float silver = sin(collapse * 3.141593) * (1.0 - smoothstep(0.03, 0.72, behind)); // 末段靠近落点时转成冰的银蓝高光。
	vec3 light = mix(premul / max(alpha, 0.0001), vec3(0.71, 0.95, 1.0), 0.56 * silver); // 尾光和星芒接成同一色调。
	COLOR = vec4(light * COLOR.rgb, alpha * COLOR.a * (1.0 - 0.45 * collapse));
}
