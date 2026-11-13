// 晨星的五向超新星与地狱的熔火撕裂：一张局部画布，不生成粒子节点。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 由可暂停的节点生命周期传入秒数，禁止使用全局 TIME。
uniform float age = 0.0;
// 地狱改用红金熔火色与向内回收的锋芒。
uniform bool infernal = false;
// 辉夜采用冷银星爆，颜色与银河场统一。
uniform bool lunar = false;
// 分裂星仅显示短促小爆发，降低密集二代星的亮度。
uniform bool daughter = false;
// 原生命中来向，旋转主星芒但不影响战斗。
uniform float heading = 0.0;
// 局部种子打散碎光，不消耗战斗随机序列。
uniform float seed_phase = 0.0;
// 预算降低时只减少次级碎光。
uniform int quality = 0;
// 宿主透明度必须参与最终输出。
varying vec4 host_tint;

void vertex() {
	host_tint = COLOR;
}

// 点到有限线段的距离；退化线段仍给出有限值。
float segment_distance(vec2 point, vec2 from, vec2 to) {
	vec2 span = to - from; // 当前有限光丝的方向与长度。
	float along = clamp(dot(point - from, span) / max(dot(span, span), 0.00001), 0.0, 1.0); // 像素在线段上的投影，端点外侧钳制。
	return length(point - from - span * along);
}

// 锋利四芒高光，较粗的暗底由调用方添加以适配明亮草地。
float glint(vec2 point, float size) {
	vec2 axis = abs(point) / max(size, 0.0001); // 以星芒半径归一化的局部坐标。
	float diamond = pow(max(0.0, 1.0 - pow(axis.x, 0.52) - pow(axis.y, 0.52)), 1.3); // 内凹四芒形状，中心亮、末端尖细。
	return diamond;
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * 2.0; // 以命中点为中心的局部画布坐标。
	float radius = length(point); // 到命中中心的归一化距离。
	float time = clamp(age / 0.64, 0.0, 1.0); // 完整零点六四秒生命周期的比例。
	float end_fade = 1.0 - smoothstep(0.65, 1.0, time); // 尾段统一淡出权重。
	float blast = 1.0 - pow(1.0 - clamp(age / 0.26, 0.0, 1.0), 3.0); // 快速扩张后减速的冲击进度。
	float flash = exp(-age * 24.0); // 极短的初始光量，避免持续白屏。
	vec3 cold = infernal ? vec3(0.47, 0.035, 0.11) : vec3(0.29, 0.18, 0.75); // 主光外围用于草地对比的暗色。
	vec3 middle = infernal ? vec3(1.0, 0.26, 0.035) : vec3(0.28, 0.70, 1.0); // 爆发的中间色温。
	vec3 hot = infernal ? vec3(1.0, 0.80, 0.30) : vec3(1.0, 0.88, 0.56); // 主射流的亮色。
	vec3 ivory = vec3(1.0, 0.97, 0.83); // 只在小星核使用的近白高光。
	if (lunar) {
		cold = vec3(0.16, 0.075, 0.45);
		middle = vec3(0.36, 0.40, 1.0);
		hot = vec3(0.48, 0.88, 1.0);
		ivory = vec3(0.91, 0.97, 1.0);
	}
	float halo = exp(-radius * radius * 16.0) * flash; // 只覆盖命中附近的衰减柔光。
	vec3 emission = middle * halo * 0.24; // 当前像素累计的有色亮度。
	float cover = halo * 0.28; // 薄雾和光丝的最大覆盖率。
	float bright = 0.0; // 锐利星核与高光的最大透明度。
	float contour = 0.0; // 星芒暗衬边的透明度。

	// 第一拍是有色的短促冲击波；椭圆薄边迅速退出，不留下常驻光圈。
	float wave_radius = 0.12 + blast * 0.62; // 椭圆冲击波快速展开的半径。
	float wave_distance = abs(length(point * vec2(1.0, 1.30)) - wave_radius); // 当前像素到薄冲击边缘的距离。
	float wave = exp(-pow(wave_distance * 105.0, 2.0)) * exp(-age * 10.0); // 迅速退场的有色波前。
	emission += hot * wave * 0.72;
	cover = max(cover, wave * 0.80);

	// 五条主锋芒由金色头部向蓝紫尾部过渡，地狱则在后半程向裂隙收卷。
	for (int index = 0; index < 6; index++) { // 有界循环仅控制装饰数量。
		if (!lunar && index == 5) { break; }
		float angle = float(index) * (lunar ? 1.04719755 : 1.25663706) + heading - 1.57079633; // 当前碎光的圆周角度。
		vec2 direction = vec2(cos(angle), sin(angle)); // 主射流的单位方向。
		vec2 normal = vec2(-direction.y, direction.x); // 主射流的侧向偏移方向。
		float ray_length = (0.56 + 0.13 * sin(float(index) * 7.1 + seed_phase)) * blast; // 不同主射流具有不同最大长度。
		float retract = infernal ? 1.0 - smoothstep(0.24, 0.64, age) * 0.72 : 1.0; // 地狱后半程的向内回收比例。
		vec2 tip = direction * (0.10 + ray_length) * retract; // 主光丝的明亮前端位置。
		vec2 tail = direction * max(0.025, ray_length - 0.24) * retract; // 主光丝的冷色后端位置。
		vec2 bend = normal * sin(time * 3.14159265) * 0.09; // 尾端略弯，避免机械直线放射。
		float streak_distance = segment_distance(point, tail + bend, tip); // 当前像素到有限光丝的距离。
		float streak_fade = (1.0 - smoothstep(0.13, 0.51, age)) * smoothstep(0.0, 0.035, age); // 光丝晚于初闪出现，早于星尘退出。
		float streak = exp(-pow(streak_distance * 150.0, 2.0)) * streak_fade; // 锐利光丝主芯。
		float sleeve = exp(-pow(streak_distance * 40.0, 2.0)) * streak_fade * 0.35; // 包裹主芯的低透明度色光。
		float shard_size = (0.09 + 0.035 * sin(float(index) * 3.7)) * (1.0 - time * 0.72); // 逐渐收缩的主星芒半径。
		float shard = glint(point - tip, shard_size) * end_fade; // 主射流前端的锋利亮点。
		float shadow = glint(point - tip, shard_size * 1.55) * end_fade; // 亮点外一圈暗边，使草地上仍可识别。
		emission += middle * sleeve + hot * streak * 0.9 + ivory * shard;
		cover = max(cover, max(sleeve, streak * 0.95));
		bright = max(bright, shard);
		contour = max(contour, shadow * 0.72);
	}

	// 余辉阶段是离散星尘而非整片增白；预算只裁减装饰点。
	for (int index = 0; index < 12; index++) { // 有界循环仅控制装饰数量。
		if ((quality == 1 && index >= 8) || (quality >= 2 && index >= 4)) {
			break;
		}
		float number = float(index); // 确定性的装饰编号，不使用战斗随机数。
		float angle = number * 2.39996323 + seed_phase + time * (infernal ? -0.7 : 0.25); // 当前碎光的圆周角度。
		float reach = 0.20 + fract(sin(number * 17.17 + seed_phase) * 437.53) * 0.56; // 本粒星尘的目标半径。
		float travel = 1.0 - pow(1.0 - time, 2.4); // 星尘先快后慢的移动进度。
		float inward = infernal ? 1.0 - smoothstep(0.38, 1.0, time) * 0.75 : 1.0; // 地狱星尘在末段回卷向中心。
		vec2 position = vec2(cos(angle), sin(angle)) * reach * travel * inward; // 本粒星尘的当前局部位置。
		float twinkle = 0.50 + 0.50 * pow(sin(time * 8.0 + number * 1.9), 2.0); // 每粒错相的微光变化。
		float size = (0.025 + 0.025 * fract(number * 0.618)) * (1.0 - time * 0.70); // 本粒随时间缩小的尖光尺寸。
		float spark = glint(point - position, size) * twinkle * smoothstep(0.015, 0.10, age) * end_fade; // 离散小星芒的当前覆盖率。
		vec3 hue = mix(middle, hot, fract(number * 0.381)); // 相邻星尘在冷暖色之间错开。
		emission += hue * spark;
		bright = max(bright, spark);
	}

	// 初始核只在几像素内达到金白，横向镜芒比主体退场更快。
	float core = exp(-radius * radius * 1700.0) * exp(-age * 15.0); // 小范围金白核心，快速衰减。
	float cross_flare = glint(point * vec2(0.38, 1.0), 0.43) * flash; // 初闪中的短暂横向镜芒。
	emission += ivory * (core + cross_flare * 0.85);
	bright = max(bright, max(core, cross_flare));
	float energy = max(emission.r, max(emission.g, emission.b)); // 归一化颜色使用的最高通道亮度。
	vec3 color = mix(cold * 0.25, emission / max(energy, 0.0001), clamp(energy * 2.0, 0.0, 1.0)); // 保留暗边与饱和度的直通输出颜色。
	float alpha = max(max(cover, bright), contour) * end_fade; // 最终局部透明度，不覆盖整片画布。
	alpha *= daughter ? 0.72 : 1.0;
	alpha *= 1.0 - smoothstep(0.90, 1.0, radius);
	COLOR = vec4(color, clamp(alpha, 0.0, 0.97)) * host_tint;
}
