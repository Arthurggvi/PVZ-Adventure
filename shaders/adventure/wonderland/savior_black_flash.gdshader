shader_type canvas_item;
render_mode unshaded, blend_mix;

// 原画抬掌帧的图集与局部像素范围。
uniform sampler2D pose_sheet : filter_linear, repeat_disable;
uniform vec4 pose_source;
uniform vec4 pose_rect;
uniform vec2 flip_axes;
// 灰色余像的显现量与扩散程度。
uniform float imprint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float imprint_age : hint_range(0.0, 1.0) = 0.0;
varying vec2 pose_uv;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void vertex() {
	pose_uv = (VERTEX - pose_rect.xy) / pose_rect.zw;
}

vec2 ink_at(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec2(0.0);
	}
	vec2 atlas_uv = pose_source.xy + mix(uv, vec2(1.0) - uv, flip_axes) * pose_source.zw;
	vec4 ink = texture(pose_sheet, atlas_uv);
	return vec2(ink.a, dot(ink.rgb, LUMA) * ink.a);
}

float blot(vec2 point, vec2 center, vec2 axis) {
	vec2 p = (point - center) * axis;
	return exp2(-dot(p, p));
}

void fragment() {
	// 七点只在原画帧内采样，余像后段边缘变宽并失去细节。
	vec2 blur = mix(3.5, 13.0, imprint_age) / pose_rect.zw;
	vec2 warp = vec2(sin(pose_uv.y * 18.0 + pose_uv.x * 7.0), sin(pose_uv.x * 17.0 - pose_uv.y * 6.0));
	vec2 uv = pose_uv + warp * blur * 0.20;
	vec2 ghost = ink_at(uv) * 0.28;
	ghost += 0.12 * (ink_at(uv + blur * vec2(1.0, 0.0)) + ink_at(uv - blur * vec2(1.0, 0.0))
		+ ink_at(uv + blur * vec2(0.45, 0.85)) + ink_at(uv - blur * vec2(0.45, 0.85))
		+ ink_at(uv + blur * vec2(-0.45, 0.85)) + ink_at(uv - blur * vec2(-0.45, 0.85)));
	// 记住刚才掌心与面部的亮部，暗袍与光环只留下较弱的断续轮廓。
	float cast = blot(uv, vec2(0.41, 0.38), vec2(2.6, 2.7));
	float edge = 0.43 * ghost.x + 0.82 * ghost.y;
	float patches = 0.70 * blot(uv, vec2(0.27, 0.34), vec2(5.7, 8.7))
		+ 0.30 * blot(uv, vec2(0.52, 0.22), vec2(6.5, 9.0));
	float density = edge * (0.05 + 0.19 * cast) + 0.038 * patches;
	COLOR = vec4(0.61, 0.61, 0.62, density * imprint_strength);
}
