// 带状雪墙网格沿真实坡面折转。只在雪墙覆盖的路段绘制滚雾、雪粉与细雪线。
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/weather/snow_storm_fields.gdshaderinc"

// 从本行起风时计时，负值留给杖击白闪和相邻攻击行的错峰。
uniform float age = -1.0;
// 带状网格的世界横向长度，以及正向推进的像素每秒。
uniform float span = 1200.0;
uniform float speed = 1260.0;
// 发射窗口给出完整雪墙的纵向长度，之后还有少量余雪。
uniform float release = 1.27;
// 实际雪弹最远到达的距离，雪墙在该边界收边，单位为世界像素。
uniform float reach = 0.0;
// 相邻行使用不同的翻卷与细雪纹理相位。
uniform float seed = 0.0;

void fragment() {
	// U 从右往左计数。先用廉价包络排除风带以外的像素。
	float along = UV.x * span;
	float travel = age * speed;
	float inside_edge = reach - along;
	float behind = travel - along;
	float tail = release * speed;
	if (inside_edge <= 0.0 || behind > tail + 260.0) {
		discard;
	}

	// 一股长卷贴近雪面，另一股短卷集中在前缘，形状跟随整个雪墙移动。
	float height = (UV.y - 0.64) * 97.0;
	float broad = snow_wall_field(vec2(along * 3.40 + height * 4.8 + seed * 700.0, height * 9.0), travel * 3.08 / 2048.0);
	float curls = snow_wall_field(vec2(along * 6.70 + height * 8.9 + 810.0 + seed * 503.0, height * 20.0), travel * 7.43 / 2048.0);
	float ragged_edge = 15.0 + broad * 37.0 + curls * 21.0 + abs(UV.y - 0.62) * 56.0;
	float front = smoothstep(0.0, ragged_edge, inside_edge);
	float wake = 1.0 - smoothstep(tail - 25.0, tail + 260.0, behind);
	float borders = smoothstep(0.0, 55.0, along) * (1.0 - smoothstep(span - 74.0, span, along));
	float rolling_edge = smoothstep(0.08, 0.12 + broad * 0.22 + curls * 0.15, UV.y);
	float lower_edge = 1.0 - smoothstep(0.71 + curls * 0.12, 1.0, UV.y);
	float profile = rolling_edge * lower_edge;
	float breaking = 1.0 - smoothstep(29.0, 202.0, inside_edge + ragged_edge * 0.42);
	float froth = smoothstep(0.31, 0.79, broad * 0.64 + curls * 0.56);
	float billows = smoothstep(0.18, 0.76, broad + curls * 0.17);
	float wash = profile * (0.26 + billows * 0.50 + breaking * (0.33 + froth * 0.26));
	float ground = (1.0 - smoothstep(0.028, 0.24, abs(UV.y - 0.82 + curls * 0.10)))
		* (0.06 + broad * 0.15);

	// 每个像素只求一个细雪格。雪线快于翻卷的雾，能够划过雾面。
	vec2 grain = vec2((along - travel * 1.23) / 72.0 + UV.y * 0.76, UV.y * 16.0 + curls * 0.19);
	vec2 local = fract(grain);
	vec2 grain_cell = floor(grain);
	float speck = snow_wall_hash(grain_cell + vec2(seed * 29.0 + floor(grain_cell.x / 8.0) * 5.0, 31.0));
	float along_grain = local.x - (0.84 - 0.69 * speck);
	float grain_y = abs(local.y - (0.21 + speck * 0.56) + along_grain * 0.18);
	float slit = smoothstep(-0.44, -0.082, along_grain) * (1.0 - smoothstep(0.013, 0.15, along_grain));
	float streaks = slit * (1.0 - smoothstep(0.015, 0.19, grain_y)) * (0.48 + speck * 0.52) * profile;
	float chips = (1.0 - smoothstep(0.10, 0.76, abs(along_grain) * 19.0 + grain_y * 3.8)) * profile;

	// 边缘保留蓝灰冷影，浪头和细雪被白光照亮。
	vec3 blue_ice = vec3(0.38, 0.56, 0.71);
	vec3 powder = vec3(0.95, 0.985, 1.0);
	vec3 color = mix(blue_ice, powder,
		clamp(0.24 + froth * 0.70 + breaking * 0.39 + streaks * 1.08 + chips * 0.60, 0.0, 1.0));
	float alpha = clamp(wash + ground + streaks * 0.86 + chips * 0.53, 0.0, 0.97);
	COLOR = vec4(color, alpha * front * wake * borders);
}
