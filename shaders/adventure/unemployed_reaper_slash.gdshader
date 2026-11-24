shader_type canvas_item;
render_mode unshaded;

// 斩击图集的帧格由同一落斩时间轴选取。
uniform vec2 frame_tile = vec2(0.0);
// x 将外接矩形横坐标转回刀宽，y 表示刀口从一端到另一端的水平偏移。
uniform vec2 blade_mapping = vec2(1.0, 0.0);
// 地面层可被单位遮挡，只画预兆、震波和留在地上的裂纹。
uniform bool ground_pass = false;
// 蓄势进度及距真正落斩的实际秒；负秒数不显示余烬。
uniform float windup = 0.0;
uniform float after_hit = -0.33;

// 用稳定空间种子打散裂痕和火星，避免退场期间逐帧跳动。
float hash(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 4375.83);
}

// 空间噪声在相邻采样之间连续，让退场沿火舌边缘蚀开。
float noise(vec2 point) {
	vec2 cell = floor(point); // 四角共享到相邻的采样网格。
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(point)); // 消除方格边界。
	float top = mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend.x);
	float bottom = mix(hash(cell + vec2(0.0, 1.0)), hash(cell + 1.0), blend.x);
	return mix(top, bottom, blend.y);
}

// 前景只保留掠过角色的刀身与落地一瞬的高光。
vec4 blade_color(sampler2D atlas, vec2 p, float cross_blade, float age, float landed) {
	float dissolve = smoothstep(0.43, 1.20, age); // 前景比地面先退，让单位轮廓尽快露出。
	vec2 blade_space = vec2(0.79 + cross_blade * 0.82 + dissolve * 0.017, 0.012 + p.y * 1.26); // 横向展开亮核，纵向覆盖首尾行。
	vec2 art = blade_space.x * vec2(0.6480, 0.7616) + blade_space.y * vec2(-0.7616, 0.6480); // 按原图集峰值刀口的轴线采样。
	vec2 atlas_uv = (frame_tile * 260.0 + 2.5 + clamp(art, 0.0, 1.0) * 255.0) / vec2(1560.0, 1040.0); // 像素中心采样保留帧间透明缝。
	vec4 blade = texture(atlas, atlas_uv);
	vec2 border = min(art, 1.0 - art); // 软化贴图取样的硬边，首尾行以内保持完整。
	float tips = 1.0 - smoothstep(0.40, 0.499, abs(p.y));
	blade.a *= smoothstep(0.0, 0.014, min(border.x, border.y)) * tips;
	if (dissolve > 0.0) {
		float breakup = noise(vec2(cross_blade, p.y) * vec2(36.0, 64.0) + vec2(age * -0.88, age * 0.92)); // 余焰沿刀口散开。
		blade.a *= smoothstep(dissolve - 0.18, dissolve + 0.12, breakup) * (1.0 - dissolve);
	}
	blade.a *= mix(windup * 0.72, 1.0 - smoothstep(0.20, 1.14, age), landed);
	float flare = exp(-age * 27.0) * landed * tips * (1.0 - smoothstep(0.012, 0.091, abs(cross_blade))); // 只让银紫亮核在落地时盖过角色。
	float alpha = blade.a + flare * 0.66 * (1.0 - blade.a);
	vec3 core = vec3(0.97, 0.78, 1.0);
	vec3 color = mix(core, blade.rgb, blade.a / max(0.001, alpha));
	return vec4(mix(color, core, flare * 0.52), alpha);
}

// 用可被角色遮挡的地光衔接落地和熄灭。
vec4 ground_color(vec2 p, float cross_blade, float age, float landed) {
	float along = abs(p.y);
	float extent = 1.0 - smoothstep(0.375, 0.415, along); // 显示整列的边缘，兼顾首尾端淡出。
	float strike_band = (1.0 - smoothstep(0.022, 0.118, abs(cross_blade))) * extent; // 脚下预兆沿同一道斜斩出现。
	float prelight = strike_band * mix(windup * 0.36, (1.0 - smoothstep(0.01, 0.16, age)) * 0.24, landed);
	float fallout = landed * (1.0 - smoothstep(0.62, 1.92, age));
	float edge_in = 0.40 * (1.0 - smoothstep(0.95, 1.92, age)); // 板面裂痕从两端向中央合拢。
	float segment = (p.y + 0.5) * 19.0;
	float segment_id = floor(segment);
	float seam = mix(hash(vec2(segment_id, 3.0)), hash(vec2(segment_id + 1.0, 3.0)), fract(segment)) * 0.044 - 0.022; // 边缘折线沿地面保持稳定。
	float crack_distance = abs(cross_blade - seam);
	float split_end = (1.0 - smoothstep(edge_in, edge_in + 0.024, along)) * fallout;
	float scorch = (1.0 - smoothstep(0.012, 0.056, crack_distance)) * split_end; // 裂缝内是暗底，亮色只在窄边出现。
	float rim_offset = 0.010 + 0.007 * fallout;
	float rim = (1.0 - smoothstep(0.003, 0.012, abs(crack_distance - rim_offset))) * split_end;
	float halo = (1.0 - smoothstep(0.014, 0.098, crack_distance)) * split_end;

	vec2 wave_space = p * vec2(1.25, 3.25); // 压平余震的纵向半径，让它沿地表扩散。
	float wave_age = clamp(age / 0.46, 0.0, 1.0);
	float wave_radius = mix(0.031, 0.50, 1.0 - pow(1.0 - wave_age, 2.0));
	float wave = (1.0 - smoothstep(0.004, 0.032, abs(length(wave_space) - wave_radius))) * (1.0 - wave_age) * landed;

	vec2 ash_grid = (vec2(cross_blade, p.y) + vec2(-0.051, 0.072) * age) * vec2(16.0, 24.0);
	vec2 ash_cell = floor(ash_grid);
	float seed = hash(ash_cell);
	vec2 ash_offset = vec2(seed, hash(ash_cell + 7.0)) * 0.64 + 0.18;
	float ember = (1.0 - smoothstep(0.04, 0.13, length((fract(ash_grid) - ash_offset) * vec2(0.8, 1.3)))) * step(0.65, seed);
	ember *= fallout * smoothstep(0.10, 0.38, age) * (1.0 - smoothstep(0.06, 0.19, abs(cross_blade))) * extent; // 少量散火贴着斜裂口逐渐熄灭。

	float light = max(max(rim * 0.83, ember * 0.68), max(wave * 0.55, halo * 0.27));
	float alpha = max(max(light * 0.71, scorch * 0.66), prelight);
	vec3 base = mix(vec3(0.038, 0.012, 0.066), vec3(0.33, 0.13, 0.53), prelight / max(alpha, 0.001));
	vec3 violet = vec3(0.72, 0.37, 0.98);
	return vec4(mix(base, violet, smoothstep(0.03, 0.75, light)), alpha);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(blade_mapping.x, 1.0); // 以未倾斜的局部带宽为单位。
	float age = max(0.0, after_hit); // 预兆阶段不推进斩后表现。
	float landed = step(0.0, after_hit); // 只有正式落斩才显现余震和裂隙。
	float cross_blade = p.x + p.y * blade_mapping.y; // 实际世界坐标中倾斜 30 度，中央仍经过列中心。
	if (ground_pass) {
		COLOR = ground_color(p, cross_blade, age, landed);
	} else {
		COLOR = blade_color(TEXTURE, p, cross_blade, age, landed);
	}
}
