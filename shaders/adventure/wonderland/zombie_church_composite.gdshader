shader_type canvas_item;
render_mode unshaded, blend_disabled;

// 捕获下层战斗世界，独立卡槽和菜单在合成之后绘制。
uniform sampler2D world_texture : hint_screen_texture, filter_linear, repeat_disable;
// R 是未遮挡的暖光和白光，G 是指针光，B 是暖光和白光各扣除自身遮挡后的总量。
uniform sampler2D light_field : filter_linear, repeat_disable;
uniform float warm_radiance_scale = 1.0;
// 独立沿用同一投影遮罩。G 表示吸收造成的短时暖光衰减，B 表示遮挡后的红光。
uniform sampler2D red_light_field : filter_linear, repeat_disable;
uniform bool has_red_light = false;
uniform float ambient : hint_range(0.0, 1.0) = 1.0;
// 本帧可带余热的屏幕矩形。只有真实地面写入 Alpha 缺口，角色照常合成并遮住它。
uniform vec4 residual_bounds = vec4(0.0);
// 烛光恢复前收去残光，给原画结构留出一次完全不可见的换样。
uniform float reveal_strength : hint_range(0.0, 1.0) = 1.0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const vec3 RED_TINT = vec3(1.0, 0.26, 0.17);
const float LANTERN_EXPOSURE = 0.255;
const float RED_LIGHT_MULTIPLIER = 2.0;

void fragment() {
	vec2 reveal = vec2(0.0); // 常亮和复光间隙都无需采样光场。
	float red_reveal = 0.0;
	if (ambient < 1.0 && reveal_strength > 0.0) {
		vec3 field = texture(light_field, SCREEN_UV).rgb;
		reveal = vec2(field.b / warm_radiance_scale, field.g) * reveal_strength;
		if (has_red_light) {
			vec3 red = texture(red_light_field, SCREEN_UV).rgb;
			red_reveal = red.b * reveal_strength;
			reveal.r *= 1.0 - 0.27 * red.g * reveal_strength;
		}
	}
	float visibility = clamp(max(max(reveal.r, reveal.g), red_reveal), 0.0, 1.0);
	bool may_have_heat = all(greaterThan(SCREEN_UV, residual_bounds.xy))
		&& all(lessThan(SCREEN_UV, residual_bounds.zw));
	vec3 scene_color = vec3(0.0); // 无覆盖时直接输出不透明纯黑。
	if (ambient > 0.0 || visibility > 0.0 || may_have_heat) {
		vec4 world_pixel = textureLod(world_texture, SCREEN_UV, 0.0);
		vec3 world = world_pixel.rgb;
		float luma = dot(world, LUMA);
		scene_color = mix(vec3(luma), world, 0.87) * ambient;
		if (visibility > 0.0) {
			float color_keep = smoothstep(0.46, 0.92, reveal.r);
			float contrast = mix(0.48, 0.70, visibility); // 光缘中间调收窄，细纹随反差减弱。
			float tone = mix(0.38, luma, contrast);
			float toe = smoothstep(0.026, 0.17, luma); // 压住已有的砖缝和接地阴影。
			vec3 tint = mix(vec3(0.95, 0.985, 1.036), vec3(1.04, 0.995, 0.947), color_keep);
			// 额外白光从真实遮罩浮出，擦亮石面和原画的高处。
			float pale_key = smoothstep(1.02, 1.65, reveal.r);
			tint = mix(tint, vec3(1.085, 1.035, 0.93), pale_key);
			vec3 muted = max(vec3(tone) + (world - vec3(luma)) * (0.21 * color_keep), vec3(0.0));
			float exposure = LANTERN_EXPOSURE * reveal.r + 0.153 * reveal.g;
			// 归一色调的亮度，让饱和红色仍有两倍的明暗贡献。
			vec3 red = tone * (RED_TINT / dot(RED_TINT, LUMA)) * (LANTERN_EXPOSURE * RED_LIGHT_MULTIPLIER * red_reveal);
			scene_color += (muted * tint * exposure + red) * (toe * (1.0 - ambient));
		}
		if (may_have_heat) {
			float heat = clamp(1.0 - world_pixel.a, 0.0, 0.73);
			vec3 glow = mix(vec3(0.90, 0.071, 0.029), vec3(1.0, 0.58, 0.27), smoothstep(0.20, 0.53, heat));
			glow = mix(glow, vec3(1.0, 0.88, 0.70), smoothstep(0.55, 0.73, heat));
			// 只加裂隙自身的热量，不提高现有灯的照射范围或显露邻近原画。
			scene_color += glow * heat * mix(1.0, 0.46, ambient);
		}
	}
	COLOR = vec4(scene_color, 1.0);
}
