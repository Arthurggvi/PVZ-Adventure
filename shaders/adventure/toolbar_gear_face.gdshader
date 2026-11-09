shader_type canvas_item;

void fragment() {
	// 保留浅色齿轮，原图深色底盘和铜边交由工具栏的通用槽位素材替代。
	vec3 source = texture(TEXTURE, UV).rgb;
	float metal = smoothstep(0.24, 0.38, min(source.r, min(source.g, source.b)));
	COLOR.a *= metal;
}
