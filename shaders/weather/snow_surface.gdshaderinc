// 数据贴图覆盖完整绘制矩形。与 Sprite2D 的图集 UV 分开，保留原有透明度。
uniform bool snow_surface_enabled = false;
uniform sampler2D snow_state : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D snow_details : hint_default_black, filter_linear, repeat_disable;
uniform vec4 snow_ground_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 snow_contact_clip = vec3(0.0, 0.0, 4.0);
uniform vec4 snow_ambient : source_color = vec4(0.55, 0.66, 0.65, 0.0);
varying vec2 snow_surface_uv;

// 顶点处归一化实际绘制坐标，片元不依赖视口或镜头位置。
vec2 snow_surface_vertex(vec2 vertex) {
	return (vertex - snow_ground_rect.xy) / snow_ground_rect.zw;
}

// 只混合地板颜色。覆雪和压痕的容量读取原图亮度，雪线轮廓由地板材质处理。
vec3 snow_surface_color(vec3 ground, float brightness) {
	if (!snow_surface_enabled || brightness <= 0.22) {
		return ground;
	}
	vec3 state = texture(snow_state, snow_surface_uv).rgb;
	vec2 scar = texture(snow_details, snow_surface_uv).rg;
	float battle = smoothstep(0.0, 3.0, snow_contact_clip.z - dot(snow_contact_clip.xy, snow_surface_uv));
	float land = smoothstep(0.22, 0.57, brightness);
	float drift = 0.86 + 0.10 * sin(snow_surface_uv.x * 41.0 - snow_surface_uv.y * 18.0);
	vec3 loose = mix(ground, vec3(0.77, 0.82, 0.88), state.r * land * drift * 0.36);
	// 轨迹用最大深度合并，抑制被相邻轨迹覆盖到内部的推雪边。
	float furrow = scar.r * 0.31 + state.g * 0.075 + state.b * 0.095;
	float rim = max(0.0, scar.g - scar.r * 0.70) * 0.20;
	vec3 pressed = mix(loose, loose * vec3(0.57, 0.69, 0.82), furrow * 2.0 * battle * land);
	vec3 snow = mix(pressed, vec3(0.86, 0.90, 0.94), rim * battle * land);
	float ambient = min(snow_ambient.a, 1.0) * land * (0.014 + (1.0 - state.r) * 0.019);
	return mix(snow, snow * (0.62 + snow_ambient.rgb * 0.55), ambient);
}
