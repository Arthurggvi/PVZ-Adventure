// 局部加色光，不依赖全屏辉光或前向渲染器。
shader_type canvas_item;
render_mode unshaded, blend_add;
// 保存绘制指令提供的逐粒颜色与透明度。
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float light = max(source.r, max(source.g, source.b));
	COLOR = vec4(tint.rgb * light, source.a * tint.a);
}
