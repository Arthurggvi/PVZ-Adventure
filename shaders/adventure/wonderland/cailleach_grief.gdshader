// 悲寒以连续冷色映射逐级淡去原画，满层及安息残像保留同一蓝白轮廓。
shader_type canvas_item;

uniform float sorrow = 0.0;
uniform float disperse = 0.0;
uniform bool imitater = false;
varying vec2 ground_point;

void vertex() {
	ground_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; // 同株各部件共享风化纹理。
	VERTEX += vec2(-24.0, -7.0) * disperse * disperse; // 残像瓦解时沿雪幕漂移。
}

void fragment() {
	vec3 base = COLOR.rgb;
	float luma = dot(base, vec3(0.25, 0.63, 0.12)); // 留下叶脉与脸部的原始明暗。
	if (imitater) {
		base = vec3(luma);
	}
	vec3 palette = mix(vec3(0.12, 0.37, 0.66), vec3(0.87, 0.96, 1.0), clamp(luma, 0.0, 1.0));
	vec3 frost = mix(base, palette, sorrow * 0.91);
	float alpha = COLOR.a;
	if (sorrow >= 1.0) {
		frost = vec3(0.73, 0.89, 1.0); // 满层忽略原画的内部色差。
	}
	if (disperse > 0.0) {
		float folds = sin(ground_point.y * 0.28 + ground_point.x * 0.061)
			* sin(ground_point.x * 0.39 - ground_point.y * 0.09);
		float flecks = sin(ground_point.x * 0.79 + ground_point.y * 1.34) * 0.12;
		float threshold = 0.49 + 0.27 * folds + flecks; // 风纹与细碎粉雪分层消散。
		float edge = smoothstep(disperse - 0.14, disperse + 0.075, threshold);
		frost = mix(vec3(0.95, 0.99, 1.0), frost, edge);
		alpha *= edge * (1.0 - smoothstep(0.68, 1.0, disperse));
	}
	COLOR = vec4(frost, alpha);
}
