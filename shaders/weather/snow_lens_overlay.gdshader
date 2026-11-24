// 单次视口混合，弱冷色持续，局部风带和冰粒只在阵风期间出现。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 等比换算为参考像素的视口尺寸，纵向恒为 600，横向随实际长宽比。
uniform vec2 reference_size;
// 相位由暂停感知的场景控制器在两轴各 4096 参考像素内推进。
uniform vec2 travel;
// 同一世界风驱动的屏幕运动方向，包含镜头雪自身的轻落速。
uniform vec2 wind_axis = vec2(-0.94, 0.34);
// 阵风冲击包络，从 0 到 1。各处实际透明度另行限制。
uniform float lens_whiteout = 0.0;
// 淡色基线与 HUD 合成上限，由关卡预设传入。
uniform float frost_alpha = 0.0;
uniform float hud_cap = 0.09;
// 冷白融合色。钢灰偏移只用于掠过的雪雾。
uniform vec4 lens_tint : source_color = vec4(0.863, 0.902, 0.918, 1.0);
// 低档仍有主风带和冰粒，高档补第二股断续雪流。
uniform bool fine_detail = false;
// 大波与末波红字显示时仅保留很淡的冷色。
uniform bool warning_visible = false;

// [cell] 是整数格坐标；[period] 将格索引与 CPU 位移回绕对齐。
vec2 lens_hash(vec2 cell, vec2 period) {
	vec2 wrapped = mod(cell, period); // 相位两端共享同一格和种子。
	vec3 p = fract(vec3(wrapped.x, wrapped.y, wrapped.x) * vec3(0.1031, 0.11369, 0.13787)); // 两个分量共享廉价格散列。
	p += vec3(dot(p, p.yzx + vec3(17.17)));
	return fract((p.xx + p.yz) * p.zy);
}

// 按 [travelled] 的参考像素坐标返回温和起伏的雪流密度。
float plume_noise(vec2 travelled) {
	vec2 lattice = travelled / vec2(256.0, 64.0); // 横向较长，让稀疏孔口随风掠过。
	vec2 cell = floor(lattice); // 低频噪声单元。
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(lattice)); // 平滑邻格连接。
	vec2 period = vec2(16.0, 64.0); // 始终对应两轴各 4096 参考像素。
	float a = mix(lens_hash(cell, period).x, lens_hash(cell + vec2(1.0, 0.0), period).x, blend.x); // 上边。
	float b = mix(lens_hash(cell + vec2(0.0, 1.0), period).x, lens_hash(cell + vec2(1.0), period).x, blend.x); // 下边。
	return mix(a, b, blend.y);
}

// 利用 [travelled] 和 [stride] 生成短椭圆冰粒。[radius] 为参考像素半径。
float ice_flecks(vec2 travelled, float stride, float radius) {
	vec2 lattice = travelled / stride; // 每个格最多一粒，保证负载固定。
	vec2 rnd = lens_hash(floor(lattice), vec2(4096.0 / stride)); // 每格固定位置。
	vec2 offset = (fract(lattice) - mix(vec2(0.25), vec2(0.75), rnd)) * stride; // 椭圆不会跨格而被裁断。
	float crosswind = dot(offset, vec2(-wind_axis.y, wind_axis.x)); // 垂直于风的短轴。
	float alongwind = dot(offset, wind_axis) * mix(0.43, 0.58, rnd.x); // 沿风的短拖尾。
	float mark = 1.0 - smoothstep(radius * 0.32, radius, length(vec2(crosswind, alongwind))); // 雪粒柔边。
	return mark * smoothstep(0.37, 0.57, rnd.y);
}

void fragment() {
	vec2 uv = UV; // 独立于战场及镜头移动的可见视口。
	float top_hud = 1.0 - smoothstep(0.17, 0.255, uv.y); // 卡槽、头像、阳光和菜单。
	float skill_hud = (1.0 - smoothstep(0.14, 0.20, uv.x)) * (1.0 - smoothstep(0.215, 0.30, uv.y)); // 左上头像下方的技能数字。
	float bottom_hud = smoothstep(0.88, 0.94, uv.y); // 冷白集中在波次与底部提示条，避免染重第六行。
	float side = 1.0 - smoothstep(0.08, 0.30, min(uv.x, 1.0 - uv.x)); // 两侧有较强风带，中央战斗区减弱。
	float lower_guard = mix(1.0, 0.24, smoothstep(0.44, 0.84, uv.y)); // 坡面底行得到渐进保护。
	float readout_guard = max(max(top_hud, skill_hud), bottom_hud); // 所有普通 HUD 都受合成上限保护。
	float base = frost_alpha * mix(0.37, 1.0, readout_guard); // 卡槽、头像和波次更冷，中央仍用淡色。
	float storm_alpha = 0.0; // 无冲击或红字出现时使用无需噪声的普通混合。
	float grain = 0.0; // 细粒的亮色权重。
	if (lens_whiteout > 0.002 && !warning_visible) {
		vec2 travelled = uv * reference_size - travel; // 共享位移的视口参照像素。
		float density = plume_noise(travelled); // 风流有低频孔隙。
		float fold = (density - 0.5) * 0.30; // 雪流随漂移弯折，峰前保留开口。
		float lean = (uv.x - 0.5) * wind_axis.x * wind_axis.y * 0.16; // 斜率随风向变化。
		float ribbon = 1.0 - smoothstep(0.018, 0.195, abs(uv.y - 0.205 - fold - lean)); // 冲向顶部 HUD 的主风带。
		float holes = smoothstep(0.22, 0.78, density); // 只出现局部乳白。
		float veil = ribbon * holes; // 主风流由低档保留。
		grain = ice_flecks(travelled, 64.0, 2.02) * mix(0.35, 1.0, ribbon); // 近处冰粒柔和。
		if (fine_detail) {
			float other_density = plume_noise(travelled + vec2(384.0, 112.0)); // 增加有空间错位的第二股破碎流。
			float second = 1.0 - smoothstep(0.025, 0.166, abs(uv.y - 0.44 + fold * 0.65 - lean)); // 副带偏下但仍受底行遮罩。
			veil += second * smoothstep(0.35, 0.82, other_density) * 0.58;
			grain += ice_flecks(travelled + vec2(23.0, 48.0), 128.0, 3.08) * 0.70;
		}
		float soft_edge = smoothstep(0.0, 0.028, uv.y) * (1.0 - smoothstep(0.93, 1.0, uv.y)); // 上下收边。
		storm_alpha = lens_whiteout * (veil * 0.172 + grain * 0.108) * lower_guard * soft_edge
			* mix(0.43, 1.0, side) * mix(1.0, 0.53, readout_guard);
	}
	float cap = mix(mix(0.102, 0.19, side), hud_cap, readout_guard); // 中央约十分之一，HUD 不超过资源上限。
	if (warning_visible) {
		base *= 0.28;
	}
	float opacity = min(base + storm_alpha, cap); // 所有分量在一次混合中合成。
	vec3 blowing_snow = mix(lens_tint.rgb * vec3(0.84, 0.89, 0.93), min(vec3(1.0), lens_tint.rgb * 1.05), clamp(grain, 0.0, 1.0)); // 冷钢雾与少量冰白。
	vec3 color = mix(lens_tint.rgb, blowing_snow, storm_alpha / max(base + storm_alpha, 0.001)); // 以各自强度混合底色与雪。
	COLOR = vec4(color, opacity);
}
