shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// 地面层和柱身层共享世界坐标与实例数据。
uniform bool ground_only = false;
// 四边形上的实际柱底位置与落地事件共用。
uniform float ground_y = 0.88;
// 每个局部轴上包含的地面接触半径，用于描出扫掠边缘。
uniform vec2 section_in_radii = vec2(1.77, 9.5);
// 战斗时间控制缓慢流动的光带，暂停期间冻结。
uniform float flow_time = 0.0;
// 从第一次触地开始计时，负值时仅显示空中的柱尖。
uniform float seconds_after_impact = -1.0;
// 第一束离开原碰撞点后的位移，以接触半径为单位。
uniform vec2 impact_offset;
// 当前救主原画帧的图集、纹理边界、逆屏幕变换与继承透明度。
uniform sampler2D owner_sheet : filter_linear, repeat_disable;
uniform vec4 owner_source;
uniform vec4 owner_axes;
uniform vec2 owner_offset;
uniform float owner_opacity = 0.0;
varying vec2 section;
varying flat vec4 beam;
varying flat float retreat;
varying flat float crimson;
varying flat float behind_owner;
varying flat float shaft_pulse;

const vec3 DEEP_RED = vec3(0.45, 0.018, 0.052);
const vec3 SCARLET = vec3(1.0, 0.103, 0.190);
const vec3 HOT = vec3(1.0, 0.69, 0.53);
// 仅用于受压的柱芯和贴地瞬态。
const vec3 WHITE_HOT = vec3(1.0, 0.88, 0.80);

void vertex() {
	if (ground_only) {
		VERTEX.y = ground_y + VERTEX.y * (1.14 / section_in_radii.y);
	}
	section = VERTEX;
	beam = INSTANCE_CUSTOM;
	retreat = COLOR.r;
	crimson = COLOR.g; // 疯狂为满红，福音的活柱与击破余光使用白色。
	behind_owner = COLOR.a;
	// 各束错开约半个低频周期。缓闪在顶点阶段计算，地面轮廓和真光照保持稳定。
	float phase = INSTANCE_CUSTOM.a * 6.2831853;
	float beat = sin(flow_time * 4.28 - phase * 0.55 + 0.28 * sin(flow_time * 1.31 + phase));
	float breath = mix(0.62, 1.0, smoothstep(-0.84, 0.82, beat));
	float breath_mix = smoothstep(0.22, 0.60, seconds_after_impact) * (1.0 - smoothstep(0.04, 0.17, COLOR.r));
	shaft_pulse = mix(1.0, breath, breath_mix);
}

// 反差集中的贴地压痕。窄边像被压裂的砖，外围断线对应实际扫掠半径。
vec4 ground_contact(vec2 contact, float phase, float impact, float recoil) {
	vec2 stone = contact * vec2(1.0, 1.67);
	float radius = length(stone);
	float angle = atan(stone.y, stone.x + 0.00001);
	vec2 side = abs(stone);
	float slab = max(dot(side, vec2(0.93, 0.39)), dot(side, vec2(0.36, 0.91)));
	float facets = 0.63 * cos(angle * 3.0 + phase) + 0.37 * sin(angle * 7.0 - phase);
	float lip = 0.56 + 0.051 * facets + 0.11 * impact;
	float plate = 1.0 - smoothstep(lip - 0.029, lip + 0.037, slab);
	float rim = 1.0 - smoothstep(0.014, 0.054, abs(slab - lip));
	float core = 1.0 - smoothstep(0.19, 0.42, radius);
	float brush = 0.34 + 0.66 * smoothstep(-0.39, 0.68, facets);
	float sweep_edge = (1.0 - smoothstep(0.016, 0.046, abs(length(contact) - 0.97))) * brush;
	float ember = 1.0 - smoothstep(0.49, 1.16, radius);
	float warning = 0.044 * smoothstep(0.24, 0.79, beam.r) * (1.0 - beam.b) * beam.g;
	float alpha = clamp(beam.b * (0.43 * plate + 0.23 * rim * brush + (0.25 + 0.25 * recoil) * core
		+ 0.16 * sweep_edge + 0.07 * ember) + warning * plate, 0.0, 1.0);
	vec3 tint = mix(SCARLET, WHITE_HOT, min(1.0, 0.84 * core + 0.56 * rim * brush + 0.13 * plate + 0.18 * impact));
	return vec4(tint * alpha, alpha);
}

// 第一束撞地时，断裂的波沿石砖推出。碎片与折线只占撞击点周围一小片地面。
vec4 ground_break(vec2 contact) {
	vec2 stone = contact * vec2(1.0, 1.68);
	float radius = length(stone);
	float age = seconds_after_impact / 0.38;
	float sectors = atan(stone.y, stone.x + 0.00001) * (9.0 / 6.2831853) + 0.19;
	float tile = floor(sectors + 0.5);
	float chip = fract(sin(tile * 23.71 + 7.31) * 415.93);
	float wedge = sectors - tile;
	float step_crack = abs(fract(radius * 2.95 + chip * 0.82) * 2.0 - 1.0) - 0.5;
	float seam = wedge + step_crack * (0.20 + 0.20 * chip);
	float front = mix(0.29, 1.52, 1.0 - pow(1.0 - age, 2.1));
	float reach = front * mix(0.79, 1.06, chip);
	float fissure = (1.0 - smoothstep(0.025, 0.079, abs(seam))) * smoothstep(0.25, 0.40, radius)
		* (1.0 - smoothstep(reach - 0.12, reach + 0.022, radius));
	float crest = (1.0 - smoothstep(0.024, 0.081, abs(radius - reach + 0.028 * wedge)))
		* smoothstep(0.09, 0.24, abs(wedge)) * (1.0 - smoothstep(0.27, 0.44, abs(wedge)));
	float sliver = 1.0 - smoothstep(0.70, 1.0, abs(seam + 0.18) * 10.0
		+ abs(radius - reach - 0.096) * mix(9.0, 17.0, chip));
	float fade = (1.0 - smoothstep(0.15, 1.0, age)) * min(1.0, beam.g * 3.85);
	float alpha = min(1.0, 0.83 * fissure + 0.68 * crest + 0.94 * sliver) * fade;
	vec3 tint = mix(HOT, WHITE_HOT, min(1.0, 0.58 * fissure + 0.46 * crest + 0.85 * sliver));
	return vec4(tint * alpha, alpha);
}

// 柱身单独留在世界合成之后，保留明亮的光带与前后遮挡。
vec4 shaft_color(float impact, float recoil) {
	// 柱芯着地时外撑，回收时先绷紧成一线，再沿原柱身方向抽离。
	float depth = (section.y + 1.0) / (ground_y + 1.0);
	float variant = beam.a * 6.2831853;
	float pinch = smoothstep(0.0, 0.28, retreat);
	float neck = (0.25 + 0.75 * sqrt(beam.g)) * mix(0.56, 1.0, smoothstep(0.06, 0.76, beam.r));
	float width = (0.32 + 0.11 * depth) * neck * (1.0 + 0.62 * impact) * mix(1.0, 0.34, pinch);
	float bend = 0.015 * sin(depth * 11.0 + variant) * sin(clamp(depth, 0.0, 1.0) * 3.14159265);
	float axis = (section.x - bend) / max(width, 0.01);
	float at_tip = 1.0 - smoothstep(beam.r - 0.031, beam.r + 0.027, depth);
	float cutoff = at_tip * (1.0 - smoothstep(0.998, 1.016, depth)) * smoothstep(0.0, 0.07, depth);
	float skirt = exp2(-axis * axis * 1.90) * (1.0 - smoothstep(1.48, 2.08, abs(axis)));
	float core = exp2(-axis * axis * 15.0);
	// 窄而长的透光纹像暗红色彩窗，纹理纵向延伸，不抢实际投影。
	float stripe = 0.68 + 0.16 * cos(axis * 17.0 + sin(depth * 13.0 - flow_time * 2.8 + variant) * 0.90)
		+ 0.08 * sin(depth * 25.0 + axis * 9.0 - flow_time * 5.1 + variant);
	float side_distance = (abs(axis) - 0.61) * 5.6;
	float side = exp2(-side_distance * side_distance);
	vec3 shaft_tint = mix(DEEP_RED, SCARLET, min(1.0, skirt * 0.90 + side * 0.29));
	float tip_distance = (depth - beam.r + 0.025) * 20.0;
	float tip_hot = exp2(-tip_distance * tip_distance);
	shaft_tint = mix(shaft_tint, HOT, min(1.0, core * (0.59 + tip_hot * 0.29) + side * stripe * 0.24));
	shaft_tint = mix(shaft_tint, WHITE_HOT, min(1.0, core * (0.53 * impact + 0.44 * recoil) + tip_hot * skirt * (0.16 + 0.30 * recoil)));
	if (crimson < 0.999) {
		vec3 pearl = mix(vec3(0.33, 0.44, 0.58), vec3(0.87, 0.93, 1.0), min(1.0, skirt * 0.79 + side * 0.21));
		pearl = mix(pearl, vec3(1.0, 0.989, 0.956), min(1.0, core * 0.86 + tip_hot * 0.19));
		shaft_tint = mix(pearl, shaft_tint, crimson);
	}
	float shaft_alpha = clamp(beam.g * cutoff * shaft_pulse
		* (skirt * (0.45 + 0.17 * stripe) + core * (0.31 + 0.22 * impact + 0.28 * recoil) + side * 0.048), 0.0, 1.0);
	return vec4(shaft_tint * shaft_alpha, shaft_alpha);
}

// 柱底更远时，按救主原画像素的 Alpha 隐去重叠部分。近处柱体可从她身前经过。
float owner_mask(vec2 screen_uv) {
	if (behind_owner <= 0.0 || owner_opacity <= 0.0) {
		return 1.0;
	}
	vec2 pose = mat2(owner_axes.xy, owner_axes.zw) * screen_uv + owner_offset;
	if (all(greaterThanEqual(pose, vec2(0.0))) && all(lessThanEqual(pose, vec2(1.0)))) {
		return 1.0 - texture(owner_sheet, owner_source.xy + pose * owner_source.zw).a * behind_owner * owner_opacity;
	}
	return 1.0;
}

void fragment() {
	if (beam.g <= 0.0 && beam.b <= 0.0) {
		discard; // 已离开场地的实例不再计算柱身和地面反光。
	}
	float impact = step(0.0, seconds_after_impact) * (1.0 - smoothstep(0.035, 0.24, seconds_after_impact));
	float recoil = smoothstep(0.03, 0.15, retreat) * (1.0 - smoothstep(0.28, 0.63, retreat));
	if (ground_only) {
		vec2 contact = vec2(section.x, section.y - ground_y) * section_in_radii;
		vec4 foot = ground_contact(contact, beam.a * 6.2831853, impact, recoil);
		if (beam.a < 0.08 && seconds_after_impact >= 0.0 && seconds_after_impact < 0.38) {
			vec4 fractured = ground_break(contact + impact_offset);
			foot = fractured + foot * (1.0 - fractured.a);
		}
		COLOR = foot; // 石砖批次在角色下方，进入同一世界光场。
	} else {
		COLOR = shaft_color(impact, recoil) * owner_mask(SCREEN_UV);
	}
}
