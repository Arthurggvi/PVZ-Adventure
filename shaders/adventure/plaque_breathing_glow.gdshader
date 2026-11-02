// 独立木牌轮廓光层，按原图 Alpha 生成边缘，不修改底图或文字。
shader_type canvas_item;
render_mode unshaded, blend_add;

// 原木牌在设计画布中的尺寸，以及外围预留的发光范围，单位为设计像素。
uniform vec2 source_size = vec2(263.0, 118.0);
uniform float padding = 12.0;
// 呼吸周期（秒）与暖黄色光。
uniform float period_seconds = 2.8;
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.08, 0.85);

// 图像外侧视为透明，避免采样钳制导致边缘拉丝。
float mask_alpha(sampler2D source_texture, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(source_texture, uv).a;
}

void fragment() {
	// 将扩大的覆盖层坐标映射回原木牌，保持光边与牌面精确对齐。
	vec2 uv = (UV * (source_size + vec2(2.0 * padding)) - vec2(padding)) / source_size;
	float near_edge = 0.0; // 贴近牌边的明亮轮廓。
	float soft_edge = 0.0; // 外围较弱的光晕。
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 6.2831853 / 8.0; // 八方向轮廓采样。
		vec2 direction = vec2(cos(angle), sin(angle)) / source_size;
		near_edge = max(near_edge, mask_alpha(TEXTURE, uv + direction * 3.0));
		soft_edge = max(soft_edge, mask_alpha(TEXTURE, uv + direction * 8.0));
	}
	float outline = (near_edge * 0.8 + soft_edge * 0.3) * (1.0 - mask_alpha(TEXTURE, uv));
	float breath = 0.65 + 0.35 * sin(TIME * 6.2831853 / period_seconds);
	COLOR = vec4(glow_color.rgb, outline * breath * glow_color.a);
}
