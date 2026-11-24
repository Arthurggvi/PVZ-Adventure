shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// 透明视口的预乘颜色与透明度，用原 Alpha 合成回战场。
uniform sampler2D hud_texture : filter_linear, repeat_disable;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 hud = texture(hud_texture, UV);
	float luminance = dot(hud.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(mix(hud.rgb, vec3(luminance * 0.54), darkness), hud.a);
}
