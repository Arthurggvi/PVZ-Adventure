// 融合体短跨帧与保色死亡消散；双原画先对齐脚点，不推算或拉扯表面特征。
shader_type canvas_item;

// 相邻的完整原画编号，正反向循环均由外部唯一相位决定。
uniform int next_frame : hint_range(0, 11) = 0;
// 仅跨帧末尾十八毫秒非零，停止和死亡快照清零以保留清晰形体。
uniform float frame_mix : hint_range(0.0, 1.0) = 0.0;
// 下一原画与主原画的脚点高度差，单位为一个三百八十四像素图块的UV。
uniform float next_foot_offset = 0.0;
// 完整到瓦解的进度；由外部死亡演出推进，暂停时保持当前状态。
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
// 撞击与分裂时的短促米灰提亮，不把暗色轮廓刷成白块。
uniform float hit_strength : hint_range(0.0, 1.0) = 0.0;

// 从精灵局部顶点保存原画位置，噪声不随四乘三图集帧号跳变。
varying vec2 source_pixel;
// 顶点阶段的颜色尚未乘上纹理，避免手动采样后重复乘原帧。
varying vec4 vertex_tint;

// 只记录形变前的位置；挤压、呼吸和下塌由外部表现节点负责。
void vertex() {
	source_pixel = VERTEX;
	vertex_tint = COLOR;
}

// 每个局部小格使用固定灰度，不读取时间，也不干扰战斗随机数。
float grain(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

// 预乘透明度混合避免黑边；原画、引擎调色与死亡消散各只合成一次。
void fragment() {
	vec4 source = texture(TEXTURE, UV); // 非过渡帧只需一次纹理采样。
	if (frame_mix > 0.0001) {
		vec2 grid = vec2(4.0, 3.0); // 图集固定四列三行，仍使用原始十二帧素材。
		vec2 local_uv = fract(UV * grid) + vec2(0.0, next_foot_offset); // 第二张下缘与主原画落在同一世界脚点。
		vec2 half_pixel = TEXTURE_PIXEL_SIZE * grid * 0.5; // 双线性采样不得越过图块像素中心。
		vec2 tile = vec2(float(next_frame % 4), floor(float(next_frame) / 4.0)); // 下一张原画的格坐标。
		float inside = step(0.0, local_uv.x) * step(local_uv.x, 1.0) * step(0.0, local_uv.y) * step(local_uv.y, 1.0); // 图块之外透明。
		vec4 adjacent = texture(TEXTURE, (tile + clamp(local_uv, half_pixel, vec2(1.0) - half_pixel)) / grid) * inside; // 短窗口内才取第二张原画。
		float alpha = mix(source.a, adjacent.a, frame_mix); // 透明轮廓按覆盖率混合。
		vec3 premultiplied = mix(source.rgb * source.a, adjacent.rgb * adjacent.a, frame_mix); // 原色先乘透明度。
		source = vec4(premultiplied / max(alpha, 0.0001), alpha);
	}
	source *= vertex_tint;
	float speck = grain(floor(source_pixel / vec2(8.0, 9.0))); // 显示缩放后约四像素的碎边。
	float downward = clamp(0.5 + source_pixel.y / 384.0, 0.0, 1.0); // 上部略先散开，脚点保留到后段。
	float field = speck * 0.78 + downward * 0.22; // 小片错开消失，避免硬直的水平擦除。
	float boundary = mix(-0.10, 1.10, clamp(dissolve, 0.0, 1.0)); // 两端分别完全保留和完全透明。
	float coverage = smoothstep(boundary, boundary + 0.08, field); // 柔化每块细小的边缘。
	float rim = coverage * (1.0 - smoothstep(boundary + 0.03, boundary + 0.17, field))
		* smoothstep(0.0, 0.06, dissolve); // 仅保留即将散去的窄边，完整时绝不重染原图。
	vec3 surface = mix(source.rgb, vec3(0.43, 0.39, 0.36), rim * 0.36); // 边缘轻微变灰，原画仍可辨认。
	surface += vec3(0.085, 0.073, 0.043) * clamp(hit_strength, 0.0, 1.0); // 短促暖灰提亮。
	COLOR = vec4(surface, source.a * coverage);
}
