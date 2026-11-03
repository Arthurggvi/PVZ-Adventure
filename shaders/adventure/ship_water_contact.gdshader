// 在原船体Alpha下沿形成窄水线，不移动或采样整张背景。
shader_type canvas_item;
// 总FX开关只停止波动，保留必要的静态衔接。
uniform bool animate = true;
// 原船图像素中的边缘宽度，避免生成过厚光边。
uniform float edge_pixels = 5.0;
// 单独传递顶点调制，避免重复乘贴图Alpha。
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 hull = texture(TEXTURE, UV);
	float clock = animate ? TIME : 0.0;
	vec2 offset = vec2(0.0, TEXTURE_PIXEL_SIZE.y * edge_pixels);
	float above = texture(TEXTURE, clamp(UV - offset, vec2(0.0), vec2(1.0))).a;
	float below = texture(TEXTURE, clamp(UV + offset, vec2(0.0), vec2(1.0))).a;
	float lower_hull = smoothstep(0.53, 0.73, UV.y);
	float inner_edge = hull.a * (1.0 - below) * lower_hull;
	float outer_edge = max(above - hull.a, 0.0) * lower_hull;
	float pulse = 0.65 + 0.18 * sin(UV.x * 67.0 + clock * 1.2);
	hull.rgb = mix(hull.rgb, vec3(0.20, 0.53, 0.59), inner_edge * 0.65);
	float foam = (inner_edge * 0.35 + outer_edge * 0.70) * pulse;
	COLOR = vec4(mix(hull.rgb, vec3(0.69, 0.90, 0.91), foam), max(hull.a, foam)) * tint;
}
