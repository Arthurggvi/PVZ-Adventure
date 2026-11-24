// 在白闪退开后保留一拍冷色失焦，再回到当前清晰画面。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D battle_image : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// 画面中的闪光源；可在边缘或视口外。
uniform vec2 focus_uv = vec2(0.5, 0.5);
// 白色覆盖率和失焦量各自衰减。
uniform float flash = 0.0;
uniform float defocus = 0.0;

void fragment() {
	vec2 direction = SCREEN_UV - focus_uv; // 从闪光源轻微向外散焦。
	vec2 smear = direction * defocus * 0.008;
	vec3 sharp = textureLod(battle_image, SCREEN_UV, 0.0).rgb;
	vec3 soft = textureLod(battle_image, SCREEN_UV - smear, 4.4 * defocus).rgb;
	vec3 scene = mix(sharp, soft, defocus * 0.90);
	float bloom = exp(-length(direction * vec2(1.03, 0.72)) * 3.4) * defocus;
	float veil = clamp(flash + (1.0 - flash) * (0.10 * defocus + 0.18 * bloom), 0.0, 1.0);
	COLOR = vec4(mix(scene, vec3(0.973, 0.991, 1.0), veil), 1.0);
}
