// 灯条的水光尾迹。沿连续的横截面绘制亮芯、卷流和扩散雾。
shader_type canvas_item;
render_mode unshaded, blend_add;

// 战斗秒数，由尾迹节点推进，暂停时保持形态。
uniform float clock_seconds = 0.0;
// 每段水光的最大寿命，单位为战斗秒。
uniform float lifetime = 1.42;
// 各根灯条使用不同的流纹相位。
uniform float phase = 0.0;

// 返回软边截面。[offset] 是相对中心的有符号距离，[sharpness] 控制收束程度。
float soft_band(float offset, float sharpness) {
	return exp2(-offset * offset * sharpness);
}

void fragment() {
	float age = UV.x; // 横截面从写入水中到消散的年龄比例。
	float cross_section = UV.y * 2.0 - 1.0; // 从水光一侧连续过渡到另一侧。
	float written_at = clock_seconds - age * lifetime; // 流纹随着最初的水柱一同移动。
	float eddy = written_at * 27.0 + age * 4.1 + phase; // 扭曲时由快慢不同的水流共同推动。
	float drift = smoothstep(0.07, 0.76, age); // 年轻部分保持贴合，旧段形成旋流。
	float warp = drift * (0.19 * sin(eddy) + 0.067 * sin(eddy * 1.91 - 0.6)); // 带内亮区随流纹挪动。
	float center = cross_section - warp; // 亮芯周围的截面距离。
	float detail = sin(eddy * 1.86 - cross_section * 7.2 + 0.65 * sin(eddy * 0.82)); // 内外层水纹以不同速度翻卷。
	float density = mix(1.0, 0.70 + detail * 0.30, drift); // 扩散中的薄雾保留连续的明暗变化。
	float halo = soft_band(center, 3.9) * density; // 最外层水光留出宽而透明的边缘。
	float stream = soft_band(center, mix(19.0, 9.0, drift)) * density; // 青色流束先收紧，再随水阻变宽。
	float white_core = soft_band(center, 106.0) * (1.0 - smoothstep(0.06, 0.57, age)); // 刚离灯管的高亮在雾化前退场。
	float upper_fold = soft_band(center - (0.28 + 0.14 * sin(eddy)), 72.0); // 沿卷流外侧形成一层细亮纹。
	float lower_fold = soft_band(center + (0.25 + 0.17 * sin(eddy * 1.31 + 1.25)), 55.0); // 对侧细纹在较深的水色里渐隐。
	float filaments = (upper_fold * (0.54 + 0.32 * detail) + lower_fold * (0.42 - 0.32 * detail)) * drift; // 两侧折光错峰可见。
	float edge = 1.0 - smoothstep(0.59, 1.0, abs(cross_section)); // 透明雾边先于三角形轮廓消失。
	vec3 radiance = vec3(0.045, 0.37, 0.70) * halo * mix(0.37, 0.53, drift); // 散射层由青蓝逐渐扩开。
	radiance += vec3(0.11, 0.86, 0.96) * stream * mix(0.75, 0.41, drift);
	radiance += vec3(0.68, 1.0, 0.96) * white_core * 0.93;
	radiance += vec3(0.24, 0.75, 1.0) * filaments * 0.71;
	COLOR = vec4(radiance * COLOR.rgb, COLOR.a * edge);
}
