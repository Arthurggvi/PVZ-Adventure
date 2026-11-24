shader_type canvas_item;
render_mode unshaded, blend_disabled;

// 精灵纹理提供可重新照明的正常材质，暗版提供替换结构和熄灭后的烛台。
uniform sampler2D dark_interior : source_color, filter_linear, repeat_disable;
uniform sampler2D lit_sky : source_color, filter_linear, repeat_disable;
// 熄灯量控制烛台和窗洞，不控制整张地图的可见性。
uniform float extinction : hint_range(0.0, 1.0) = 0.0;
// 结构范围使用原画像素，位掩码由光圈外的结构切换决定。
uniform vec4 structure_areas[6];
uniform int structure_mask = 0;
// 祭坛上方两侧的七组烛台在原图中的水平中心。
const float SCONCES[7] = { 351.0, 464.0, 581.0, 694.0, 1228.0, 1349.0, 1468.0 };

// 烛芯靠近椭圆内部，烛光的反射在外圈羽化到正常材质。
float candle_area(vec2 point, vec2 center, vec2 radius) {
	return 1.0 - smoothstep(0.60, 1.0, length((point - center) / radius));
}

float baked_candlelight(vec2 point) {
	float mask = 0.0; // 只在原画的灯具和近处反射内替换。
	if (point.y < 235.0) {
		for (int i = 0; i < 7; i++) {
			mask = max(mask, candle_area(point, vec2(SCONCES[i], 159.0), vec2(55.0, 75.0)));
		}
	}
	if (point.x < 350.0) {
		mask = max(mask, candle_area(point, vec2(250.0, 412.0), vec2(114.0, 151.0)));
		mask = max(mask, candle_area(point, vec2(95.0, 707.0), vec2(176.0, 157.0)));
	}
	if (point.x > 1500.0) {
		mask = max(mask, candle_area(point, vec2(1609.0, 402.0), vec2(118.0, 152.0)));
		mask = max(mask, candle_area(point, vec2(1650.0, 431.0), vec2(65.0, 85.0)));
		mask = max(mask, candle_area(point, vec2(1874.0, 537.0), vec2(98.0, 180.0)));
		mask = max(mask, candle_area(point, vec2(1775.0, 742.0), vec2(147.0, 134.0)));
	}
	return mask;
}

// 遮罩内的细节使用灭灯参照的局部材质，边缘与正常石面连续交接。
float changed_structure_area(vec2 point) {
	float mask = 0.0; // 任意已变化的区域可以写入替换材质。
	for (int i = 0; i < 6; i++) {
		if ((structure_mask & (1 << i)) != 0) {
			vec4 area = structure_areas[i]; // 左上角、右下角均为原图像素。
			vec2 edge = min(point - area.xy, area.zw - point);
			mask = max(mask, smoothstep(0.0, 12.0, min(edge.x, edge.y)));
		}
	}
	return mask;
}

void fragment() {
	vec3 lit = texture(TEXTURE, UV).rgb; // 主材质保留整个棋盘的石纹和明暗细节。
	vec3 room = lit;
	if (extinction > 0.0 || structure_mask != 0) {
		vec2 point = UV / TEXTURE_PIXEL_SIZE; // 与原画中的蜡烛和结构范围对齐。
		float candle = baked_candlelight(point) * extinction;
		float replacement = max(candle, changed_structure_area(point));
		float stone_gray = dot(lit, vec3(0.2126, 0.7152, 0.0722));
		room = mix(lit, mix(lit, vec3(stone_gray), 0.23), extinction);
		if (replacement > 0.0) {
			vec3 detail = texture(dark_interior, UV).rgb; // 仅采样灭灯的烛台和已换样的结构。
			float gray = dot(detail, vec3(0.2126, 0.7152, 0.0722));
			vec3 stone = vec3(gray * 3.9) + (detail - gray) * 1.8; // 局部提取可照明的中性材质。
			room = mix(room, clamp(stone, vec3(0.0), vec3(1.0)), replacement);
		}
	}
	// 明亮窗洞内原图带灰白棋盘纹，色键只作用于三组窗洞。
	bool at_windows = UV.x > 0.398 && UV.x < 0.599 && UV.y < 0.230;
	if (at_windows) {
		float neutral = min(lit.r, min(lit.g, lit.b)); // 三通道同时高于窗框。
		float opening = smoothstep(0.58, 0.82, neutral);
		if (extinction > 0.0) {
			float dark_opening = 1.0 - texture(dark_interior, UV).a; // 暗版窗洞边缘以 Alpha 提供。
			opening = max(opening, smoothstep(0.12, 0.94, dark_opening) * extinction);
		}
		vec3 sky = vec3(0.0); // 完全黑暗时连照到窗内也只有空洞。
		if (extinction < 1.0) {
			vec2 sky_uv = UV * vec2(2.65, 2.35) + vec2(-0.825, 0.065);
			sky = texture(lit_sky, sky_uv).rgb * (1.0 - extinction);
		}
		room = mix(room, sky, opening);
	}
	COLOR = vec4(room, 1.0);
}
