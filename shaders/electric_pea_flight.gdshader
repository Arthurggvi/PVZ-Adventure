// 已合并的飞行遮罩。RGB 分别保存主电色、亮芯和辅色的权重。
shader_type canvas_item;

uniform vec4 rim_tone : source_color;
uniform vec4 core_tone : source_color;
uniform vec4 glow_tone : source_color;

// 保存精灵和它的祖先提供的淡入淡出颜色。
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

void fragment() {
	vec4 weights = texture(TEXTURE, UV);
	vec3 rgb = weights.r * rim_tone.rgb + weights.g * core_tone.rgb + weights.b * glow_tone.rgb;
	COLOR = vec4(rgb, weights.a) * sprite_tint;
}
