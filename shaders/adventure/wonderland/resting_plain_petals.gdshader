shader_type canvas_item;
render_mode unshaded;

// 保留粒子寿命渐变，花瓣在出生和离场时渐显渐隐。
varying vec4 petal_tint;
// 不同朝向的薄瓣交替露出奶白正面和淡杏粉背面。
varying flat float petal_face;

void vertex() {
	// 每片花瓣按自己的世界位置取得旋转起点。
	float phase = dot(MODEL_MATRIX[3].xy, vec2(0.011, 0.019));
	petal_face = cos(TIME * 2.53 + phase);
	VERTEX.x *= 0.36 + 0.64 * abs(petal_face);
	petal_tint = COLOR;
}

void fragment() {
	vec2 petal = UV * 2.0 - 1.0; // 花瓣在局部纹理中以上宽下窄的形状展开。
	float width = mix(0.44, 0.91, smoothstep(-0.8, 0.68, petal.y)); // 下端收成柔软的小尖。
	vec2 outline = vec2((petal.x - 0.16 * petal.y * petal.y) / width, petal.y / 0.91); // 弯曲的瓣缘。
	float coverage = 1.0 - smoothstep(0.68, 1.04, dot(outline, outline)); // 软边遮罩。
	float fold = 1.0 - smoothstep(0.025, 0.17, abs(petal.x + 0.11 * petal.y)); // 浅色的中心折痕。
	vec3 tint = mix(vec3(1.0, 0.67, 0.59), vec3(1.0, 0.93, 0.75), petal_face * 0.5 + 0.5); // 正反面色差。
	tint = mix(tint, vec3(1.0, 0.97, 0.85), 0.43 * fold);
	COLOR = vec4(tint * petal_tint.rgb, coverage * petal_tint.a);
}
