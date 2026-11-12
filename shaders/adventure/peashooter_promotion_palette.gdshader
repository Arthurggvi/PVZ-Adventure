// 对原动画分件着色，保留纹理透明度和父节点的状态色。
shader_type canvas_item;

// 0 为枪灰，1 为迷彩底色，2 为带色块的大叶片。
uniform int palette = 0;
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

// 用少量相交的椭圆构成柔边色块，避免在战斗尺寸下形成碎纹。
float patch(vec2 uv, vec2 center, vec2 radius) {
	return 1.0 - smoothstep(0.77, 1.05, length((uv - center) / radius));
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 rgb;
	if (palette == 0) {
		// 使用原绘制的明暗，让头顶高光和下颌阴影延续到嘴部和眨眼帧。
		float value = dot(source.rgb, vec3(0.39, 0.59, 0.02));
		rgb = mix(vec3(0.035, 0.057, 0.062), vec3(0.37, 0.44, 0.46),
			smoothstep(0.08, 0.77, value));
		rgb = mix(rgb, vec3(0.69, 0.75, 0.75), smoothstep(0.76, 1.0, value));
	} else {
		// 叶、茎与叶尖用相同底色，维持分件交界处的明暗关系。
		float value = smoothstep(0.10, 0.83, source.g);
		rgb = mix(vec3(0.074, 0.107, 0.061), vec3(0.49, 0.58, 0.30), value);
		if (palette == 2) {
			float dark = max(patch(UV, vec2(0.23, 0.62), vec2(0.20, 0.18)),
				patch(UV, vec2(0.37, 0.67), vec2(0.14, 0.26)));
			float olive = max(patch(UV, vec2(0.75, 0.36), vec2(0.23, 0.19)),
				patch(UV, vec2(0.82, 0.54), vec2(0.13, 0.20)));
			rgb *= mix(vec3(1.0), vec3(0.72, 0.82, 0.76), dark * value);
			rgb *= mix(vec3(1.0), vec3(1.19, 1.07, 0.84), olive * value);
		}
	}
	COLOR = vec4(rgb, source.a) * sprite_tint;
}
