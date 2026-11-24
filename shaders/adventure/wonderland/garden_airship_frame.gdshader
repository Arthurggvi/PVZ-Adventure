shader_type canvas_item;

#include "res://shaders/adventure/wonderland/garden_airship_cloud_light.gdshaderinc"
#include "res://shaders/adventure/wonderland/garden_airship_flags.gdshaderinc"

// 关卡模拟时钟（秒）。暂停和倍速由关卡统一处理。
uniform float flight_seconds = 0.0;
// 上半图为左桨、下半图为右桨；姿势中已合成修补的船壳、轴帽与机匣遮挡。
uniform sampler2D propulsion_atlas : source_color, filter_linear, repeat_disable;

// 两处换片窗口均使用母图像素，与周围机匣共用下船体逆映射。
const vec2 LEFT_ORIGIN = vec2(300.0, 719.0);
const vec2 RIGHT_ORIGIN = vec2(936.0, 713.0);
// 每桨以十六种姿势覆盖四叶桨的一个四分之一周；每行八帧。
const vec2 TILE_SIZE = vec2(152.0, 168.0);
const vec2 ATLAS_SIZE = vec2(1216.0, 672.0);

// 船身横梁的起止采样位置，单位为原图像素；两端的船舱与敌舰保持原比例。
const vec2 STRETCH_SECTION = vec2(300.0, 1054.0);
// 平滑分配拉伸的过渡宽度，单位为原图像素。
const float FEATHER = 48.0;
// 加在横梁中段的宽度，战场节点以 0.9 倍显示，即增加 460.8 个世界像素。
const float EXTRA_WIDTH = 512.0;

// 下船体沿金色横栏平滑接入，栏柱及上部船身继续使用原有逆映射。
const vec2 HULL_HANDOFF_Y = vec2(687.0, 703.0);
// 两段金属箍在出现在横栏上缘前就接到下船体，使箍件顶边与箍身对齐。
const vec2 CLASP_HANDOFF_Y = vec2(681.0, 686.0);
// 每侧窗的四个加宽坐标依次为左过渡起点、箍件两边和右过渡终点。两端避开栏柱。
const vec4 PORT_CLASP_WINDOW = vec4(561.0, 572.0, 612.0, 767.0);
const vec4 STARBOARD_CLASP_WINDOW = vec4(1244.0, 1371.0, 1440.0, 1470.0);
// 金属箍件在母图中保留形状的横向范围。
const vec2 PORT_CLASP_SOURCE = vec2(518.0, 558.0);
const vec2 STARBOARD_CLASP_SOURCE = vec2(873.0, 942.0);
// 左机匣、船徽及龙骨灯、右机匣的累计平移量，单位为加宽后的像素。
const vec3 HULL_SHIFTS = vec3(38.0, 249.0, 500.0);
// 右桨后方与垂旗之间的最后一段加宽区，单位为母图像素。
const vec2 HULL_TAIL_GAP = vec2(1066.0, 1081.0);
// 船腹板缝加宽的最大羽化宽度，随局部可用板面收窄。
const float HULL_PANEL_FEATHER = 27.0;

// 保留 Sprite2D 的节点调色与透明度，供重采样后合成。
varying vec4 sprite_color;
// 真实船体世界坐标，计算云影时独立于母图的逆映射。
varying vec2 world_point;

// 计算经过单个端点的累计权重，使两端的采样比例逐渐回到 1:1。
float ramp_integral(float distance_from_edge, float feather) {
	float ramp = clamp(distance_from_edge, 0.0, feather); // 端点羽化内的距离。
	return ramp * ramp / (2.0 * feather) + max(distance_from_edge - feather, 0.0);
}

// 返回加宽段的累计权重。边界和羽化宽度均使用加宽后的像素坐标。
float stretch_progress(float output_x, vec2 bounds, float feather) {
	float distance = output_x - bounds.x; // 从加宽段左端起算。
	float span = bounds.y - bounds.x - feather; // 累计权重的满量程。
	return (ramp_integral(distance, feather) - ramp_integral(distance - span, feather)) / span;
}

// 原有的上梁逆映射，同样用于箍件窗口的两个衔接端点。
float upper_frame_x(float output_x) {
	return output_x - EXTRA_WIDTH * stretch_progress(output_x, STRETCH_SECTION + vec2(0.0, EXTRA_WIDTH), FEATHER);
}

// 在箍件两侧经过空白横栏回到既有映射，窗口外的栏柱保持原位。
float rail_clasp_x(float output_x, vec4 window, vec2 clasp) {
	if (output_x < window.y) {
		float weight = (output_x - window.x) / (window.y - window.x); // 从左侧空白横栏接到箍件左缘。
		return mix(upper_frame_x(window.x), clasp.x, weight);
	}
	if (output_x < window.z) {
		float weight = (output_x - window.y) / (window.z - window.y); // 在箍件内部保留母图宽度。
		return mix(clasp.x, clasp.y, weight);
	}
	float weight = (output_x - window.z) / (window.w - window.z); // 从箍件右缘接回上部横栏。
	return mix(clasp.y, upper_frame_x(window.w), weight);
}

// 计算一段空板面需要从输出横坐标扣除的加宽量。shifts 是该段两端的累计平移量。
float hull_panel_offset(float output_x, vec2 source_gap, vec2 shifts) {
	float feather = min(HULL_PANEL_FEATHER, (source_gap.y - source_gap.x) * 0.5); // 端点羽化永远小于原板面宽度。
	return (shifts.y - shifts.x) * stretch_progress(output_x, source_gap + shifts, feather);
}

// 随船腹轮廓收窄可加宽区，让两侧机匣、桨叶、船徽和龙骨灯按母图比例采样。
float lower_hull_x(float output_x, float source_y) {
	vec2 port_gap = vec2(310.0, mix(364.0, 319.0, smoothstep(728.0, 754.0, source_y))); // 左垂旗后方，从梁板过渡到桨叶边缘外。
	vec2 port_panel = vec2(
			mix(549.0, 514.0, smoothstep(725.0, 775.0, source_y)),
			mix(641.0, 575.0, smoothstep(760.0, 795.0, source_y))); // 避开左箍、船徽和下缘的龙骨灯。
	vec2 starboard_panel = vec2(
			mix(781.0, 747.0, smoothstep(744.0, 783.0, source_y)),
			mix(854.0, 813.0, smoothstep(715.0, 766.0, source_y))); // 沿右侧弧形板缝收拢，避开发动机进气管。
	return output_x
			- hull_panel_offset(output_x, port_gap, vec2(0.0, HULL_SHIFTS.x))
			- hull_panel_offset(output_x, port_panel, HULL_SHIFTS.xy)
			- hull_panel_offset(output_x, starboard_panel, HULL_SHIFTS.yz)
			- hull_panel_offset(output_x, HULL_TAIL_GAP, vec2(HULL_SHIFTS.z, EXTRA_WIDTH));
}

void vertex() {
	sprite_color = COLOR;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 将换片窗口内的坐标定位到指定相位；半像素边距防止相邻帧串色。
vec4 rotor_pose(vec2 local_pixel, float phase, float side) {
	vec2 tile = vec2(mod(phase, 8.0), floor(phase / 8.0) + 2.0 * side); // 图集帧坐标。
	vec2 pixel = clamp(local_pixel, vec2(0.5), TILE_SIZE - vec2(0.5)); // 当前帧有效采样区。
	return texture(propulsion_atlas, (tile * TILE_SIZE + pixel) / ATLAS_SIZE);
}

void fragment() {
	float output_x = UV.x * (1.0 / TEXTURE_PIXEL_SIZE.x + EXTRA_WIDTH); // 加宽后的横坐标。
	float source_y = UV.y / TEXTURE_PIXEL_SIZE.y; // 船体纵向沿用原图像素。
	float source_x = upper_frame_x(output_x); // 上部横梁的既有逆映射。
	if (source_y > CLASP_HANDOFF_Y.x && source_y < HULL_HANDOFF_Y.y) {
		float clasp_weight = smoothstep(CLASP_HANDOFF_Y.x, CLASP_HANDOFF_Y.y, source_y); // 在箍顶露出前完成接入。
		if (output_x > PORT_CLASP_WINDOW.x && output_x < PORT_CLASP_WINDOW.w) {
			source_x = mix(source_x, rail_clasp_x(output_x, PORT_CLASP_WINDOW, PORT_CLASP_SOURCE), clasp_weight);
		} else if (output_x > STARBOARD_CLASP_WINDOW.x && output_x < STARBOARD_CLASP_WINDOW.w) {
			source_x = mix(source_x, rail_clasp_x(output_x, STARBOARD_CLASP_WINDOW, STARBOARD_CLASP_SOURCE), clasp_weight);
		}
	}
	if (source_y > HULL_HANDOFF_Y.x && output_x > STRETCH_SECTION.x && output_x < HULL_TAIL_GAP.y + EXTRA_WIDTH) {
		float hull_weight = smoothstep(HULL_HANDOFF_Y.x, HULL_HANDOFF_Y.y, source_y); // 在横栏内连续接入下船体。
		source_x = mix(source_x, lower_hull_x(output_x, source_y), hull_weight);
	}
	vec2 source_pixel = vec2(source_x, source_y); // 原画、桨叶图集及布料共用的母图位置。
	float side = step(RIGHT_ORIGIN.x, source_x); // 左右换片窗口互不相交。
	vec2 local_pixel = source_pixel - mix(LEFT_ORIGIN, RIGHT_ORIGIN, side); // 以局部窗口左上为零点。
	vec4 frame_paint; // 先画原船壳和动力部件，再按独立罩片合成布料。
	if (all(greaterThanEqual(local_pixel, vec2(0.0))) && all(lessThan(local_pixel, TILE_SIZE))) {
		// 2.125 和 2.25 转/秒，右桨独立起相；离线角度积分柔化高速叶缘。
		float frame = mod(flight_seconds * mix(136.0, 144.0, side) + side * 3.0, 16.0);
		vec4 current = rotor_pose(local_pixel, floor(frame), side); // 当前投影姿势。
		vec4 next = rotor_pose(local_pixel, mod(floor(frame) + 1.0, 16.0), side); // 相邻姿势，含首尾回绕。
		frame_paint = mix(current, next, fract(frame));
	} else {
		frame_paint = texture(TEXTURE, source_pixel * TEXTURE_PIXEL_SIZE);
	}
	COLOR = paint_airship_flags(source_pixel, frame_paint) * sprite_color;
	COLOR.rgb *= airship_cloud_light(world_point);
}
