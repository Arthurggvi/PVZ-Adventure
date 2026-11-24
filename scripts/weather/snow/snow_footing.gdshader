// 世界脚底的短暗部与不规则薄雪，共用按行批绘制的坡面几何。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 前缘位于本行角色前，暗部落在各行原生影子之后。
uniform bool front_edge = false;
// 带符号的阵风强度决定背风一侧的雪缘断裂。
uniform float wind_breakup = 0.0;
// 接触的世界像素，保持同一位置的雪缘纹形稳定。
varying vec2 world_position;
// 松雪、压实、滚动和权重，来自 CPU 雪面数据。
varying vec4 contact_style;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	contact_style = COLOR;
}

void fragment() {
	float x = UV.x * 2.0 - 1.0; // 横向从左端 -1 到右端 1。
	float roll = contact_style.b; // 滚动压痕使用中间长且近似平坦的触地带。
	float fade = 1.0 - smoothstep(mix(0.12, 0.68, roll), 1.0, abs(x));
	if (front_edge) {
		float ripple = sin(world_position.x * 0.42 + world_position.y * 0.11)
			+ 0.32 * sin(world_position.x * 0.93 - world_position.y * 0.37); // 低幅起伏随实际地块留存。
		float crest = 0.32 + ripple * 0.11 + max(0.0, x * wind_breakup) * 0.15; // 迎风端偏低。
		float edge = smoothstep(crest, crest + 0.19, UV.y) * (1.0 - smoothstep(0.71, 1.0, UV.y));
		float breakup = mix(1.0, smoothstep(-0.95, 0.26, ripple), abs(wind_breakup) * 0.64);
		vec3 snow = mix(vec3(0.63, 0.72, 0.78), vec3(0.87, 0.91, 0.93), contact_style.r); // 地板松雪的冷灰白范围。
		float alpha = edge * fade * breakup * contact_style.a * smoothstep(0.025, 0.54, contact_style.r);
		COLOR = vec4(snow, alpha * mix(0.73, 0.53, contact_style.g));
	} else {
		float core = 1.0 - smoothstep(0.06, 0.50, abs(UV.y - 0.47)); // 局限于鞋底和根部的软暗部。
		float opacity = (0.064 + 0.073 * contact_style.r) * contact_style.a;
		COLOR = vec4(0.22, 0.31, 0.38, fade * core * opacity);
	}
}
