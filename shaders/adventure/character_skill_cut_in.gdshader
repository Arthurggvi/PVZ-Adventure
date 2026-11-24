shader_type canvas_item;
render_mode unshaded;

// 主题色来自单个技能，幕布只在演出期间绘制。
uniform vec4 accent : source_color = vec4(0.3, 0.77, 1.0, 1.0);
// 以倾斜的横坐标为准，左边界划入，右边界划出。
uniform float leading_edge = 1.36;
uniform float trailing_edge = 1.36;
// 场景压暗幅度和速度线的累计位移。
uniform float dim = 0.0;
uniform float travel = 0.0;
// 仅使用刀口退场的技能在收幕时从零推进到一。
uniform float blade_exit = 0.0;

// [row] 为线条编号，反复使用同样的行布局，避免闪烁。
float variation(float row) {
	return fract(fract(row * 0.1031) * (35.32 + row));
}

// [p] 为斜幕坐标，[count] 为行数，[shift] 为有方向的位移，[seed] 区分前后线层。
float streaks(vec2 p, float count, float shift, float seed) {
	float lane = p.y * count; // 把纵向坐标分成稳定的线道。
	float row = floor(lane) + seed; // 每条线的长度和起点各有变化。
	float key = variation(row); // 长度、宽度与亮度共用的随机系数。
	float length_limit = mix(0.12, 0.51, key * key); // 一个横向周期中有线条的占比。
	float along = fract(p.x * (1.2 + key * 0.7) + shift + variation(row + 17.0)); // 循环移动的齿锋位置。
	float tail = smoothstep(0.01, length_limit * 0.82, along); // 尾迹逐段变亮。
	float tip = 1.0 - smoothstep(length_limit * 0.84, length_limit, along); // 锐利线头留小段抗锯齿。
	float width = mix(0.08, 0.19, key) * (0.4 + 0.6 * tail); // 尾端比线头细。
	float line = 1.0 - smoothstep(width, width + fwidth(lane), abs(fract(lane) - 0.5)); // 保留小视口下的细线。
	return line * tail * tip * mix(0.3, 1.0, key);
}

void fragment() {
	vec2 p = vec2(UV.x, UV.y + (UV.x - 0.5) * 0.108); // 全部条纹共用向右上抬起的斜率。
	float crossband = abs(p.y - 0.5); // 到斜幕中心的距离。
	float sweep = UV.x + (UV.y - 0.5) * 0.77; // 过渡切口独立于横幕斜率。
	float open = smoothstep(leading_edge - 0.007, leading_edge + 0.007, sweep); // 左侧切入边界。
	float close = 1.0 - smoothstep(trailing_edge - 0.007, trailing_edge + 0.007, sweep); // 右侧退场边界。
	float reveal = open * close; // 只有两条切线之间存在斜幕。
	float body = 1.0 - smoothstep(0.214, 0.222, crossband); // 中部主幕的抗锯齿边缘。
	float edge = (1.0 - smoothstep(0.001, 0.004, abs(crossband - 0.220))) * 0.95; // 主边线。
	float edge_echo = (1.0 - smoothstep(0.001, 0.003, abs(crossband - 0.235))) * 0.50; // 外侧细边线。
	float beam = (1.0 - smoothstep(0.0, 0.58, abs(p.x - 0.76))) * (1.0 - crossband * 2.0); // 立绘背后的亮区。
	float glass = (1.0 - smoothstep(0.18, 0.54, fract(p.x * 1.7 + p.y * 0.66))) * 0.14; // 背景大块斜切面的亮度。
	float outer = smoothstep(0.025, 0.20, crossband); // 速度线向边缘聚集，标题附近保持清楚。
	float faint = streaks(p, 91.0, travel * 0.61, 11.0) * (0.12 + outer * 0.34); // 慢层细线。
	float fast = streaks(p, 54.0, travel, 57.0) * (0.12 + outer * 0.83); // 快层长线。
	float blade_distance = min(abs(sweep - leading_edge), abs(sweep - trailing_edge)); // 离最近的擦幕边缘的距离。
	float blade = (1.0 - smoothstep(0.003, 0.042, blade_distance)) * (1.0 - smoothstep(0.20, 0.29, crossband)); // 切口短辉光。
	float band_alpha = max(body * 0.97, max(edge, edge_echo)) * reveal; // 合并主幕与两条边线。
	float speed_alpha = max(fast, faint) * reveal * (1.0 - smoothstep(0.217, 0.30, crossband)); // 少量速度线滑出主幕。
	float overlay = max(band_alpha, max(speed_alpha, blade * 0.75)); // 一次混合绘制整个演出背景。
	vec3 dark = vec3(0.018, 0.034, 0.077); // 过渡时保留可见的战场明暗。
	vec3 panel = mix(dark, accent.rgb * vec3(0.40, 0.53, 0.72), 0.17 + beam * 0.61 + glass); // 人物侧更亮。
	vec3 ice = mix(accent.rgb, vec3(0.88, 0.98, 1.0), 0.62); // 边线和快线的冷色高光。
	vec3 light = max(panel, ice * max(speed_alpha * 0.86, max((edge + edge_echo) * reveal, blade))); // 各线层的合成颜色。
	float intact = 1.0; // 未使用刀口退场时保持正常幕布。
	if (blade_exit > 0.0) {
		float split_distance = abs(UV.y - 0.50 + (UV.x - 0.53) * 0.72); // 贯穿整个幕布的斜刀口。
		float split_edge = blade_exit * 0.91; // 刀口张开后，上下幕分向屏幕两侧。
		float split_fade = smoothstep(0.0, 0.07, blade_exit); // 让刀口从完整幕布自然展开。
		intact = mix(1.0, smoothstep(split_edge, split_edge + 0.010, split_distance), split_fade);
		float rim = (1.0 - smoothstep(0.001, 0.025, abs(split_distance - split_edge))) * split_fade; // 只在切边留下狭窄的紫光。
		rim *= (1.0 - smoothstep(0.12, 0.62, blade_exit)) * (1.0 - smoothstep(0.20, 0.31, crossband));
		overlay = max(overlay * intact, rim * 0.83);
		light = max(light, mix(accent.rgb, vec3(1.0, 0.87, 1.0), 0.60) * rim);
	}
	float opacity = overlay + dim * intact * (1.0 - overlay); // 刀口经过的位置优先露出战场。
	COLOR = vec4(mix(dark, light, overlay / max(opacity, 0.001)), opacity);
}
