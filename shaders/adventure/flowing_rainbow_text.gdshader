shader_type canvas_item;
render_mode unshaded;

uniform float highlight_strength : hint_range(0.0, 1.0) = 0.24; // 扫光混入暖白色的最大比例。
varying vec2 text_position; // 标签内的像素坐标，跨字形与换行保持连续。

void vertex() {
	text_position = VERTEX;
}

void fragment() {
	float phase = (text_position.x - text_position.y * 0.38) / 184.0 - TIME / 4.0; // 色带每四秒向右扫过一个周期。
	vec3 hue = abs(fract(phase + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0; // 六色连续循环。
	vec3 ink = mix(vec3(0.16), vec3(0.86), smoothstep(vec3(0.0), vec3(1.0), hue)); // 保留饱和色与暗部细节。
	float brightness = dot(ink, vec3(0.2126, 0.7152, 0.0722)); // 压低黄绿等亮色，保持羊皮纸上的字形对比度。
	ink *= min(1.0, 0.45 / brightness);
	float glint = pow(0.5 + 0.5 * cos(TAU * (phase - 0.62)), 12.0); // 窄扫光随青蓝色带移动。
	COLOR.rgb *= mix(ink, vec3(1.0, 0.91, 0.78), glint * highlight_strength); // 保留字形的抗锯齿和透明度。
}
