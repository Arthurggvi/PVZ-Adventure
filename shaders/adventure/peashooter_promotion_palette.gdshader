// 对原动画分件着色，保留纹理透明度和父节点的状态色。
shader_type canvas_item;

// 0 为枪灰分件，1 为迷彩底色，2 为迷彩叶片，3 为带面光的枪灰头部。
uniform int palette = 0;
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

// 柔边光斑或色块。偏转椭圆和叶片的弧线走向一致。
float oval(vec2 uv, vec2 center, vec2 radius, float feather) {
	return 1.0 - smoothstep(feather, 1.0, length((uv - center) / radius));
}

// 深蓝灰阴影、冷钢面光和原贴图最亮的抛光点共用一条色阶。
vec3 gunmetal(vec3 source) {
	float value = dot(source, vec3(0.36, 0.60, 0.04));
	vec3 rgb = mix(vec3(0.021, 0.037, 0.047), vec3(0.14, 0.21, 0.25),
		smoothstep(0.035, 0.52, value));
	rgb = mix(rgb, vec3(0.47, 0.59, 0.64), smoothstep(0.49, 0.94, value));
	float glint = smoothstep(0.26, 0.94, source.b) * smoothstep(0.72, 0.96, value);
	return mix(rgb, vec3(0.84, 0.91, 0.89), glint * 0.93);
}

// 在头部左上保留原画的高光方向，用偏斜的冷反光拉出弧度。
vec3 face_light(vec3 rgb, vec3 source, vec2 uv) {
	vec2 sheen_uv = vec2(uv.x + 0.49 * uv.y, uv.y - 0.27 * uv.x);
	float soft_light = oval(sheen_uv, vec2(0.38, 0.14), vec2(0.27, 0.22), 0.05);
	float bright_edge = oval(sheen_uv, vec2(0.29, 0.19), vec2(0.14, 0.18), 0.12);
	float face_area = smoothstep(0.22, 0.75, source.g);
	rgb = mix(rgb, vec3(0.59, 0.72, 0.75), soft_light * face_area * 0.34);
	rgb += vec3(0.115, 0.107, 0.09) * bright_edge * face_area;
	// 下颌接收茎叶的冷绿反光，保留一条有分量的暗轮廓。
	float bounce = oval(uv, vec2(0.36, 0.79), vec2(0.34, 0.15), 0.0);
	return rgb + vec3(0.02, 0.051, 0.038) * bounce * face_area;
}

// 先保留茎叶原画的亮边和凹面，再叠加少量大块林地色。
vec3 woodland(float green, vec2 uv, bool mottled) {
	float light = smoothstep(0.06, 0.64, green);
	vec3 rgb = mix(vec3(0.026, 0.047, 0.022), vec3(0.28, 0.40, 0.21), light);
	rgb = mix(rgb, vec3(0.62, 0.67, 0.35), smoothstep(0.56, 1.0, green));
	if (mottled) {
		vec2 shaped_uv = vec2(uv.x + 0.052 * sin(9.0 * uv.y + uv.x * 3.0),
			uv.y + 0.075 * sin(11.0 * uv.x));
		float forest = max(oval(shaped_uv, vec2(0.17, 0.50), vec2(0.17, 0.18), 0.64),
			oval(shaped_uv, vec2(0.28, 0.66), vec2(0.19, 0.11), 0.63));
		float olive = max(oval(shaped_uv, vec2(0.78, 0.36), vec2(0.16, 0.17), 0.67),
			oval(shaped_uv, vec2(0.66, 0.49), vec2(0.12, 0.12), 0.56));
		rgb *= mix(vec3(1.0), vec3(0.69, 0.85, 0.81), forest * light);
		rgb *= mix(vec3(1.0), vec3(1.28, 1.05, 0.77), olive * light);
	}
	return rgb;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 rgb;
	if (palette == 0 || palette == 3) {
		rgb = gunmetal(source.rgb);
		if (palette == 3) {
			rgb = face_light(rgb, source.rgb, UV);
		}
	} else {
		rgb = woodland(source.g, UV, palette == 2);
	}
	COLOR = vec4(rgb, source.a) * sprite_tint;
}
