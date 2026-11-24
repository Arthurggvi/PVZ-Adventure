// 用明灯的浪纹塑造低伏、抬升和向前翻卷的浪面。
shader_type canvas_item;
render_mode unshaded;

// 战斗秒与分路相位；暂停时由浪节点保持。
uniform float travel_time = 0.0;
uniform float phase = 0.0;
// 起浪成长、共享的水冠峰位与高度、向前落卷及最终贴地的比例。
uniform float formation = 0.0;
uniform float peak = 0.38;
uniform float crest_height = 0.05;
uniform float curl = 0.0;
uniform float collapse = 0.0;
// 父节点的淡入淡出，只在最后写入。
varying vec4 paint;

void vertex() {
	paint = COLOR;
}

float cross_section(float distance, float width) {
	float ratio = distance / width;
	return exp2(-ratio * ratio);
}

void fragment() {
	float back = UV.x; // 0 为行进侧的浪尖；Sprite2D 负责镜像方向。
	float motion = travel_time * 5.2 + phase;
	float foot = 0.88 + 0.023 * sin(back * 16.0 - motion * 0.65);
	float face = smoothstep(0.018, peak, back);
	float slope = 1.0 - smoothstep(peak * 0.93, 0.97, back);
	float volume = pow(max(0.0, face * slope), 0.72);
	float contour = 0.026 * sin(back * 25.0 + motion) + 0.012 * sin(back * 57.0 - motion * 1.4);
	float lip = foot - volume * max(0.014, crest_height + contour * formation);
	float thickness = max(0.025, foot - lip);
	float depth = clamp((UV.y - lip) / thickness, 0.0, 1.0); // 0 为翻卷的水冠，1 为贴地的水脚。
	float aa = max(fwidth(UV.y - lip), 0.007);
	float silhouette = smoothstep(-aa, aa * 1.8, UV.y - lip) * (1.0 - smoothstep(-0.045, 0.044, UV.y - foot));
	float edges = smoothstep(0.005, 0.075, back) * (1.0 - smoothstep(0.67, 0.985, back));
	if (silhouette * edges <= 0.005) {
		discard;
	}

	// 让原有的海水纹理随波形被卷起再流回底部，采样避开透明边缘。
	float bend = (1.0 - depth) * sin(depth * 8.0 + motion) * (0.04 + curl * 0.08);
	vec2 texture_uv = vec2(clamp(back * 0.84 + 0.08 + bend, 0.04, 0.96),
		clamp(0.22 + depth * 0.63 + 0.07 * sin(motion * 0.98 + back * 9.0 - depth * 4.0), 0.10, 0.90));
	vec4 original = texture(TEXTURE, texture_uv);
	float detail = mix(0.34, dot(original.rgb, vec3(0.27, 0.54, 0.19)), original.a);
	float shoulder = cross_section(depth - 0.12, 0.222);
	float shadow = cross_section(depth - 0.47 - 0.09 * curl, 0.227);
	vec3 water = mix(vec3(0.022, 0.19, 0.27), vec3(0.13, 0.55, 0.62), shoulder * 0.73 + detail * 0.22);
	float pocket = cross_section(back - peak + 0.08, 0.084) * cross_section(depth - 0.46, 0.24);
	water *= 1.0 - 0.26 * shadow - 0.39 * curl * pocket;
	float dapple = 0.55 + 0.45 * sin(back * 39.0 - motion * 2.0 + sin(back * 19.0 + motion) * 1.3);
	float rim = cross_section(depth - 0.035 - dapple * 0.066, 0.125);
	float fold = back - peak + 0.07 + 0.10 * sin(depth * 5.8 + 0.3);
	float spill = cross_section(fold, 0.019 + dapple * 0.011)
		* smoothstep(0.10, 0.23, depth) * (1.0 - smoothstep(0.49, 0.73, depth));
	float foam = clamp(rim * (0.33 + 0.44 * dapple) + curl * spill * 0.73
		+ smoothstep(0.42, 0.90, detail) * (0.26 + 0.35 * shoulder), 0.0, 1.0);
	float broken = mix(1.0, smoothstep(0.20, 0.64, 0.58 * detail + 0.42 * dapple), collapse * 0.75);
	vec3 color = mix(water, vec3(0.83, 0.98, 0.98), foam);
	float opacity = silhouette * edges * broken * mix(0.56, 0.94, volume) * (1.0 - 0.27 * smoothstep(0.79, 1.0, depth));
	COLOR = paint * vec4(color, opacity);
}
