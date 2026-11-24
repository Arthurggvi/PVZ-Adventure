// 保留人物中部的原始透明度，让取景边缘融入档案底图。
shader_type canvas_item;
render_mode unshaded;

// 头像控件的逻辑尺寸，用来把图集坐标与渐隐范围分开。
uniform vec2 extent = vec2(184.0, 162.0);
// 由头像控件左上角起算，四条边对应 0 和 1。
varying vec2 portrait_uv;

void vertex() {
	portrait_uv = VERTEX / extent;
}

void fragment() {
	float side_distance = min(portrait_uv.x, 1.0 - portrait_uv.x); // 两侧只柔化取景边缘。
	float sides = smoothstep(0.0, 0.11, side_distance); // 头发和持物在场内保留原轮廓。
	float top = smoothstep(0.0, 0.05, portrait_uv.y); // 头顶只用窄过渡，保留帽饰细节。
	float bottom = 1.0 - smoothstep(0.76, 1.0, portrait_uv.y); // 肩部向铭牌或内底慢慢收尾。
	COLOR.a *= sides * top * bottom;
}
