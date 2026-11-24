// 将已有风雾贴图当作雪云的光学厚度，保留旋卷纹理并给原图裁边留出软雾。
shader_type canvas_item;
render_mode unshaded;

varying vec4 bank;

void vertex() {
	bank = COLOR;
}

void fragment() {
	vec4 cloud = texture(TEXTURE, UV); // 暖紫色的旧素材保留明暗和原来的透明轮廓。
	vec2 edge = min(UV, vec2(1.0) - UV);
	float feather = smoothstep(0.0, 0.065, edge.x) * smoothstep(0.0, 0.065, edge.y);
	float depth = cloud.a * feather * bank.a;
	float transmission = exp2(-7.4 * depth);
	float luminance = dot(cloud.rgb, vec3(0.2126, 0.7152, 0.0722));
	float glow = smoothstep(0.18, 0.79, luminance) * 0.56 + 0.38 * smoothstep(0.05, 0.47, cloud.a);
	vec3 color = mix(vec3(0.65, 0.78, 0.89), vec3(0.973, 0.993, 1.0), glow) * bank.rgb;
	COLOR = vec4(color, 1.0 - transmission);
}
