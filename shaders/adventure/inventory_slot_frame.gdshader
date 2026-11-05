// 保留默认格子的原版边框，仅挖空内部填色，作为图标上层的透明边框。
shader_type canvas_item;

// 原图像素单位的边框内沿，不随 UI 显示缩放改变。
uniform vec2 inset_pixels = vec2(13.0);
// 内沿圆角半径，单位为原图像素。
uniform float inner_radius_pixels = 6.0;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 inner_half_size = texture_size * 0.5 - inset_pixels;
	vec2 corner = abs((UV - vec2(0.5)) * texture_size) - inner_half_size + vec2(inner_radius_pixels);
	float distance_to_inner = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - inner_radius_pixels;
	COLOR.a *= smoothstep(-0.5, 0.5, distance_to_inner);
}
