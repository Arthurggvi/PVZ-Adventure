shader_type canvas_item;
render_mode blend_mix;

// 共用底图：独立泳池贴图或冒险战场整图。
uniform sampler2D surface_texture : source_color, filter_linear, repeat_disable;
// uv_rect.xy 为局部水域在源图上的左上角，zw 为宽高。
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
// 时间由控制器按游戏帧推进，暂停时自动停止。
uniform float water_time = 0.0;
uniform float wave_speed = 0.3;
uniform float ripple_strength = 0.0018;
uniform float wave_density = 1.0;
uniform float caustic_strength = 0.06;
uniform vec4 water_tint : source_color = vec4(1.0);
uniform float tint_mix = 0.0;
uniform vec4 caustic_tint : source_color = vec4(0.65, 0.88, 0.9, 1.0);
uniform float opacity = 1.0;

void fragment() {
	vec2 local_uv = UV;
	vec2 flow_uv = local_uv * wave_density;
	float phase = water_time * wave_speed;

	float a = sin(flow_uv.y * 51.0 + phase * 2.2 +
		sin(flow_uv.x * 13.0 - phase * 0.6) * 1.4);
	float b = sin(flow_uv.x * 38.0 - phase * 1.55 +
		cos(flow_uv.y * 11.0 + phase * 0.8) * 1.1);
	float c = sin(flow_uv.x * 29.0 + flow_uv.y * 14.0 + phase * 1.1);
	// 消除接缝处位移，始终保持池壁与陆地像素稳定。
	float edge = min(min(local_uv.x, 1.0 - local_uv.x),
		min(local_uv.y, 1.0 - local_uv.y));
	float edge_fade = smoothstep(0.0, 0.055, edge);
	vec2 offset_uv = vec2(a + 0.35 * b, 0.65 * b + 0.35 * c) *
		ripple_strength * edge_fade;
	vec2 sample_local = clamp(local_uv + offset_uv, vec2(0.001), vec2(0.999));
	vec2 sample_atlas = uv_rect.xy + sample_local * uv_rect.zw;
	vec4 base = texture(surface_texture, sample_atlas);

	// 交错、缓慢流动的焦散光纹；由水域配置控制颜色和强度。
	float ca = sin(flow_uv.x * 69.0 + flow_uv.y * 15.0 + phase * 1.35 +
		sin(flow_uv.y * 21.0 - phase) * 1.5);
	float cb = cos(flow_uv.x * 47.0 - flow_uv.y * 22.0 - phase * 0.9);
	// 两条宽窄不同的流动光脊：避免过度取幂使焦散几乎完全不可见。
	float ridge_a = pow(max(ca, 0.0), 3.0);
	float ridge_b = pow(max(cb, 0.0), 3.0);
	float light_lines = ridge_a * (0.34 + 0.66 * ridge_b);
	vec3 color = mix(base.rgb, base.rgb * water_tint.rgb, tint_mix);
	color += caustic_tint.rgb * light_lines * caustic_strength * edge_fade;
	COLOR = vec4(color, base.a * opacity);
}
