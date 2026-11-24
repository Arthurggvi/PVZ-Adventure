shader_type canvas_item;
render_mode unshaded, blend_add;

// 以照明矩形左上角为原点的世界像素，分别对齐原画的夕阳和提灯。
uniform vec2 sun_position;
uniform vec2 lantern_position;

// 插值后的局部像素让薄雾、光束和提灯跟随原画。
varying vec2 meadow_position;
// 投影后的夕阳位置使反光沿镜头光轴移动。
varying flat vec2 sun_screen_uv;
// 提灯的明暗由两种缓慢变化的频率叠加。
varying flat float lantern_energy;

void vertex() {
	meadow_position = VERTEX;
	// 日轮和镜头反光使用同一套投影，选卡横移时逐帧对齐。
	vec4 sun_clip = SCREEN_MATRIX * CANVAS_MATRIX * MODEL_MATRIX * vec4(sun_position, 0.0, 1.0);
	sun_screen_uv = sun_clip.xy * 0.5 + 0.5;
	lantern_energy = 0.93 + 0.047 * sin(TIME * 1.43) + 0.023 * sin(TIME * 2.71 + 0.8);
}

// 输入是按两个轴的光斑半径归一化的偏移，三次衰减让椭圆边缘平滑归零。
float soft_glow(vec2 offset) {
	float falloff = max(1.0 - dot(offset, offset), 0.0); // 半径外不再叠光。
	return falloff * falloff * falloff;
}

// [光轴方向、局部偏移、半径] 均在等像素比例的屏幕空间中计算。
vec3 aperture_reflection(vec2 offset, vec2 light_direction, float radius, float angularity, vec3 tint) {
	vec2 local = offset / radius; // 光圈中心到像素的归一化距离。
	vec2 quadrant = abs(local); // 对称六瓣外缘只需比较一个象限。
	float hexagon = max(quadrant.x, dot(quadrant, vec2(0.5, 0.8660254))); // 六叶光圈轮廓。
	float contour = mix(length(quadrant), hexagon, angularity); // 圆润度随反光层次变化。
	float lit_side = smoothstep(-0.68, 0.74, dot(local, light_direction)); // 镜头朝向日轮的一侧更亮。
	float fill_light = 1.0 - smoothstep(0.04, 1.28, contour); // 内部奶油般的散射。
	float rim = 1.0 - smoothstep(0.035, 0.225, abs(contour - 0.87)); // 柔和的不对称亮边。
	float coating = 1.0 - smoothstep(0.018, 0.105, abs(contour - 1.015)); // 外侧一线较冷的镀膜反光。
	return tint * (0.39 * fill_light + rim * mix(0.24, 0.70, lit_side))
		+ vec3(0.56, 0.76, 0.64) * coating * mix(0.25, 0.05, lit_side);
}

// 日轮暖光、贴着地平线的薄雾和从日轮展开的光束共享原画空间。
vec3 daylight(vec2 sunlight) {
	float solar_bloom = soft_glow(sunlight / vec2(150.0, 94.0)); // 日轮近处的亮部。
	float sky_scatter = soft_glow(sunlight / vec2(434.0, 203.0)); // 大范围的蜜色散射。
	float streak = soft_glow(sunlight / vec2(367.0, 11.0)); // 夕阳附近的淡横向眩光。
	float haze_height = 65.0 + 8.0 * sin(sunlight.x * 0.007 - TIME * 0.47); // 远处暖雾随风逐渐起伏。
	float horizon_veil = soft_glow((sunlight - vec2(30.0, haze_height)) / vec2(643.0, 60.0)); // 低处较厚的空气。
	float haze_shift = 46.0 * sin(TIME * 0.26); // 第二层较薄的暖雾缓慢掠过草地。
	float drifting_veil = soft_glow((sunlight - vec2(haze_shift, haze_height + 31.0)) / vec2(518.0, 29.0));
	float meadow_fill = soft_glow((sunlight - vec2(-105.0, 295.0)) / vec2(1005.0, 436.0)); // 草地中心保留暖色。
	vec3 light = vec3(1.0, 0.76, 0.45) * (0.22 * solar_bloom + 0.12 * sky_scatter + 0.075 * streak); // 暖光累积量。
	light += vec3(1.0, 0.85, 0.64) * (0.112 * horizon_veil + 0.046 * drifting_veil + 0.090 * meadow_fill);

	float depth = clamp(sunlight.y, 0.0, 458.0); // 光束往下展开的世界距离。
	float ray_fade = smoothstep(7.0, 67.0, depth) * (1.0 - smoothstep(188.0, 458.0, depth)); // 在草地上逐渐消散。
	float breeze = depth * 0.085 * sin(TIME * 0.63 + depth * 0.012); // 远离日轮后，光束边缘在浮尘里缓缓游动。
	float left_ray = (sunlight.x + 0.73 * depth + breeze) / (21.0 + 0.22 * depth); // 斜过草地的主光束。
	float middle_ray = (sunlight.x + 0.28 * depth - breeze * 0.68) / (15.0 + 0.14 * depth); // 交叠的细光束。
	float right_ray = (sunlight.x - 0.48 * depth + breeze * 0.58) / (24.0 + 0.27 * depth); // 右侧较宽的柔光。
	light += vec3(1.0, 0.80, 0.53) * ray_fade * (
		0.132 * soft_glow(vec2(left_ray, 0.0)) + 0.083 * soft_glow(vec2(middle_ray, 0.0))
		+ 0.088 * soft_glow(vec2(right_ray, 0.0))
	);
	return light;
}

void fragment() {
	vec3 light = daylight(meadow_position - sun_position); // 背景底光与下面的镜头反光共用一次叠加。

	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0); // 保持光圈的实际像素比例。
	vec2 screen_point = (SCREEN_UV - vec2(0.5)) * aspect; // 以镜头中心为原点。
	vec2 optical_axis = (sun_screen_uv - vec2(0.5)) * aspect; // 镜头中心指向日轮的位置。
	vec2 light_direction = optical_axis * inversesqrt(max(dot(optical_axis, optical_axis), 0.0001)); // 安全的单位朝向。
	vec2 sun_edge = min(sun_screen_uv, vec2(1.0) - sun_screen_uv); // 日轮靠近画外时逐步降下反光。
	float lens_visibility = smoothstep(-0.11, 0.10, min(sun_edge.x, sun_edge.y)); // 日轮离开视口后的平缓衰减。
	float lens_angle = clamp(length(optical_axis) * 1.3, 0.0, 1.0); // 横移时反光的大小和亮度随入射角微调。
	// 近处金边、微凉的小反光和远处的杏粉光圈在光轴上错开。
	vec3 flare = aperture_reflection(screen_point - optical_axis * 0.65, light_direction,
		0.068 + 0.018 * lens_angle, 0.27, vec3(1.0, 0.77, 0.43)) * 0.247;
	flare += aperture_reflection(screen_point - optical_axis * 0.22, light_direction,
		0.035, 0.54, vec3(0.77, 0.93, 0.67)) * 0.109;
	flare += aperture_reflection(screen_point + optical_axis * 0.29, -light_direction,
		0.117 + 0.012 * lens_angle, 0.16, vec3(1.0, 0.68, 0.56)) * 0.171;
	flare += aperture_reflection(screen_point + optical_axis * 0.73, -light_direction,
		0.043, 0.30, vec3(1.0, 0.87, 0.60)) * 0.116;
	light += flare * lens_visibility * (0.82 + 0.18 * lens_angle);

	vec2 lantern = meadow_position - lantern_position; // 提灯和帐篷共用原画坐标。
	float wick = soft_glow(lantern / vec2(21.0, 32.0)); // 灯芯内几乎呈白色的亮点。
	float cloth_light = soft_glow((lantern - vec2(5.0, 19.0)) / vec2(70.0, 107.0)); // 近处帐布上暖亮的一圈。
	float ground_light = soft_glow((lantern - vec2(17.0, 50.0)) / vec2(131.0, 165.0)); // 传到地面的低强度暖光。
	light += (vec3(1.0, 0.88, 0.57) * 0.30 * wick
		+ vec3(1.0, 0.67, 0.33) * (0.18 * cloth_light + 0.14 * ground_light)) * lantern_energy;

	float energy = max(light.r, max(light.g, light.b)); // 加法混合使用颜色乘以透明度。
	COLOR = vec4(light / max(energy, 0.0001), energy);
}
