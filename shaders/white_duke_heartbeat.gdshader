shader_type canvas_item;
render_mode unshaded, blend_disabled;

// 刚完成天气镜头合成的战场画面。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// 从触发到消退的归一化时间。
uniform float progress : hint_range(0.0, 1.0) = 1.0;
// 与本次召唤聚光灯同步的颜色。
uniform vec4 pulse_color : source_color = vec4(1.0);

void fragment() {
	// 主跳快速撞击，回弹较弱，之后逐渐恢复画面。
	float impact = smoothstep(0.0, 0.13, progress) * (1.0 - smoothstep(0.13, 0.39, progress));
	float rebound = smoothstep(0.24, 0.37, progress) * (1.0 - smoothstep(0.37, 0.72, progress));
	float beat = impact + 0.45 * rebound;

	// 收缩采样范围模拟推镜，并给位移留出边缘余量。
	vec2 centered = SCREEN_UV - vec2(0.5);
	vec2 shake = vec2(sin(progress * 41.0), sin(progress * 49.0 + 0.7)) * vec2(0.007, 0.005);
	vec2 uv = vec2(0.5) + centered * (1.0 - 0.026 * beat) + shake * beat;
	// 三个通道从略有差异的位置取样，让轮廓随震颤产生短暂色散。
	vec2 split = (centered * 0.012 + vec2(0.003, -0.001)) * beat;
	vec3 color = vec3(texture(screen_texture, uv + split).r,
		texture(screen_texture, uv).g, texture(screen_texture, uv - split).b);

	// 同色光沿斜线掠过，余色比震颤多停留一瞬。
	float sweep_center = mix(-0.2, 1.4, progress);
	float sweep = 1.0 - smoothstep(0.03, 0.40, abs(SCREEN_UV.x + 0.18 * SCREEN_UV.y - sweep_center));
	float fade = smoothstep(0.0, 0.13, progress) * (1.0 - smoothstep(0.57, 1.0, progress));
	color = mix(color, color * 0.80 + pulse_color.rgb * 0.30, 0.36 * beat + 0.42 * sweep * fade);
	COLOR = vec4(color, 1.0);
}
