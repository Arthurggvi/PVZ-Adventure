// 处决副本先银光定格，再化为带银色裂纹的幽影，最后沿全身连续切面升散。
shader_type canvas_item;
render_mode unshaded;

// 变白、破碎分别由同一演出时钟提供。
uniform float whitening = 0.0;
uniform float dissolve = 0.0;
// 单次处决的可暂停秒数，控制短促闪光和裂纹流动。
uniform float execution_seconds = 0.0;
// 采集时全身的世界中心，分件共享同一个灵魂消散方向。
uniform vec2 soul_origin = vec2(0.0);
// 全身高度，归一化向上的溶解层次。
uniform float soul_height = 100.0;
// 世界坐标种子让不同死者的裂纹错开。
uniform float phase = 0.0;
// 保存出土或入水时的原生裁切，白影不会突然显示被遮住的腿部。
uniform bool mask_enabled = false;
uniform float mask_cutoff = 0.0;
uniform bool mask_world = false;
uniform bool mask_above = false;
uniform float mask_fade = 0.0;
// 原姿态各部件颜色与世界坐标。
varying vec4 tint;
varying vec2 world_point;
void vertex() {
	tint = COLOR;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
float hash_cell(vec2 p) {
	vec3 h = fract(vec3(p.xyx) * 0.1031); // 连续噪声网格的确定性散列。
	h += dot(h, h.yzx + 33.33);
	return fract((h.x + h.y) * h.z);
}
float noise_field(vec2 p) {
	vec2 cell = floor(p); // 本次采样所处的网格。
	vec2 f = fract(p); // 网格内部的平滑插值权重。
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0)), f.x), f.y);
}
void fragment() {
	vec4 art = texture(TEXTURE, UV); // 原姿态纹理，透明轮廓保持完整。
	float cloud = noise_field(world_point * vec2(0.04, 0.06) + vec2(phase, 0.0)); // 跨部件一致的大裂纹。
	float flakes = noise_field(world_point * vec2(0.17, 0.14) + vec2(0.0, phase)); // 裂纹边缘的细碎切面。
	float height = clamp((world_point.y - soul_origin.y) / max(soul_height, 1.0) + 0.5, 0.0, 1.0); // 脚部先裂解，上身随后升散。
	float field = cloud * 0.48 + flakes * 0.32 + (1.0 - height) * 0.20; // 兼具向上层次与自然破碎的阈值场。
	float threshold = mix(-0.16, 1.06, dissolve); // 开始完整、结束全透明。
	float coverage = smoothstep(threshold, threshold + 0.05, field); // 当前仍保留的身体碎片。
	float crack = coverage * (1.0 - smoothstep(threshold + 0.025, threshold + 0.11, field)); // 瓦解边界的银焰。
	float luminance = dot(art.rgb, vec3(0.2126, 0.7152, 0.0722)); // 保留衣服和肢体原有明暗结构。
	vec2 pixel = TEXTURE_PIXEL_SIZE * 1.4; // 轮廓采样仅在原部件内偏移约一像素。
	float neighbor = min(min(texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a, texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a), min(texture(TEXTURE, UV + vec2(0.0, pixel.y)).a, texture(TEXTURE, UV - vec2(0.0, pixel.y)).a)); // 局部轮廓透明度。
	float outline = clamp(art.a - neighbor, 0.0, 1.0); // 细银边仅描在真实图像轮廓。
	float flash = exp(-pow((execution_seconds - 0.075) * 24.0, 2.0)); // 只持续数帧的银色定格。
	vec3 spectral = mix(vec3(0.025, 0.035, 0.075), vec3(0.32, 0.40, 0.52), luminance * luminance); // 深色幽影避免整具尸体长时间纯白过曝。
	vec3 color = mix(art.rgb * tint.rgb, spectral, whitening); // 原姿态平滑转为幽影。
	color = mix(color, vec3(0.87, 0.95, 1.0), flash * 0.80);
	color = mix(color, vec3(0.70, 0.86, 1.0), clamp(outline * whitening * 0.85 + crack * 0.94, 0.0, 1.0));
	float mask_alpha = 1.0; // 默认不额外裁切，入水或出土者沿用原遮罩。
	if (mask_enabled) {
		float clip_y = mask_world ? world_point.y : VERTEX.y; // 原遮罩的坐标空间。
		float distance = mask_above ? clip_y - mask_cutoff : mask_cutoff - clip_y; // 到保留半平面的有符号距离。
		mask_alpha = mask_fade > 0.0 ? smoothstep(0.0, mask_fade, distance) : step(0.0, distance);
	}
	COLOR = vec4(color, art.a * tint.a * coverage * mask_alpha);
}
