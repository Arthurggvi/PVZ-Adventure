shader_type canvas_item;
render_mode unshaded;

// 残像只显薄边与部分暗面，避免叠出多个完整的不透明马身。
uniform bool echo = false;
// 抬蹄与撞击时沿原始血马图的高亮区域加温。
uniform float heat : hint_range(0.0, 1.0) = 0.0;
// 当前踏步相位，用脚部的局部弯折保留上半身稳定。
uniform float stride : hint_range(-1.0, 1.0) = 0.0;
// Sprite2D 的透明度独立于原始贴图的轮廓。
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	// 踏步只变形原图下三分之一，上半身重心和长枪保持稳定。
	float hoof = smoothstep(0.63, 0.98, UV.y);
	vec2 sample_uv = UV + vec2(stride * hoof * (UV.x - 0.46) * 0.096, 0.0);
	// 在透明边缘采样，建立与原始尖角一致的逆光轮廓。
	vec2 texel = TEXTURE_PIXEL_SIZE * (echo ? 8.0 : 4.5);
	vec4 ink = texture(TEXTURE, sample_uv);
	float fringe = max(texture(TEXTURE, sample_uv + vec2(texel.x, 0.0)).a,
		texture(TEXTURE, sample_uv - vec2(texel.x, 0.0)).a);
	fringe = max(fringe, texture(TEXTURE, sample_uv + vec2(0.0, texel.y)).a);
	fringe = max(fringe, texture(TEXTURE, sample_uv - vec2(0.0, texel.y)).a);
	float rim = max(0.0, fringe - ink.a);
	float red = smoothstep(0.14, 0.89, ink.r);
	if (echo) {
		// 留下暗面形状和偶尔掠过的高光，内部亮度保持低于真身。
		float accent = smoothstep(0.20, 0.76, red + (1.0 - UV.y) * 0.16);
		vec3 color = mix(vec3(0.22, 0.012, 0.045), vec3(0.92, 0.13, 0.25), accent);
		COLOR = vec4(mix(color, vec3(1.0, 0.29, 0.33), rim),
			(ink.a * (0.15 + red * 0.43) + rim * 0.86) * tint.a);
	} else {
		// 原图的暗部保留深酒红，亮部补一层受力时的橘红反光。
		vec3 body = mix(ink.rgb * vec3(1.15, 0.93, 0.98) + vec3(0.052, 0.006, 0.012),
			vec3(1.0, 0.37, 0.24), red * (0.25 + heat * 0.56));
		vec3 outline = mix(vec3(0.74, 0.018, 0.12), vec3(1.0, 0.58, 0.30), heat);
		COLOR = vec4(mix(body, outline, rim), max(ink.a, rim * (0.52 + heat * 0.45)) * tint.a);
	}
}
