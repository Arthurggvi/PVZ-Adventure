shader_type canvas_item;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float gray = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(tex.rgb, vec3(gray * 0.55), 0.92), tex.a * 0.67);
}
