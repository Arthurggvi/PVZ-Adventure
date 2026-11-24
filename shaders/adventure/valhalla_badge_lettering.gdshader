shader_type canvas_item;
render_mode unshaded;

// 题字的局部宽度，单位为像素。色带在整行中穿行，避免反复分色。
uniform float text_width = 160.0;
// 挚爱之章使用暖玫瑰金，神殿之光保留珍珠与浅蓝的反光。
uniform bool rose_gold = false;

// 字形四边形在标签内的位置，让斜向色带在字形之间连续。
varying vec2 text_position;
// 字形绘制颜色的目标亮度，用于区分亮色字面与深色描边、投影。
varying float fill_weight;

void vertex() {
	text_position = VERTEX;
	float ink_light = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)); // 贴图采样前的亮度，独立于字形的抗锯齿覆盖率。
	fill_weight = smoothstep(0.25, 0.70, ink_light);
}

void fragment() {
	float wavelength = clamp(text_width * 1.12, 116.0, 344.0); // 一组反光至少跨过大部分标题。
	float phase = dot(text_position, vec2(1.0, 0.65)) / wavelength - TIME / 6.4; // 色带缓慢沿刻字滑过。
	vec4 band_distance = abs(fract(phase - vec4(0.0, 0.25, 0.50, 0.75) + 0.5) - 0.5); // 环形相位内到四个主色的距离。
	vec4 band = 1.0 - smoothstep(vec4(0.0), vec4(0.25), band_distance); // 相邻色带平滑交接，任一位置都维持亮色。
	vec3 prism = band.x * vec3(1.0, 0.72, 0.33)
		+ band.y * vec3(1.0, 0.88, 0.64)
		+ band.z * vec3(0.85, 0.83, 1.0)
		+ band.w * vec3(0.66, 0.88, 1.0); // 以两段暖金承接珍珠色与浅蓝色反光。
	vec3 ivory = vec3(1.0, 0.93, 0.78); // 暗部也保有珍珠金底色。
	if (rose_gold) {
		prism = band.x * vec3(1.0, 0.65, 0.51)
			+ band.y * vec3(1.0, 0.88, 0.67)
			+ band.z * vec3(1.0, 0.78, 0.76)
			+ band.w * vec3(0.98, 0.55, 0.59);
		ivory = vec3(1.0, 0.89, 0.79);
	}
	float crest = band.y * band.y; // 暖金与珍珠色交界形成较窄的高光。
	vec3 letter_color = mix(mix(ivory, prism, 0.72), vec3(1.0, 0.98, 0.92), crest * 0.42); // 高光柔和滑过笔画。
	COLOR.rgb *= mix(vec3(1.0), letter_color, fill_weight); // 保留渲染器算出的字形、描边及投影透明度。
}
