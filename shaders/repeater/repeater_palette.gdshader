// 原版弹体轮廓保持不变，只重映射明暗和流动的材质细节。
shader_type canvas_item;
render_mode unshaded;

// 同一弹种的暗部、中间色和高光；每枚弹体使用独立材质。
uniform vec4 shadow_color : source_color = vec4(0.04, 0.04, 0.08, 1.0);
uniform vec4 body_color : source_color = vec4(0.25, 0.32, 0.65, 1.0);
uniform vec4 light_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
// 外部战斗时钟推进，暂停时不使用不受控的 TIME。
uniform float effect_seconds = 0.0;
// 0 为普通配色，1 为星点，2 为黑金流光，3 为焰色。
uniform int detail_mode = 0;
// 不同弹体的闪烁错相，不改变游戏随机序列。
uniform float phase = 0.0;
// 深色星空弹降低球面亮度，星点亮度独立保留。
uniform float surface_brightness = 1.0;
// 饱和红火焰、漩涡按最大通道取明度；豌豆和星弹保留原线稿对比。
uniform bool red_source = false;
// 保留原画布颜色，包括父级透明度。
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// 稳定的二维散列只用于材质细节。
float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	// 原漩涡是饱和红图，最大色通道才能保留其明暗纹理而不压成一团黑。
	float luminance = red_source ? max(source.r, max(source.g, source.b)) : dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 mapped = mix(shadow_color.rgb, body_color.rgb, smoothstep(0.06, 0.72, luminance));
	mapped = mix(mapped, light_color.rgb, pow(smoothstep(0.42, 1.0, luminance), 3.0) * 0.82);
	mapped *= surface_brightness;
	vec2 centered = UV - vec2(0.5);
	if (detail_mode == 1) {
		vec2 cells = floor(UV * 9.0);
		vec2 local = fract(UV * 9.0) - vec2(0.5);
		float seed = hash_cell(cells);
		float pin = exp(-dot(local, local) * 95.0) * step(0.73, seed);
		float twinkle = pow(0.5 + 0.5 * sin(effect_seconds * (3.0 + seed * 4.0) + seed * 40.0 + phase), 4.0);
		mapped += light_color.rgb * pin * (0.2 + twinkle * 1.5);
	}
	if (detail_mode == 2) {
		float angle = atan(centered.y, centered.x);
		float sweep = pow(0.5 + 0.5 * sin(angle * 2.0 - effect_seconds * 3.2 + phase), 12.0);
		float rim = smoothstep(0.20, 0.38, length(centered)) * (1.0 - smoothstep(0.43, 0.56, length(centered)));
		float vein = pow(0.5 + 0.5 * sin(UV.x * 32.0 + UV.y * 18.0 + sin(UV.y * 14.0) * 2.0), 24.0);
		mapped = mix(mapped * 0.26, light_color.rgb, clamp(rim * (0.36 + sweep * 0.82) + vein * 0.3, 0.0, 0.94));
	}
	if (detail_mode == 3) {
		float ember = 0.87 + 0.13 * sin(effect_seconds * 13.0 + UV.x * 15.0 + phase);
		mapped *= ember;
	}
	COLOR = vec4(mapped, source.a) * tint;
}
