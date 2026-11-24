// 灯条在水下引爆，体积散射在一个局部透明矩形内合成。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// 归一化的包围盒余量，覆盖软边附近的浮点舍入。
const float BOUNDS_MARGIN = 0.001;

// 战斗秒数，暂停时由调用方保持。
uniform float age = 0.0;
// 本次爆炸的噪声相位，由格中心确定。
uniform float pattern_seed = 1.0;
// 白热爆心，入树时达到峰值。
uniform float flash = 1.0;
// 与场景亮圈共用的波前半径，以攻击半宽为单位。
uniform float pressure_radius = 0.08;
// 压力波散射强度，扩开后衰减。
uniform float pressure = 0.0;
// 爆后余雾的可见度。
uniform float haze = 0.0;
// 与余雾照明共用的上浮位置，以攻击半宽高为单位。
uniform vec2 haze_center = vec2(0.0);
// 保留上级演出节点的颜色调制。
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// 从格点 [p] 提取零到一的固定随机数，避免纹理读取。
float cell_hash(vec2 p) {
	vec2 scrambled = fract(p * vec2(123.34, 456.21)); // 打乱两轴从整数格点得到的分布。
	scrambled += dot(scrambled, scrambled + 45.32);
	return fract(scrambled.x * scrambled.y);
}

// 返回 [p] 处跨格连续的值噪声，供波面与雾团弯折。
float current_noise(vec2 p) {
	vec2 cell = floor(p); // 四邻域中的左上格点。
	vec2 fraction = fract(p); // 格内位置。
	vec2 ease = fraction * fraction * (3.0 - 2.0 * fraction); // 格界处平滑过渡。
	return mix(mix(cell_hash(cell), cell_hash(cell + vec2(1.0, 0.0)), ease.x),
		mix(cell_hash(cell + vec2(0.0, 1.0)), cell_hash(cell + vec2(1.0)), ease.x), ease.y);
}

// 用 [color] 和 [opacity] 将一层透明介质合到预乘背景 [under] 上。
vec4 over(vec4 under, vec3 color, float opacity) {
	float alpha = clamp(opacity, 0.0, 1.0); // 保证各层透明度可单独调节。
	return vec4(color * alpha, alpha) + under * (1.0 - alpha);
}

// [point] 是攻击半宽高归一化后的像素位置；返回随流体浮升的散射和发光。
vec4 rising_haze(vec2 point) {
	vec2 local = point - haze_center; // 雾带与地面爆心逐渐分离。
	float spread = 1.0 - exp(-age * 2.15); // 扩散先快后慢。
	vec2 span = vec2(0.40 + spread * 0.83, 0.31 + spread * 0.40); // 左右扩开的雾身半轴。
	vec2 trail_span = span * vec2(0.78, 0.87); // 雾羽的软包络半轴。
	vec2 trail_offset = vec2(0.0, 0.34 + spread * 0.21); // 雾羽随扩散从雾身上方分离。
	float bend_range = 0.11 + spread * 0.12; // 雾羽横向卷曲的最大偏移。
	const vec2 eddy_scale = vec2(0.34, 0.29); // 将归零中心的噪声映射为雾团形变。
	const float body_edge = 0.99; // 雾身软包络完全透明时的归一化距离。
	vec2 eddy_limit = eddy_scale * 0.5 + vec2(BOUNDS_MARGIN); // 两层噪声的形变绝对值上界。
	vec2 body_limit = span * body_edge + eddy_limit; // 雾身最外缘，含噪声扰动。
	vec2 trail_limit = trail_span + eddy_limit + vec2(bend_range, 0.0); // 雾羽最外缘，含横向卷流。
	if (any(greaterThan(abs(local), body_limit)) && any(greaterThan(abs(local + trail_offset), trail_limit))) {
		return vec4(0.0);
	}
	vec2 flow = local * vec2(3.25, 4.80) + vec2(pattern_seed, age * 0.90); // 由下而上的大尺度卷流。
	float broad = current_noise(flow); // 较厚的发光雾身。
	float thin = current_noise(flow * 2.07 + vec2(0.9, 5.2) + (broad - 0.5) * vec2(2.0, -2.8)); // 拉伸的细卷和孔洞。
	vec2 eddy = local + vec2(broad - 0.5, thin - 0.5) * eddy_scale; // 让雾团形状偏离规则椭圆。
	float body = 1.0 - smoothstep(0.19, body_edge, length(eddy / span)); // 近处浓雾的软包络。
	float bend = sin(local.y * 3.6 + pattern_seed) * bend_range; // 薄雾随升流向侧方翻卷。
	vec2 trail = eddy + vec2(bend, trail_offset.y); // 先被卷起的雾沿上缘分离。
	float loose = 1.0 - smoothstep(0.10, 1.0, length(trail / trail_span)); // 上部疏松的雾羽。
	float density = smoothstep(0.23, 0.78, broad * 0.54 + thin * 0.46); // 厚薄间可以看见战场。
	float sides = smoothstep(0.24, 0.68, thin + broad * 0.16); // 照亮卷流时断时续的表层。
	float cold = (body * (0.21 + 0.55 * density) + loose * density * 0.37) * haze; // 蓝色体积与较轻的漂雾。
	float lit = max(body, loose * 0.52) * density * sides * haze; // 不规则亮脉跟随雾体淡出。
	vec3 blue = mix(vec3(0.035, 0.27, 0.65), vec3(0.15, 0.65, 0.96), density); // 密集区域由湛蓝转向水青。
	vec4 result = over(vec4(0.0), blue, cold * 0.72); // 薄蓝雾底层。
	return over(result, vec3(0.49, 0.91, 1.0), lit * 0.61);
}

// 在归一化半径 [radius] 与方向 [direction] 上绘制弯折的压力前沿，并将它叠到 [under] 上。
vec4 pressure_front(vec4 under, float radius, vec2 direction) {
	float swell = current_noise(direction * 4.1 + vec2(pattern_seed, -age * 0.69)); // 周向无缝的大波节。
	float folds = current_noise(direction * 11.4 + vec2(pattern_seed * 0.71, age * 2.2 + radius * 4.3)); // 前沿上的小尺度破碎水纹。
	float distortion = (swell - 0.5) * 0.135 + (folds - 0.5) * 0.054; // 不同方位有不同传播速度。
	float front = radius - pressure_radius - distortion * min(pressure_radius * 2.4, 1.0); // 到冲击前沿的带符号距离。
	float shoulder = 1.0 - smoothstep(0.014, 0.125, abs(front + 0.015)); // 厚蓝压力带和白边之间有缓冲层。
	float crest = 1.0 - smoothstep(0.003, 0.018 + folds * 0.025, abs(front)); // 狭窄亮边保留局部厚薄。
	float backscatter = 1.0 - smoothstep(0.006, 0.037, abs(front + 0.076 + swell * 0.043)); // 湍流内侧的短片回光。
	float breaks = smoothstep(0.24, 0.78, swell * 0.58 + folds * 0.42); // 亮白边破成不等长的段。
	vec4 result = over(under, vec3(0.06, 0.48, 0.88), shoulder * pressure * (0.34 + folds * 0.26)); // 透明宽带产生厚度。
	result = over(result, vec3(0.33, 0.84, 1.0), backscatter * pressure * folds * 0.58);
	return over(result, vec3(0.79, 0.98, 1.0), crest * pressure * (0.22 + 0.77 * breaks));
}

// 将 [point] 处迅速膨开的爆心和短促散射叠到 [under] 上。
vec4 hot_core(vec4 under, vec2 point) {
	vec2 p = (point + vec2(0.0, 0.025)) / vec2(1.0, 0.85); // 爆心和压力波共享水面透视。
	float r = length(p); // 与爆心的透视距离。
	vec2 heading = p / max(r, 0.003); // 无极角接缝的径向采样方向。
	float beam = current_noise(heading * 8.1 + vec2(pattern_seed, r * 3.9 + age * 4.5)); // 不规则的短扩散亮舌。
	float spread = 1.0 - exp(-age * 14.0); // 白热介质迅速打开，随后退亮。
	float size = 0.103 + spread * 0.31; // 最亮部分始终留在压力圈内部。
	float hot = 1.0 - smoothstep(size * 0.17, size * (0.48 + beam * 0.77), r); // 白热爆心随水涡形成参差的轮廓。
	float scatter = 1.0 - smoothstep(size * 0.15, size * (1.63 + beam * 0.63) + 0.16, r); // 比白心更宽的青蓝辉光。
	vec4 result = over(under, vec3(0.20, 0.81, 1.0), scatter * flash * (0.30 + 0.40 * beam)); // 周围水体中的瞬时散射。
	return over(result, vec3(0.91, 1.0, 1.0), hot * flash);
}

void fragment() {
	vec2 field = UV * vec2(3.08, 3.02) - vec2(1.54, 1.74); // 与脚本的局部矩形共用归一化坐标。
	vec4 result = vec4(0.0); // 由远处的雾到近处的亮圈和爆心逐层合成。
	if (haze > 0.002) {
		result = rising_haze(field);
	}
	if (pressure > 0.002 || flash > 0.002) {
		vec2 wave = field / vec2(1.0, 0.85); // 压力波在纵向略压缩，对应战场的透视。
		float radius = length(wave); // 只在压力波或爆心可见时计算透视半径。
		if (pressure > 0.002 && abs(radius - pressure_radius) < 0.24) {
			result = pressure_front(result, radius, wave / max(radius, 0.003));
		}
		if (flash > 0.002 && radius < 1.22) {
			result = hot_core(result, field);
		}
	}
	vec2 trim = min(UV, 1.0 - UV); // 画布边缘的短淡出，仅避免大涡被矩形截断。
	float edge = smoothstep(0.0, 0.055, min(trim.x, trim.y)); // 涨落过程始终保留全透明外缘。
	COLOR = result * vec4(tint.rgb * tint.a, tint.a) * edge;
}
