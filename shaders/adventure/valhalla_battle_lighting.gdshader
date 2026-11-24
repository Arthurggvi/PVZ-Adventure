shader_type canvas_item;
render_mode unshaded;

// 控件逻辑尺寸，把原图集 UV 与本面板的动画坐标分开。
uniform vec2 extent = vec2(400.0, 244.0);
// 方形技能按钮与横幅的宝石位置不同。
uniform bool compact = false;
// 内景仅绘制柔和的光束和浮尘，边框使用金属与宝石材质。
uniform bool hall_interior = false;
// 技能剩余充能比例，0 为刚施放，1 为完全就绪。
uniform float charge : hint_range(0.0, 1.0) = 1.0;
// 悬停或键盘聚焦的淡入强度。
uniform float attention : hint_range(0.0, 1.0) = 0.0;
// 施放和冷却完成时从 1 衰减到 0 的沿框高光。
uniform float flare : hint_range(0.0, 1.0) = 0.0;

// 0–1 面板坐标、顶点着色及宿主渐显的透明度。
varying vec2 panel_uv;
varying vec4 tint;

void vertex() {
	panel_uv = VERTEX / extent;
	tint = COLOR;
}

// 计算 [p] 周围的四芒星与短晕，[aspect] 修正横幅中星芒的宽高比。
float jewel_glint(vec2 p, vec2 origin, float aspect, float radius) {
	vec2 d = abs(p - origin) * vec2(aspect, 1.0) / radius; // 按控件高度归一。
	float arms = exp(-11.0 * min(d.x, d.y) - 3.1 * max(d.x, d.y)); // 纵横光芒向尖端收窄。
	float glow = exp(-3.6 * dot(d, d)); // 短晕维持晶石表面的光感。
	return arms + 0.38 * glow;
}

// 让远处的圣窗缓慢换光，点亮摆动光束中的少量尘点。
vec3 hall_light(vec2 p) {
	vec2 ray = p - vec2(0.5, -0.14); // 光束汇聚点略高于画面上方。
	float angle = ray.x / ray.y; // 纵深展开给出自然的扇形。
	float drift = 0.09 * sin(TIME * 0.65); // 轻微摆动，主光仍来自窗上方。
	float shafts = pow(0.5 + 0.5 * cos(32.0 * (angle + drift)), 3.0); // 窄光束与背景暗部交错。
	float fade = exp(-5.2 * angle * angle) * (1.0 - smoothstep(0.05, 0.91, p.y)); // 光不盖住地面和铭牌。
	float breath = 0.68 + 0.32 * sin(TIME * 0.82); // 连续明暗变化，不叠加硬闪。
	float dust = 0.0; // 近处光点沿缓慢上升的路径移动。
	for (int i = 0; i < 6; i++) { // 固定粒子数，两个小面板即可绘制，无节点池。
		float seed = float(i) + 1.0; // 每粒尘光独立的速度、位置和明灭。
		float flight = fract(TIME * (0.075 + seed * 0.007) + seed * 0.3819); // 路径端点透明。
		vec2 point = vec2(0.16 + 0.68 * fract(seed * 0.618) + 0.022 * sin(TIME + seed), 0.84 - flight * 0.68); // 悬浮在立绘后的殿内。
		vec2 d = (p - point) * vec2(extent.x / extent.y, 1.0); // 点光保持圆形。
		dust += exp(-dot(d, d) * 15200.0) * pow(sin(flight * 3.14159), 2.0);
	}
	return vec3(1.0, 0.76, 0.40) * fade * (0.06 + 0.17 * shafts) * breath
		+ vec3(0.93, 0.89, 0.68) * dust * 0.66;
}

void fragment() {
	vec4 art = texture(TEXTURE, UV); // 先取原图透明度，宿主的渐显在最后乘上。
	vec2 p = panel_uv;
	art.a *= smoothstep(0.010, 0.041, art.a); // 去除极弱的透明区杂色并保留柔软抗锯齿边缘。
	if (hall_interior) {
		art.rgb += hall_light(p);
	} else {
		// 方框与横幅在原图集上相邻，两个矩形的交界需要去掉各自远离主体的尾角。
		float corner = compact
			? smoothstep(0.70, 0.77, p.x) * (1.0 - smoothstep(0.120, 0.145, p.y))
			: (1.0 - smoothstep(0.20, 0.23, p.x)) * smoothstep(0.940, 0.950, p.y);
		art.a *= 1.0 - corner;
		float aspect = extent.x / extent.y; // 光芒长宽按逻辑画布校正。
		float phase = fract(TIME / (compact ? 5.0 : 7.0) + (compact ? 0.40 : 0.10)); // 两个框交替反光。
		float travel = p.x + 0.30 * (p.y - 0.5) - mix(-0.25, 1.25, phase); // 从羽翼一侧扫到另一侧。
		float sheen = exp(-160.0 * travel * travel); // 两侧平滑收束的斜向反光。
		float gilded = smoothstep(0.04, 0.29, art.r - art.b) * smoothstep(0.27, 0.77, art.r); // 只提亮已有的金属部分。
		float pulse = pow(max(0.0, sin(TIME * 1.62 + (compact ? 1.4 : 0.0))), 7.0); // 晶石错峰闪烁。
		float crown = jewel_glint(p, vec2(0.500, compact ? 0.132 : 0.051), aspect, 0.077); // 上方金色圣印。
		float sapphire = jewel_glint(p, vec2(0.496, compact ? 0.882 : 0.916), aspect, 0.073); // 下方蓝宝石。
		float pillars = jewel_glint(p, vec2(compact ? 0.173 : 0.116, 0.530), aspect, 0.027)
			+ jewel_glint(p, vec2(compact ? 0.820 : 0.886, 0.530), aspect, 0.027); // 柱廊上的两颗小宝石。
		float wave = p.y - mix(0.12, 0.91, flare); // 就绪和施放时从蓝宝石向上扬起的反光。
		float ripple = exp(-125.0 * wave * wave) * sqrt(flare) * gilded;
		float gold_light = (sheen * (0.45 + 0.31 * attention) + 0.15 * attention) * gilded * (0.48 + 0.52 * charge); // 冷却时仍可识别金边。
		float star_light = 0.55 * crown * (0.33 + pulse) + 0.28 * pillars * (1.0 - pulse); // 暖光集中在首饰锚点。
		float blue_light = sapphire * (0.08 + 0.36 * charge * (0.46 + pulse) + 0.60 * flare); // 整理成可读的充能反馈。
		vec3 warm = vec3(1.0, 0.80, 0.44); // 香槟金延续原图的象牙色羽翼。
		vec3 cool = vec3(0.50, 0.80, 1.0); // 冷却和蓝宝石的冰蓝反光。
		art.rgb = mix(art.rgb * vec3(0.79, 0.88, 1.0), art.rgb, charge);
		art.rgb += warm * (gold_light + star_light) + cool * blue_light
			+ mix(cool, warm, charge) * ripple * 0.80;
		art.a = max(art.a, (star_light + blue_light) * 0.34); // 星芒只略微越过宝石外沿。
	}
	COLOR = vec4(art.rgb * tint.rgb, art.a * tint.a);
}
