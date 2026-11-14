// 电能豌豆专属换色：彩色轮廓按高度重映射，白色能量面、暗线和原透明度保持可读。
shader_type canvas_item;

// 根、茎、头顶的彩色区域；白色面不直接乘入这些颜色。
uniform vec4 root_tone : source_color;
uniform vec4 stem_tone : source_color;
uniform vec4 tip_tone : source_color;
// 特效主电色和近白芯；高亮不依靠整株加法叠光。
uniform vec4 rim_tone : source_color;
uniform vec4 core_tone : source_color;
// 特效只重映射电色，不需要本体的空间渐变。
uniform bool projectile = false;
// 飞行球才按原球面半径柔和收束垂尾；命中和放电不启用该裁切。
uniform bool trim_projectile_tail = false;
uniform float projectile_radius = 16.0;
// 动画共用的根部世界锚点、局部高度轴及参考高度，单位为局部像素。
uniform vec2 root_origin = vec2(0.0);
uniform vec2 width_axis = vec2(1.0, 0.0);
uniform vec2 height_axis = vec2(0.0, -1.0);
uniform float body_height = 84.0;

// 保留受击、动画和界面淡入淡出给出的颜色乘数。
varying vec4 sprite_tint;
// 所有分层部件使用同一条连续的局部高度轴。
varying float plant_height;
// 飞行球的局部横坐标，与高度一起识别球面之外的原垂尾。
varying float effect_width;

void vertex() {
	sprite_tint = COLOR;
	// 世界坐标通过锚点逆轴换回本体高度，缩放和翻转后仍与根部对齐。
	vec2 world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	plant_height = dot(world_position - root_origin, height_axis);
	effect_width = dot(world_position - root_origin, width_axis);
}

void fragment() {
	// 最大通道保存原画层次，最小通道识别白色能量面，色差识别需要换色的轮廓。
	vec4 source = texture(TEXTURE, UV);
	float value = max(source.r, max(source.g, source.b));
	float minimum = min(source.r, min(source.g, source.b));
	float chroma = value - minimum;
	float white = smoothstep(0.58, 0.96, minimum);
	// 默认保留原透明度，只有飞行球的专属实例会收束原垂尾。
	float coverage = 1.0;
	vec3 rgb;
	if (projectile) {
		// 主色只占电光边缘，最亮的原画纹理回到清透近白，不把整个球染成实心色块。
		vec3 electric_edge = mix(rim_tone.rgb * 0.38, rim_tone.rgb, smoothstep(0.06, 0.90, value));
		rgb = mix(electric_edge, core_tone.rgb, white);
		if (trim_projectile_tail) {
			// 半径由具体原版球片段提供，圆球主体和表面动画完整保留，外缘自然渐隐。
			float distance_from_core = length(vec2(effect_width, plant_height));
			coverage = 1.0 - smoothstep(projectile_radius, projectile_radius * 1.24, distance_from_core);
		}
	} else {
		// 紫根在最低的叶片收束，头部大部分使用主电色，以白芯形成清楚的实体轮廓。
		float root_weight = 1.0 - smoothstep(0.0, body_height * 0.27, plant_height);
		float tip_weight = smoothstep(body_height * 0.28, body_height, plant_height);
		vec3 tone = mix(mix(stem_tone.rgb, tip_tone.rgb, tip_weight), root_tone.rgb, root_weight);
		// 用明暗重映射取代整图乘色，饱和彩边不会被原绿色通道压暗。
		vec3 pigment = mix(tone * 0.20, tone, smoothstep(0.04, 0.88, value));
		pigment = mix(pigment, core_tone.rgb, smoothstep(0.82, 1.0, value) * 0.09);
		// 原画接近黑色的细线保留；接近白色的脸和眼睛只给极轻的冷色温。
		float pigment_weight = smoothstep(0.04, 0.19, chroma) * smoothstep(0.035, 0.15, value);
		vec3 neutral = mix(source.rgb, core_tone.rgb * value, white * 0.20);
		rgb = mix(neutral, pigment, pigment_weight * (1.0 - white));
	}
	COLOR = vec4(rgb, source.a * coverage) * sprite_tint;
}
