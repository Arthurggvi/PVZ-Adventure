// 船上的布料共用原画色层。固定遮挡、折波和背风剪影在各自的局部窗口合成。
uniform sampler2D cloth_atlas : source_color, filter_linear, repeat_disable;
// 各挂点独立累积的折波相位与当前风力，按船首、中央、船尾排列。
uniform vec3 ribbon_phase = vec3(0.0);
uniform vec3 ribbon_wind = vec3(0.0);
// 中央蓝旗、右侧蓝旗、船首旗尾、船尾旗尾。
uniform vec4 pennant_phase = vec4(0.0);
uniform vec4 pennant_wind = vec4(0.0);
// 船尾护栏的小旗的相位和风力。
uniform vec2 rail_pennant = vec2(0.0);
// 沿用关卡质量和减弱动效开关。
uniform float cloth_amount = 1.0;
// 稳态空速造成的平均张力。折波相位和局部阵风仍各自更新。
uniform float cruise_tension = 0.0;

const vec2 CLOTH_SIZE = vec2(800.0, 312.0);
// 原上层三块布及从干净空域分出的其余自由端。XY 为母图坐标，ZW 为原布片尺寸。
const vec4 BOW_RIBBON = vec4(173.0, 8.0, 380.0, 87.0);
const vec4 MID_RIBBON = vec4(772.0, 116.0, 228.0, 100.0);
const vec4 AFT_RIBBON = vec4(1146.0, 125.0, 159.0, 116.0);
const vec4 MID_FLAG = vec4(694.0, 92.0, 78.0, 115.0);
const vec4 AFT_FLAG = vec4(1082.0, 126.0, 80.0, 105.0);
const vec4 BOW_HEM = vec4(237.0, 786.0, 78.0, 84.0);
const vec4 AFT_HEM = vec4(1072.0, 757.0, 67.0, 66.0);
const vec4 RAIL_FLAG = vec4(1239.0, 486.0, 69.0, 83.0);

bool cloth_contains(vec2 point, vec4 patch) {
	return all(greaterThanEqual(point, patch.xy)) && all(lessThan(point, patch.xy + patch.zw));
}

// 对单块贴图越界时返回透明，半像素保护让采样不串到邻接布面。
vec4 cloth_texel(vec2 point, vec4 patch, vec2 tile) {
	if (!cloth_contains(point, patch)) {
		return vec4(0.0);
	}
	vec2 local = clamp(point - patch.xy, vec2(0.5), patch.zw - 0.5); // 图块内的有效像素。
	return texture(cloth_atlas, (tile + local) / CLOTH_SIZE);
}

vec4 cloth_over(vec4 front, vec4 back) {
	float visible_back = back.a * (1.0 - front.a); // 前层自身的透明边后仍显示船体。
	float coverage = front.a + visible_back; // 保持 CanvasItem 的直通透明色。
	return vec4((front.rgb * front.a + back.rgb * visible_back) / max(coverage, 0.00001), coverage);
}

// 再利用透明空域裁下的旗面反选旧轮廓，船杆和动力图集在轮廓外继续正常合成。
vec4 without_free_cloth(vec2 point, vec4 frame, vec4 patch, vec2 tile) {
	if (cloth_texel(point, patch, tile).a > 0.006) {
		return vec4(0.0);
	}
	return frame;
}

// 沿自由端传播的一道主折波和一组较小的高频褶；整数倍相位跨周期无跳变。
float cloth_fold(float phase, float along, float wind, float offset) {
	float crest = TAU * (phase - along * mix(0.86, 1.38, wind) + offset); // 风大时褶距更紧。
	return 0.74 * sin(crest) + 0.26 * sin(2.0 * crest - 2.4 * along + 1.1);
}

// 红带左端固接。更高的风压稍微延长可见轮廓、抬平尾段，并增大行波。
vec4 painted_ribbon(vec2 point, vec4 patch, vec2 tile, vec2 drive, float sag) {
	float pull = smoothstep(0.23, 0.96, drive.y); // 巡航有基本张力，阵风把自由端拉向船尾。
	float tautness = pull + (1.0 - pull) * cruise_tension; // 高阵风仍保持原有布片边界。
	float stretch = 1.0 + cloth_amount * mix(0.011, 0.105, tautness); // 只在下风方向拉开。
	vec2 sample_point = point;
	sample_point.x = patch.x + (point.x - patch.x) / stretch;
	float along = clamp((sample_point.x - patch.x) / (patch.z - 12.0), 0.0, 1.0); // 从挂边到旗尖。
	float wave = cloth_fold(drive.x, along, pull, 0.12); // 折波从挂边向外走。
	float response = smoothstep(0.015, 0.96, along); // 首尾连续，挂边没有采样位移。
	float lift = sag * along * mix(0.14, 0.79, tautness); // 常态就受力，阵风进一步减少下垂。
	sample_point.y -= cloth_amount * (response * mix(10.0, 24.0, pull) * wave - lift);
	vec4 paint = cloth_texel(sample_point, patch, tile); // 原画红棕颜料随褶运动。
	paint.rgb *= 1.0 + 0.14 * response * cloth_amount * wave;
	return paint;
}

// 逆向采样顶部或根部固定的旗。pin 包含挂点参考坐标及挂边斜率。
vec4 painted_pennant(vec2 point, vec4 patch, vec2 tile, vec2 drive, vec4 pin, float reach) {
	float pull = smoothstep(0.22, 0.96, drive.y); // 高速时迎风面立起，旗尾向同一方向偏。
	float tautness = pull + (1.0 - pull) * cruise_tension; // 只提高平均偏向，不同步所有褶波。
	float edge = pin.y + (point.x - pin.x) * pin.z; // 挂边可斜，杆上两端始终在原处。
	float distance = point.y - edge; // 映射完成前的挂边下方距离。
	float raised = 1.0 - mix(0.018, 0.18, tautness) * cloth_amount; // 掀起的布在屏幕纵向投影变短。
	float depth = distance >= 0.0 ? distance / raised : distance; // 布杆以上保留原始接缝。
	float along = clamp(depth / pin.w, 0.0, 1.0); // 固定边到自由端的归一化布长。
	float wave = cloth_fold(drive.x, along, pull, 0.04); // 独立挂点的褶波。
	float bend = pow(along, 1.48) * cloth_amount; // 挂边斜率保持，末梢响应最强。
	float dx = bend * reach * (mix(0.20, 0.76, tautness) + mix(0.43, 0.63, pull) * wave);
	vec2 sample_point = vec2(point.x - dx, edge + depth - dx * pin.z); // 倾斜挂件的局部横向逆变形。
	vec4 paint = cloth_texel(sample_point, patch, tile);
	paint.rgb *= 1.0 + bend * 0.17 * wave; // 不改变图案，只表现折面明暗。
	return paint;
}

// 固定底片保留遮在红带前的横杆；垂旗与红带的区域允许自然交叠。
vec4 paint_airship_flags(vec2 point, vec4 frame) {
	if (point.y < 251.0) {
		if (point.x >= 165.0 && point.x < 601.0 && point.y < 126.0) {
			vec2 tile = vec2(402.0, 0.0); // 船首横飘长旗。
			vec4 back = without_free_cloth(point, frame, BOW_RIBBON, tile);
			return cloth_over(back, painted_ribbon(point, BOW_RIBBON, tile, vec2(ribbon_phase.x, ribbon_wind.x), 40.0));
		}
		if (point.x >= 678.0 && point.x < 1038.0 && point.y >= 88.0) {
			vec4 back = frame; // 普通像素仍是船体原画。
			if (cloth_contains(point, MID_RIBBON)) {
				back = cloth_texel(point, MID_RIBBON, vec2(0.0, 120.0));
			} else if (cloth_contains(point, MID_FLAG)) {
				back = cloth_texel(point, MID_FLAG, vec2(230.0, 120.0));
			}
			vec4 ribbon = painted_ribbon(point, MID_RIBBON, vec2(0.0), vec2(ribbon_phase.y, ribbon_wind.y), 48.0);
			vec4 flag = painted_pennant(point, MID_FLAG, vec2(230.0, 0.0), vec2(pennant_phase.x, pennant_wind.x),
					vec4(698.0, 98.0, 0.0, 108.0), 41.0);
			return cloth_over(flag, cloth_over(back, ribbon));
		}
		if (point.x >= 1069.0 && point.x < 1345.0 && point.y >= 120.0) {
			vec2 tile = vec2(402.0, 96.0); // 右旗后侧的红飘带。
			vec4 back = without_free_cloth(point, frame, AFT_RIBBON, tile);
			if (cloth_contains(point, AFT_FLAG)) {
				back = cloth_texel(point, AFT_FLAG, vec2(310.0, 120.0));
			}
			vec4 ribbon = painted_ribbon(point, AFT_RIBBON, tile, vec2(ribbon_phase.z, ribbon_wind.z), 73.0);
			vec4 flag = painted_pennant(point, AFT_FLAG, vec2(310.0, 0.0), vec2(pennant_phase.y, pennant_wind.y),
					vec4(1088.0, 130.0, 0.23, 92.0), 38.0);
			return cloth_over(flag, cloth_over(back, ribbon));
		}
	} else if (point.y >= 757.0) {
		if (point.x >= 223.0 && point.x < 347.0 && point.y >= BOW_HEM.y) {
			vec2 tile = vec2(402.0, 220.0); // 船首旗面在机匣以下的自由端。
			vec4 back = without_free_cloth(point, frame, BOW_HEM, tile);
			return cloth_over(painted_pennant(point, BOW_HEM, tile, vec2(pennant_phase.z, pennant_wind.z),
					vec4(243.0, 786.0, 0.0, 80.0), 25.0), back);
		}
		if (point.x >= 1058.0 && point.x < 1166.0 && point.y < 829.0) {
			vec2 tile = vec2(489.0, 220.0); // 船尾旗面露在船壳以下的旗尾。
			vec4 back = without_free_cloth(point, frame, AFT_HEM, tile);
			return cloth_over(painted_pennant(point, AFT_HEM, tile, vec2(pennant_phase.w, pennant_wind.w),
					vec4(1080.0, 757.0, 0.0, 64.0), 21.0), back);
		}
	} else if (point.y >= 486.0 && point.y < 576.0 && point.x >= 1232.0 && point.x < 1350.0) {
		vec2 tile = vec2(565.0, 220.0); // 船尾小旗上部仍绕在横杆上。
		vec4 back = without_free_cloth(point, frame, RAIL_FLAG, tile);
		return cloth_over(painted_pennant(point, RAIL_FLAG, tile, rail_pennant,
				vec4(1246.0, 490.0, 0.0, 77.0), 26.0), back);
	}
	return frame;
}
