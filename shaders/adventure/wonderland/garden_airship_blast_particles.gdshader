shader_type canvas_item;
render_mode unshaded, blend_mix;

// 复用原爆炸裁片和八格烟图。各实例只读取自身形状，不采样屏幕。
uniform sampler2D hot_core : source_color, filter_linear, repeat_disable;
uniform sampler2D flame_lobe : source_color, filter_linear, repeat_disable;
uniform sampler2D rays : source_color, filter_linear, repeat_disable;
uniform sampler2D smoke_atlas : source_color, filter_linear, repeat_disable;

// 材质号、初相、风捕获程度、寿命进度。各字段均在 0 至 1。
varying vec4 particle;

void vertex() {
	particle = INSTANCE_CUSTOM;
}

void fragment() {
	float role = floor(particle.x * 7.0 + 0.5); // 低精度实例量化之后仍恢复正确的分类。
	float phase = particle.y; // 同一次爆炸里的形状不同时卷起。
	float pull = particle.z; // 火团捕风时才剪切图案。
	float age = particle.w; // 已经走过的寿命比例。
	vec2 point = UV * 2.0 - 1.0; // 当前面片中心为局部原点。
	vec4 paint = vec4(1.0); // 受力、温度与透明度再由实例颜色乘入。
	if (role < 0.5) {
		float falloff = 1.0 - smoothstep(0.03, 1.0, length(point)); // 面片以外不染色。
		paint.a = falloff * falloff;
	} else if (role < 1.5) {
		float frame = floor(min(phase * 8.0, 7.999)); // 每团来自随机固定裁片，避免帧跳。
		vec2 cell = vec2(mod(frame, 4.0), floor(frame * 0.25)); // 原图为四列两行。
		vec2 eddy = vec2(0.0, sin(UV.x * 5.5 + phase * 12.0) * 0.068 * age); // 卷曲烟带略具尾流弯度。
		paint = texture(smoke_atlas, (cell + clamp(UV + eddy, vec2(0.004), vec2(0.996))) * vec2(0.25, 0.5));
	} else if (role < 2.5) {
		point.x -= 0.10 * age + point.y * 0.08 * age; // 晚期压力波局部偏斜，起点仍保持中心。
		float rim = length(point) + 0.023 * age * sin(point.x * 12.0 + phase * 8.0); // 小幅不规则外缘。
		paint.a = smoothstep(0.70, 0.85, rim) * (1.0 - smoothstep(0.86, 0.97, rim));
	} else if (role < 3.5) {
		paint = texture(rays, UV);
	} else if (role < 4.5) {
		vec2 shear = UV; // 上风侧纹理压缩、下风侧纹理延长。
		shear.x += 0.66 * pull * UV.x * (1.0 - UV.x);
		shear.y = 0.5 + (UV.y - 0.5) * (1.0 + (1.0 - UV.x) * 0.72 * pull);
		shear.y += pull * (0.16 * (phase - 0.5) + 0.075 * sin(UV.x * 6.0 + phase * 12.0));
		paint = texture(flame_lobe, clamp(shear, vec2(0.0), vec2(1.0)));
		float boundary = smoothstep(0.0, 0.06, shear.y) * (1.0 - smoothstep(0.94, 1.0, shear.y)); // 剪切后不夹出硬边。
		float rift = sin(shear.x * 22.0 + phase * 17.0) * sin(shear.y * 15.0 - phase * 7.0); // 冷却时团边有不规则断口。
		paint.a *= boundary * (1.0 - pull * smoothstep(0.25, 0.93, rift) * smoothstep(0.42, 1.0, age) * 0.78);
		float fold = 0.69 + 0.19 * sin(shear.x * 10.4 + phase * 11.0) + 0.14 * sin(shear.y * 13.0 - shear.x * 5.0); // 热团内有不规则火纹。
		float heat = clamp(fold + 0.15 * smoothstep(0.38, 0.76, paint.a) - 0.08 * age, 0.0, 1.0); // 透明边缘先冷却。
		paint.rgb *= vec3(1.0, mix(0.53, 1.0, heat), mix(0.35, 1.0, heat));
	} else if (role < 5.5) {
		paint = texture(hot_core, UV);
		float contour = length(point * vec2(1.0, 1.09)) + 0.09 * sin(point.x * 8.4 + point.y * 7.3 + phase * 10.0); // 白热内芯有轻微不规则轮廓。
		float heat = 1.0 - smoothstep(0.17, 0.80, contour);
		paint.rgb *= mix(vec3(1.0, 0.68, 0.33), vec3(1.0), heat);
		paint.rgb = mix(paint.rgb, vec3(1.0, 0.98, 0.87), 0.68 * (1.0 - age) * heat);
	} else if (role < 6.5) {
		float width = 0.17 + 0.62 * smoothstep(0.10, 0.82, UV.x); // 速度拖尾朝后收成细线。
		float head = smoothstep(0.46, 0.85, UV.x); // 最亮处即粒子的瞬时位置。
		paint.a = smoothstep(0.03, 0.70, UV.x) * (1.0 - smoothstep(0.83, 1.0, UV.x))
			* (1.0 - smoothstep(0.20 * width, width, abs(point.y)));
		paint.rgb = mix(vec3(1.0, 0.49, 0.24), vec3(1.0, 1.0, 0.92), head);
	} else {
		float bevel = abs(point.y + 0.23 * point.x - 0.09 * sin(phase * 7.0)); // 微小金属片的切斜边。
		float edge = 0.52 * (1.0 - 0.63 * abs(point.x)); // 不会出现随机矩形替代结构碎片。
		paint.a = (1.0 - smoothstep(edge - 0.11, edge, bevel)) * (1.0 - smoothstep(0.77, 0.96, abs(point.x)));
		paint.rgb = mix(vec3(0.50, 0.66, 0.80), vec3(1.0, 0.82, 0.55), smoothstep(-0.25, 0.29, point.y));
	}
	COLOR *= paint;
}
