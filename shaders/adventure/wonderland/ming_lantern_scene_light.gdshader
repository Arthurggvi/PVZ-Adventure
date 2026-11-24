shader_type canvas_item;
render_mode unshaded, blend_disabled;

// 实体之后、界面与环境柔光之前读取战场本身的颜色。
uniform sampler2D screen_image : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D irradiance : filter_linear, repeat_disable;
uniform vec2 world_origin = vec2(0.0);
uniform vec2 world_x = vec2(1066.0, 0.0);
uniform vec2 world_y = vec2(0.0, 600.0);
uniform float clock_seconds = 0.0;

// 两组弯曲的水纹交汇时形成狭窄焦散，屏幕抖动时仍留在水面上。
float caustics(vec2 point) {
	vec2 p = point * vec2(0.043, 0.068);
	vec2 flow = vec2(sin(p.y * 1.42 + clock_seconds * 0.95), cos(p.x * 1.38 - clock_seconds * 0.74));
	float folds = sin(p.x * 1.27 + flow.x * 1.13 + clock_seconds * 0.55)
		+ sin(p.y * 1.18 + flow.y * 1.06 - clock_seconds * 0.79)
		+ 0.37 * sin((p.x + p.y) * 1.47 - clock_seconds * 0.63);
	float strands = 1.0 - smoothstep(0.025, 0.22, abs(folds));
	return strands * strands * (0.47 + 0.53 * flow.x * flow.x);
}

void fragment() {
	vec4 source = texture(screen_image, SCREEN_UV);
	vec3 light = texture(irradiance, SCREEN_UV).rgb;
	float power = max(light.r, max(light.g, light.b));

	// 现有的手绘凸起和边缘以颜色梯度估计表面细节，迎光侧比背光侧亮。
	float detail = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec2 from_light = vec2(dFdx(power), dFdy(power));
	vec2 ridges = vec2(dFdx(detail), dFdy(detail)) / max(1066.0 * SCREEN_PIXEL_SIZE.x, 0.1);
	vec2 incidence = from_light * inversesqrt(dot(from_light, from_light) + 0.0000018);
	float relief = clamp(0.92 + dot(ridges, incidence) * 9.0, 0.62, 1.46);

	COLOR = source;
	if (power > 0.0035) {
		vec3 linear_color = source.rgb * source.rgb;
		vec3 incident = mix(vec3(power), light, 0.69);
		vec3 reflected = linear_color * incident * (4.5 * relief);

		// 低亮像素有少量水体散射，冷色背景额外承接焦散。木纹与叶片仍靠本色反射。
		vec2 point = world_origin + world_x * SCREEN_UV.x + world_y * SCREEN_UV.y;
		float water = smoothstep(0.018, 0.135, source.b - source.r) * (1.0 - smoothstep(0.29, 0.68, detail));
		float shimmer = caustics(point);
		reflected += light * (0.006 + detail * 0.024 + water * (0.011 + 0.046 * shimmer)) * relief;

		// 高亮余量平滑收敛，同格多个技能叠光时仍看得见原画纹理。
		vec3 headroom = max(vec3(0.004), vec3(1.0) - linear_color);
		vec3 lit = linear_color + headroom * (vec3(1.0) - exp(-reflected / headroom));
		COLOR = vec4(sqrt(clamp(lit, vec3(0.0), vec3(1.0))), source.a);
	}
}
