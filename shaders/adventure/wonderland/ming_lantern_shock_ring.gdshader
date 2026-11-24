// 明灯震颤的局部折射。读入技能层下方的景物，让水圈经过时实际扭动被它扫过的画面。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// 同一批水圈共享的技能层前景快照。
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
// 完整光圈的世界横纵半径，用于求椭圆的法线方向。
uniform vec2 half_extent = vec2(300.0, 220.0);
// 局部画布相对光圈最大半径的保留比例。
uniform float surface_margin = 1.28;
// 运行到当前帧的战斗秒数。
uniform float clock_seconds = 0.0;
// 与真实接触范围同步的归一化半径。
uniform float front_radius = 0.0;
// 达到最大半径之后水纹继续散开的比例。
uniform float fade_progress = 0.0;
// 主环和余波的强度，由表现节点调整。
uniform float intensity = 0.0;
// 按世界中心和是否为余波确定的细纹相位。
uniform float phase = 0.0;
// 折射带最强处的采样位移，单位为屏幕像素。
uniform float refraction_pixels = 7.4;

// 返回柔和的狭窄波带。[offset] 为到波带中心的距离，[width] 为扩散宽度。
float band(float offset, float width) {
	float normalized_offset = offset / width; // 轮廓过渡平滑，局部缩放时不会出现硬边。
	return exp2(-normalized_offset * normalized_offset);
}

void fragment() {
	vec2 point = (UV * 2.0 - 1.0) * surface_margin; // 光圈的归一化椭圆局部坐标。
	float radial = length(point); // 到起浪中心的归一化距离。
	float rebound = fade_progress * (0.125 - 0.067 * fade_progress); // 末端水纹减速外扩。
	if (intensity < 0.001 || abs(radial - front_radius - rebound) > 0.22) {
		discard;
	}
	float angle = atan(point.y, point.x + 0.00001); // 从中心沿周向定位水流的褶皱。
	float flow = phase + clock_seconds * 5.1; // 色带和细纹随本次传播时间移动。
	float split = smoothstep(0.59, 1.0, front_radius); // 宽光冠接近外缘后开始裂成细水纹。
	float fold = sin(angle * 7.0 + flow) + 0.47 * sin(angle * 13.0 - flow * 1.31 + 0.4); // 大涡与细涡不同步。
	float front = radial - front_radius - rebound + fold * (0.009 + 0.010 * front_radius); // 不规则但连贯的可见波前。
	float aa = clamp(fwidth(radial) * 0.65, 0.0025, 0.014); // 用实际像素密度保护远处细水纹的轮廓。
	float dissolve = 1.0 - smoothstep(0.08, 1.0, fade_progress); // 破碎后仍能看见细流逐渐隐入水色。
	float lobe = band(front + 0.028, 0.039) - band(front - 0.021, 0.047); // 折射两侧的位移方向相反，像水面翻起的薄膜。
	vec2 normal = normalize(point * vec2(half_extent.y, half_extent.x) + vec2(0.00001, 0.0)); // 椭圆在屏幕里的外法线。
	vec2 tangent = vec2(-normal.y, normal.x); // 少量侧向流动让格线短暂错位。
	float lens = band(front - 0.005, 0.071) * (1.0 - split * 0.62) * (1.0 - smoothstep(0.0, 0.76, fade_progress)); // 只保留一条窄折射带。
	vec2 offset = (normal * lobe + tangent * fold * 0.12) * refraction_pixels * intensity * SCREEN_PIXEL_SIZE; // 水面沿波前推开，在其后略往回卷。
	float lens_alpha = lens * intensity * 0.63; // 圈外原画完整透过，交叠的两道波也能各自显形。
	vec3 under = textureLod(scene_color, clamp(SCREEN_UV + offset, vec2(0.0), vec2(1.0)), 0.0).rgb; // 读取这一帧已绘制的背景与植物。
	float wavelets = 0.64 + 0.36 * sin(angle * 10.0 + flow + 0.65 * sin(angle * 3.0 - flow * 0.8)); // 周向亮度连续变化，避免均匀描边。
	float crest = band(front, 0.008 + aa) * (0.69 + 0.31 * wavelets)
		* (1.0 - split * 0.83) * (1.0 - smoothstep(0.0, 0.36, fade_progress)); // 白冠散去后将余光留给分流的细纹。
	float shoulder = band(front + 0.034, 0.026 + aa) * (0.35 + wavelets * 0.35) * (1.0 - split * 0.65); // 白冠后面较暗的薄水肩。
	float spread = split * (1.0 + fade_progress * 0.39); // 外沿细纹间距随水面回落而拉大。
	float outer = band(front - 0.030 * spread - 0.007 * sin(angle * 17.0 + flow), 0.0045 + aa); // 外层细纹从主波前向外偏移。
	float middle = band(front + 0.023 * spread + 0.007 * sin(angle * 14.0 - flow * 1.2), 0.0037 + aa); // 中层较窄，保持独立流向。
	float inner = band(front + 0.062 * spread + 0.009 * sin(angle * 19.0 + flow * 0.9), 0.004 + aa); // 后沿细纹比外层更早退亮。
	float fray = smoothstep(0.04, 0.67, fade_progress); // 淡出的三层细纹逐渐断成不等长的水面弧段。
	float outer_mask = mix(1.0, smoothstep(-0.30, 0.38, sin(angle * 9.0 + flow + 0.51 * sin(angle * 4.0))), fray); // 外层缺口随水流缓缓偏摆。
	float middle_mask = mix(1.0, smoothstep(-0.36, 0.47, cos(angle * 7.0 - flow * 0.79 + 0.71 * sin(angle * 5.0))), fray); // 中层从不同位置消散。
	float inner_mask = mix(1.0, smoothstep(-0.19, 0.46, sin(angle * 11.0 + flow * 1.23)), fray); // 最里层留下更短的碎纹。
	float ribbons = split * (outer * outer_mask * 0.43 * (0.26 + 0.74 * wavelets)
		+ middle * middle_mask * 0.32 * (1.0 - wavelets * 0.52) + inner * inner_mask * 0.25 * wavelets * dissolve); // 以透明度融掉弧段两端。
	float foam_alpha = clamp((crest * 0.91 + ribbons + shoulder * 0.34) * dissolve * intensity, 0.0, 0.96); // 白冠、细纹和水雾的合成可见度。
	vec3 foam = mix(vec3(0.41, 0.73, 0.83), vec3(0.92, 0.98, 1.0), clamp(crest + ribbons * 0.63, 0.0, 1.0)); // 从冷白冠过渡到薄青水光。
	COLOR = vec4(mix(under * lens_alpha, foam, foam_alpha), lens_alpha * (1.0 - foam_alpha) + foam_alpha);
}
