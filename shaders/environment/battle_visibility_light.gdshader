shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform float edge_margin = 1.09;
uniform float footprint_feather = 0.112;
uniform float warm_radiance_scale = 1.0;
// 参与棋盘判定的暖灯可单独提高画面亮度，入射覆盖率仍由原光强计算。
uniform float gameplay_warm_radiance_multiplier = 1.0;
uniform sampler2D shadow_mask : filter_linear, repeat_disable;
uniform vec2 shadow_grid = vec2(4.0);
uniform float shadow_tile_size = 96.0;
varying flat vec4 light_data;
varying flat vec4 footprint;
varying vec2 ground_stamp;

void vertex() {
	light_data = INSTANCE_CUSTOM; // 灯片轮廓、边界偏移、局部遮挡地址与强度。
	footprint = COLOR; // 红晕用实例颜色传递世界范围在灯片上的四条边。
	// QuadMesh 纹理的纵轴与地面 XY 不同。灯格按真实顶点坐标采样。
	ground_stamp = VERTEX * 0.5 + vec2(0.5);
}

void fragment() {
	float profile = light_data.r;
	float warm = step(0.125, profile);
	vec2 offset = (UV * 2.0 - 1.0) * edge_margin;
	float radius = length(offset);
	// 交错的宽暗区只扰动光缘，中心留给实体轮廓与投影。
	float seed = light_data.g * TAU;
	float ripple = sin(dot(offset, vec2(4.6, 7.0)) + seed)
		* sin(dot(offset, vec2(7.1, -3.3)) - seed);
	float edge = 1.0 + (0.053 * ripple - 0.034) * smoothstep(0.26, 0.77, radius);
	float distance_to_light = radius / edge;
	float falloff = exp2(-mix(6.2, 3.8, warm) * distance_to_light * distance_to_light);
	float edge_fade = 1.0 - smoothstep(0.25, 1.0, distance_to_light);
	float coverage = light_data.a * falloff * edge_fade * (1.0 - (0.14 - 0.10 * ripple) * smoothstep(0.15, 0.73, radius));
	float absorbing = 0.0;
	if (profile > 0.25 && profile < 0.875) {
		vec2 margin = min(ground_stamp - footprint.xy, footprint.zw - ground_stamp);
		vec2 feather = smoothstep(vec2(0.0), vec2(footprint_feather), margin);
		coverage *= feather.x * feather.y;
		absorbing = step(0.625, profile);
		// 撞地的余光被宽缓地推向外围，中心留有底光。
		float spread = clamp((profile - 0.375) / 0.20, 0.0, 1.0) * (1.0 - absorbing);
		coverage *= 1.0 - spread * 0.53 * (1.0 - smoothstep(0.10, 0.54, distance_to_light));
	}
	float occlusion = 0.0;
	float slot = floor(0.5 + light_data.b * 255.0) - 1.0;
	if (slot >= 0.0 && coverage > 0.0) {
		vec2 cell = vec2(mod(slot, shadow_grid.x), floor(slot / shadow_grid.x));
		vec2 sample_px = cell * shadow_tile_size + 1.0 + ground_stamp * (shadow_tile_size - 2.0);
		occlusion = texture(shadow_mask, sample_px / (shadow_grid * shadow_tile_size)).r;
	}
	// 普通暖灯只占部分显示范围。传送白灯保留剩余亮度，仍销去自己被遮挡的份额。
	float standard_warm = step(0.875, profile) * (1.0 - step(0.984375, profile));
	float gameplay_warm = step(0.9375, profile) * standard_warm; // 路灯花的实例档位。
	float lantern = warm * coverage * mix(1.0, warm_radiance_scale, standard_warm);
	lantern *= mix(1.0, gameplay_warm_radiance_multiplier, gameplay_warm);
	// Alpha 保留原入射权重。挡灯只扣这盏灯在 B 的份额，G 和其他灯的份额不变。
	COLOR = vec4(lantern, (1.0 - warm + absorbing) * coverage, lantern * (1.0 - occlusion), coverage);
}
