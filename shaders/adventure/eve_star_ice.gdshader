shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D ice_atlas : source_color, filter_linear, repeat_disable; // 十二帧原始星空冰。
uniform vec2 impact_uv = vec2(0.5); // 针尖在 3×3 冰面图案中的实际接触点。
uniform float age = 0.0; // 由战斗时钟提供的落地后秒数。
uniform float opacity = 1.0; // 生命周期的末段消散。
uniform float glint_offset = 0.0; // 各块冰淡入静置后的循环偏移。
uniform bool snow_slope = false; // 雪山的冷白反射和地表霜唇。
varying vec4 open_edges; // 左、右、上、下暴露边；共享的内边保持连续。

void vertex() {
	open_edges = COLOR;
}

// 共用每个槽内的有效图幅，绕开原图中帧与帧之间的透明留白。
vec4 sample_frame(vec2 uv, float frame) {
	vec2 slot = vec2(mod(frame, 4.0), floor(frame / 4.0)); // 帧序号对应的列和行。
	vec2 crop = mix(vec2(0.023, 0.192), vec2(0.980, 0.838), uv); // 全序列共用的紧凑边界。
	vec4 texel = texture(ice_atlas, (slot + crop) / vec2(4.0, 3.0)); // 图片原色和透明度。
	texel.a *= smoothstep(0.010, 0.042, texel.a);
	return vec4(texel.rgb * texel.a, texel.a);
}

// 取稍外于晶面的厚雪轮廓。首帧的边界作稳定底形，内部的星河仍逐帧变化。
float snow_fringe(vec2 plate_uv, float crystal_alpha, float drift) {
	vec2 across = vec2(mix(0.014, 0.024, drift), 0.0); // 横向霜宽和雪坡上的缩短高度采用不同的 UV 比例。
	vec2 down = vec2(0.0, mix(0.022, 0.038, drift));
	float left = sample_frame(clamp(plate_uv - across, 0.0, 1.0), 0.0).a;
	float right = sample_frame(clamp(plate_uv + across, 0.0, 1.0), 0.0).a;
	float top = sample_frame(clamp(plate_uv - down, 0.0, 1.0), 0.0).a;
	float bottom = sample_frame(clamp(plate_uv + down, 0.0, 1.0), 0.0).a;
	float envelope = max(max(left, right), max(top, bottom));
	return smoothstep(0.02, 0.60, max(0.0, envelope - crystal_alpha));
}

void fragment() {
	vec2 tile_uv = fract(UV * 3.0); // 当前格内的归一坐标，连续图案仍使用整块 UV。
	vec4 edge_distance = vec4(tile_uv.x, 1.0 - tile_uv.x, tile_uv.y, 1.0 - tile_uv.y); // 到四边的距离。
	float edge_width = 0.13;
	if (snow_slope) {
		float powder_break = sin(UV.x * 67.0 + UV.y * 46.0) * sin(UV.y * 34.0 - UV.x * 27.0);
		edge_width = 0.16 + 0.040 * powder_break; // 边缘的积雪厚薄不齐，内边仍连贯。
	}
	vec4 edge_fade = mix(vec4(1.0), smoothstep(vec4(0.0), vec4(edge_width), edge_distance), open_edges);
	float clip_alpha = min(min(edge_fade.x, edge_fade.y), min(edge_fade.z, edge_fade.w)); // 在实际绘制轮廓的开边淡化。

	float phase = mod(max(0.0, age - 0.16) * (10.6 + glint_offset * 1.8), 12.0); // 保证从第零帧凝起，再循环十二帧。
	float frame = floor(phase); // 当前帧。
	float blend = smoothstep(0.0, 1.0, fract(phase)); // 临帧以预乘颜色混合，星芒不会跳。
	vec2 plate_scale = snow_slope ? vec2(1.047, 1.15) : vec2(1.0, 1.19); // 雪山边缘多留一点横向积霜余量。
	vec2 plate_uv = (UV - 0.5) * plate_scale + 0.5; // 冰纹仍沿投影后的整块地面铺开。
	vec2 atlas_uv = clamp(plate_uv, vec2(0.0), vec2(1.0)); // 防止相邻帧的纹理渗进延伸的霜层。
	float plate_fade = smoothstep(0.0, 0.025, plate_uv.y) * (1.0 - smoothstep(0.975, 1.0, plate_uv.y)); // 冰板上下边与霜融合。
	if (snow_slope) {
		plate_fade *= smoothstep(0.0, 0.021, plate_uv.x) * (1.0 - smoothstep(0.979, 1.0, plate_uv.x));
	}
	vec4 ice = mix(sample_frame(atlas_uv, frame), sample_frame(atlas_uv, mod(frame + 1.0, 12.0)), blend) * plate_fade; // 还原逐帧亮暗。
	vec3 ice_rgb = ice.rgb / max(ice.a, 0.001); // 用于后续光色的非预乘颜色。

	vec2 delta = UV - impact_uv; // 结冰以真正触地点为中心蔓延。
	float ground_dist = length(delta * vec2(1.02, 0.88)); // 贴地脉冲略微压扁。
	float drift = sin(UV.x * 45.0 + UV.y * 19.0) * sin(UV.y * 39.0 - UV.x * 10.0); // 晶缘的小尺度扰动。
	float growth = 1.0 - pow(1.0 - clamp(age / 0.29, 0.0, 1.0), 1.6); // 前半段推进快，末端合拢。
	float freeze_radius = mix(0.052, 1.10, growth); // 首帧就有实心冰核。
	float solid = 1.0 - smoothstep(freeze_radius - 0.049, freeze_radius + 0.026, ground_dist + drift * 0.019); // 结晶前缘。
	float pulse_radius = mix(0.07, 0.71, clamp(age / 0.34, 0.0, 1.0)); // 沿地板推开的一道冰雾。
	float pulse = exp(-abs(ground_dist - pulse_radius) * 33.0) * (1.0 - smoothstep(0.07, 0.36, age)); // 一次性扩散余光。
	float core = exp(-ground_dist * ground_dist * 165.0) * (1.0 - smoothstep(0.0, 0.135, age)); // 针尖和初生冰之间的交接亮斑。
	vec2 footprint = abs(UV - 0.5) * 1.89; // 按棋盘坐标扩散到余下的有效格。
	float veil = (1.0 - smoothstep(0.50, 0.95, max(footprint.x, footprint.y) + drift * 0.036)) * 0.19 * solid; // 铺满时留一层薄霜。
	float mist = veil + 0.16 * pulse + 0.36 * core; // 半透明贴地光，避开角色前景。
	float texture_alpha = ice.a * solid * 0.88; // 星图保留原色，稍透出地表。
	vec3 fog = mix(vec3(0.28, 0.56, 0.76), vec3(0.55, 0.84, 0.99), min(1.0, pulse + core)); // 亮雾最终沉为蓝色薄霜。
	if (snow_slope) {
		float brightness = clamp(dot(ice_rgb, vec3(0.23, 0.57, 0.20)), 0.0, 1.0);
		float frost = snow_fringe(plate_uv, ice.a, drift * 0.5 + 0.5);
		float powder = frost * (0.23 + 0.09 * drift) * solid;
		vec3 snow_reflection = mix(vec3(0.32, 0.52, 0.72), vec3(0.82, 0.93, 1.0), brightness);
		ice_rgb = mix(ice_rgb, snow_reflection, 0.23 + 0.12 * frost); // 亮星仍清楚，冰底接收天光。
		texture_alpha *= mix(0.75, 0.97, smoothstep(0.15, 0.81, brightness)); // 低亮区域能看清底下的雪面。
		mist = veil * 0.69 + 0.15 * pulse + 0.33 * core + powder;
		fog = mix(vec3(0.61, 0.77, 0.89), vec3(0.81, 0.92, 0.99), frost);
	}
	float alpha = texture_alpha + mist * (1.0 - texture_alpha); // 贴纹与冰气合成同一网格。
	ice_rgb += vec3(0.28, 0.32, 0.35) * min(1.0, pulse + core);
	vec3 color = mix(fog, ice_rgb, texture_alpha / max(alpha, 0.001)); // 薄霜和星图共用柔边。
	float thaw = mix(1.0, 1.0 - smoothstep(0.18, 0.69, ground_dist), 0.48 * (1.0 - opacity)); // 消退时先松开外缘。
	COLOR = vec4(color, alpha * clip_alpha * opacity * thaw);
}
