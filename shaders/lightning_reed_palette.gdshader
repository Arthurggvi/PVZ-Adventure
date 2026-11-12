// 按原贴图的明暗重新着色，保留脸部线条、电弧轮廓与原有透明度。
shader_type canvas_item;

// 根部、茎身和顶端的阶级色，与头部高光共用一条垂直渐变。
uniform vec4 root_tone : source_color;
uniform vec4 stem_tone : source_color;
uniform vec4 tip_tone : source_color;
// 电弧外缘和亮芯的颜色。植株最亮的部位也沿用亮芯色。
uniform vec4 arc_tone : source_color;
uniform vec4 core_tone : source_color;
// 二阶只给根部上色。飞行和命中特效只使用电弧色。
uniform bool root_only = false;
uniform bool projectile = false;
// 根部的世界锚点和把世界位移换算为局部高度的轴。
uniform vec2 root_origin = vec2(0.0);
uniform vec2 height_axis = vec2(0.0, -1.0);
// 原本体型的参考高度，单位为外观锚点的局部像素。
uniform float body_height = 96.0;

// 保留动画部件、受击和界面共同给出的颜色乘数。
varying vec4 sprite_tint;
// 从根部向上量出的局部高度，在所有部件之间连续。
varying float reed_height;

void vertex() {
	sprite_tint = COLOR;
	vec2 world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	reed_height = dot(world_position - root_origin, height_axis);
}

void fragment() {
	// 用最亮通道保留高饱和边缘的层次，以最暗通道识别原画里的白色亮芯。
	vec4 source = texture(TEXTURE, UV);
	float value = max(source.r, max(source.g, source.b));
	float white = smoothstep(0.48, 0.99, min(source.r, min(source.g, source.b)));
	vec3 rgb;
	if (projectile) {
		rgb = mix(arc_tone.rgb * mix(0.55, 1.0, value), core_tone.rgb, white);
	} else {
		// 渐变以植株根部为原点，换帧、翻转或缩放都不会使颜色偏离根部。
		float root_weight = 1.0 - smoothstep(0.0, body_height * 0.24, reed_height);
		float tip_weight = smoothstep(body_height * 0.20, body_height, reed_height);
		vec3 tone = mix(mix(stem_tone.rgb, tip_tone.rgb, tip_weight), root_tone.rgb, root_weight);
		// 保留深色眼睛、叶脉及高光，只调整其色相和明暗比例。
		vec3 pigment = tone * sqrt(value) * mix(0.48, 1.0, value);
		rgb = mix(pigment, core_tone.rgb, white * 0.56);
		if (root_only) {
			rgb = mix(source.rgb, rgb, root_weight);
		}
	}
	COLOR = vec4(rgb, source.a) * sprite_tint;
}
