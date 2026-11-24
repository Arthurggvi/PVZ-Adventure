// 单弹五个窄四边形；每枚幻影在 GPU 上回算真实历史路径，无逐帧重建画布。
shader_type canvas_item;
render_mode unshaded;

// 游戏飞行时间、入行位移、带方向的出膛速度。
instance uniform vec4 flight = vec4(0.0, 0.0, 0.0, 300.0);
// 终结尾弹保留同一套拖影网格，仅使用暖色以辨认。
instance uniform bool final_round = false;
varying flat float stamp;
varying flat float reveal;
varying flat float charge;
varying vec2 local_uv;

// 此积分遵循动能子弹的1.5秒速度曲线；只用于绘制已走过的位置。
vec2 history_offset(float time) {
	float ramp = clamp(time, 0.0, 1.5);
	float distance = abs(flight.w) * (ramp + ramp * ramp / 3.0 + 2.0 * max(0.0, time - 1.5));
	vec2 entry = flight.yz;
	float entry_length = length(entry);
	vec2 straight = vec2(sign(flight.w) * max(0.0, distance - entry_length), 0.0);
	return entry_length > 0.01 ? straight + entry * min(1.0, distance / entry_length) : straight;
}

void vertex() {
	stamp = floor(UV.y);
	charge = clamp(flight.x / 1.5, 0.0, 1.0);
	float step = mix(0.037, 0.048, charge);
	float previous = max(0.0, flight.x - stamp * step);
	reveal = stamp < 0.5 ? 1.0 : smoothstep(0.0, 0.016, flight.x - stamp * step);
	vec2 offset = history_offset(previous) - history_offset(flight.x);
	vec2 motion = history_offset(previous + 0.018) - history_offset(max(previous - 0.018, 0.0));
	vec2 axis = length(motion) > 0.01 ? normalize(motion) : vec2(sign(flight.w), 0.0);
	vec2 across = vec2(-axis.y, axis.x);
	vec2 size = vec2(1.0 - 0.085 * stamp, 1.0 - 0.14 * stamp);
	VERTEX = offset + axis * VERTEX.x * size.x + across * VERTEX.y * size.y;
	local_uv = vec2(UV.x * 2.0 - 1.0, ((fract(UV.y) - 0.1) / 0.8) * 2.0 - 1.0);
}

void fragment() {
	vec2 oval = vec2(local_uv.x * 1.08, local_uv.y * 1.04);
	float d = length(oval);
	float soft_glow = 1.0 - smoothstep(0.50, 1.0, d);
	float core = 1.0 - smoothstep(0.41, 0.69, d);
	float shine = 1.0 - smoothstep(0.18, 0.39, length((local_uv - vec2(0.19, -0.2)) * vec2(0.8, 1.8)));
	vec3 cyan = vec3(0.32, 0.79, 1.00);
	vec3 violet = vec3(0.55, 0.43, 1.0);
	vec3 tint = mix(cyan, violet, stamp / 4.55);
	if (final_round) {
		tint = mix(vec3(1.0, 0.81, 0.31), vec3(1.0, 0.42, 0.20), stamp / 4.55);
	}
	tint = mix(tint, vec3(0.87, 1.0, 1.0), shine * (stamp < 0.5 ? 0.95 : 0.4));
	float opacity = stamp < 0.5 ? 1.0 : (1.0 - stamp / 5.0) * (0.66 + 0.30 * charge);
	COLOR = vec4(tint, reveal * opacity * (0.31 * soft_glow + 0.69 * core));
}
