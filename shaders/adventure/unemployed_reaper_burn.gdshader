shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float heat = dot(COLOR.rgb, vec3(0.28, 0.63, 0.09)); // 从原动画取亮度，保留透明边缘与原有动势。
	vec3 violet = mix(vec3(0.28, 0.075, 0.56), vec3(0.94, 0.78, 1.0), smoothstep(0.15, 0.86, heat)); // 紫边到银紫焰心。
	COLOR = vec4(violet, COLOR.a);
}
