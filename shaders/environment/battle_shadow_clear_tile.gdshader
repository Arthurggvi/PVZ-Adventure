shader_type canvas_item;
render_mode unshaded, blend_disabled;

void fragment() {
	// 整格覆写透明，下一层再填入这一帧的精灵 Alpha。
	COLOR = vec4(0.0);
}
