shader_type canvas_item;

// 轮胎转角（弧度）随底盘实际行程推进，停车时保留当前相位。
uniform float wheel_phase = 0.0;

// 胎面轮廓按归一化前的原素材像素标记。
const float SOURCE_SIZE = 1254.0;
// 三段胎面测量点依次记录 Y、左界、右界。
const vec3 TREAD[37] = {
	vec3(851, 294, 334), vec3(866, 269, 319), vec3(885, 249, 297),
	vec3(910, 234, 279), vec3(937, 224, 265), vec3(962, 220, 261),
	vec3(987, 222, 262), vec3(1010, 225, 264), vec3(1035, 237, 273),
	vec3(1058, 250, 287), vec3(1080, 271, 305), vec3(1093, 292, 323),
	vec3(949, 635, 673), vec3(961, 600, 648), vec3(979, 569, 622),
	vec3(1003, 545, 604), vec3(1030, 530, 585), vec3(1057, 518, 571),
	vec3(1084, 514, 569), vec3(1112, 515, 572), vec3(1140, 527, 581),
	vec3(1167, 540, 594), vec3(1189, 558, 617), vec3(1205, 586, 638),
	vec3(1215, 614, 651),
	vec3(889, 930, 973), vec3(899, 903, 951), vec3(917, 879, 932),
	vec3(942, 860, 913), vec3(968, 848, 898), vec3(995, 845, 891),
	vec3(1021, 842, 890), vec3(1047, 844, 895), vec3(1073, 857, 904),
	vec3(1098, 871, 918), vec3(1120, 892, 939), vec3(1135, 918, 955)
};

// 顶点色留给原本的受伤、冻结、关卡光照和淡入淡出。
varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

// 返回高度 y 处的胎面左右界，first 与 last 是该轮胎在原画轮廓表中的端点。
vec2 tread_edges(float y, int first, int last) {
	vec3 lower = TREAD[first]; // 当前插值段的上端。
	for (int i = first + 1; i <= last; i++) { // 从轮胎顶部沿圆柱可见侧取样。
		vec3 upper = TREAD[i]; // 当前插值段的下端。
		if (y <= upper.x) {
			return mix(lower.yz, upper.yz, (y - lower.x) / (upper.x - lower.x));
		}
		lower = upper;
	}
	return lower.yz;
}

// 用实际轮廓约束圆柱采样，返回采样 UV 与权重，轮胎外沿和车体接缝保持原画位置。
vec3 tread_mapping(vec2 point, int first, int last) {
	float top = TREAD[first].x; // 胎面可见顶端。
	float bottom = TREAD[last].x; // 胎面可见底端。
	if (point.y <= top || point.y >= bottom) {
		return vec3(0.0);
	}
	vec2 edges = tread_edges(point.y, first, last); // 当前行的轮廓。
	float u = (point.x - edges.x) / (edges.y - edges.x); // 胎宽内的横向位置。
	if (u <= 0.03 || u >= 0.97) {
		return vec3(0.0);
	}
	float center = (top + bottom) * 0.5; // 圆柱投影中心。
	float radius = (bottom - top) * 0.5; // 圆柱投影半径。
	float angle = asin(clamp((point.y - center) / radius, -1.0, 1.0)); // 当前行的可见角。
	float sample_angle = mod(angle - wheel_phase + PI * 0.5, PI) - PI * 0.5; // 沿整个可见半周循环。
	float sample_y = center + radius * sin(sample_angle); // 映回原画上的行。
	vec2 sample_edges = tread_edges(sample_y, first, last); // 避免采到宽度不同的车身部分。
	vec2 sample_uv = vec2(mix(sample_edges.x, sample_edges.y, u), sample_y) / SOURCE_SIZE; // 胎面采样坐标。
	float mask = smoothstep(0.03, 0.17, u) * (1.0 - smoothstep(0.83, 0.97, u))
		* smoothstep(0.0, 14.0, point.y - top) * smoothstep(0.0, 14.0, bottom - point.y); // 四周退回原画。
	return vec3(sample_uv, mask);
}

// 将轮毂映回透视压缩前的圆形，返回旋转后螺栓环的采样 UV 与权重。
vec3 hub_mapping(vec2 point, vec2 center, vec2 radius, float tilt) {
	mat2 basis = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt))); // 椭圆轴向。
	vec2 local = (transpose(basis) * (point - center)) / radius; // 轮毂圆形坐标。
	float rho = length(local); // 轮轴到外沿的归一化距离。
	if (rho <= 0.4 || rho >= 0.97) {
		return vec3(0.0);
	}
	float c = cos(wheel_phase); // 反向查找该像素旋转前的素材位置。
	float s = sin(wheel_phase); // 与胎面使用同一轮胎相位。
	vec2 spun = mat2(vec2(c, s), vec2(-s, c)) * local; // 圆形空间内旋转。
	vec2 sample_uv = (center + basis * (spun * radius)) / SOURCE_SIZE; // 复原透视后在原画采样。
	float mask = smoothstep(0.4, 0.52, rho) * (1.0 - smoothstep(0.85, 0.97, rho)); // 只旋转螺栓环。
	return vec3(sample_uv, mask);
}

void fragment() {
	vec4 art = texture(TEXTURE, UV); // 不修改底盘原图的透明轮廓。
	vec2 point = UV * SOURCE_SIZE; // 针对各轮子先做局部范围筛选。
	if (art.a > 0.0 && abs(wheel_phase) > 0.0001) {
		vec3 tread = vec3(0.0); // 胎面采样位置和权重，范围外保留原画。
		vec3 hub = vec3(0.0); // 内侧前、后轮露出螺栓环，远轮没有轮毂采样。
		if (point.x > 210.0 && point.x < 340.0) {
			tread = tread_mapping(point, 0, 11);
		} else if (point.x > 506.0 && point.x < 746.0) {
			tread = tread_mapping(point, 12, 24);
			hub = hub_mapping(point, vec2(676, 1092), vec2(63, 84), radians(10.0));
		} else if (point.x > 834.0 && point.x < 1060.0) {
			tread = tread_mapping(point, 25, 36);
			hub = hub_mapping(point, vec2(989, 1023), vec2(54, 77), radians(9.0));
		}
		if (tread.z > 0.0) {
			art.rgb = mix(art.rgb, texture(TEXTURE, tread.xy).rgb, tread.z);
		}
		if (hub.z > 0.0) {
			art.rgb = mix(art.rgb, texture(TEXTURE, hub.xy).rgb, hub.z);
		}
	}
	COLOR = art * sprite_tint;
}
