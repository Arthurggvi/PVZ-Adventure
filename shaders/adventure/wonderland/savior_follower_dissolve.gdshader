// 普通僵尸各个分件共用世界空间的消散阈值，保持黑影轮廓连续。
shader_type canvas_item;

// 脚点的世界坐标及从完整到消失的补间进度。
uniform vec2 origin = vec2(0.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// 入水时保持分件在原生水线上的裁切。
uniform bool clip_waterline = false;
uniform float waterline_y = 0.0;

varying vec2 world_pixel; // 消散场的世界像素位置。

void vertex() {
	world_pixel = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float grain(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 relative_pixel = world_pixel - origin; // 各个分件共用脚点作为瓦解起始位置。
	float height = clamp(-relative_pixel.y / 108.0, 0.0, 1.0); // 脚下先碎裂，遮罩逐渐上升。
	float speck = grain(floor(relative_pixel / vec2(4.0, 5.0))); // 画布像素尺度的碎边。
	float field = height * 0.49 + speck * 0.51; // 竖向传播叠加错开的孔隙。
	float boundary = mix(-0.09, 1.0, progress); // 起始全满，结束全空。
	float alpha = smoothstep(boundary, boundary + 0.08, field); // 瓦解边缘的覆盖率。
	float rim = alpha * (1.0 - smoothstep(boundary + 0.03, boundary + 0.19, field)); // 短暂显露的灰紫碎边。
	float water_mask = clip_waterline ? step(world_pixel.y, waterline_y) : 1.0; // 保留水线上方。
	COLOR = vec4(vec3(0.12, 0.09, 0.15) * rim, COLOR.a * alpha * water_mask);
}
