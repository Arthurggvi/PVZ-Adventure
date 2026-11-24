shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/weather/snow_storm_fields.gdshaderinc"

uniform bool near_layer = false;
uniform bool fine_world_snow = true;
// 本平面两层的世界位移与运动轴，远/中和近/冰使用不同实例。
uniform vec4 flake_travel;
uniform vec4 flake_direction = vec4(0.0, 1.0, 0.0, 1.0);
uniform vec3 snow_sample;
// X 能见度损失，Y 阵风，Z 地吹雪尾声，W 世界雪墙平移。
uniform vec4 storm_weather;
// 外部演出的狂风包络；零时使用常态降雪的长度与覆盖率。
uniform float wind_burst = 0.0;
uniform float drift_phase;
uniform vec4 slope_edges;
uniform vec4 slope_heights;
uniform vec4 bottom_band;
uniform float ridge_y = 152.0;
uniform vec4 haze_color : source_color = vec4(0.56, 0.64, 0.72, 1.0);
// 远、中、近、冰格距与 SnowStormRenderer 的位移回绕长度严格对应。
const vec4 WORLD_SPACING = vec4(27.0, 46.0, 184.0, 112.0);
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 位移和格索引采用同一周期，长局回绕时同一雪粒无缝接续。
vec2 seed(vec2 grid) {
	vec2 cell = mod(grid, 128.0);
	return fract(sin(vec2(dot(cell, vec2(43.13, 17.71)), dot(cell, vec2(39.91, 59.21)))) * 8137.361);
}

float flakes(vec2 travel, vec2 axis, float stride, float radius, float stretch, float coverage, float softness) {
	vec2 grid = (world - travel) / stride; // 沿实际风速推进的局部格坐标。
	vec2 rnd = seed(floor(grid)); // 每格的确定性偏移和稀疏度。
	vec2 offset = (fract(grid) - mix(vec2(0.23), vec2(0.77), rnd)) * stride; // 格内的实际雪心。
	vec2 p = vec2(dot(offset, vec2(-axis.y, axis.x)), dot(offset, axis) / stretch); // 分开横宽与风向长度。
	float size = radius * mix(0.70, 1.26, rnd.x); // 不同颗粒的直径变化。
	float mark = 1.0 - smoothstep(size * softness, size, length(p)); // 近雪软边，冰粒保留亮核。
	float density = smoothstep(rnd.y - 0.075, rnd.y + 0.06, coverage); // 档位只改采样比例，不移动格位。
	return mark * density * smoothstep(0.0, 0.06, coverage);
}

float slope_at(float x) {
	float a = clamp((x - slope_edges.x) / max(1.0, slope_edges.y - slope_edges.x), 0.0, 1.0);
	float b = clamp((x - slope_edges.z) / max(1.0, slope_edges.w - slope_edges.z), 0.0, 1.0);
	return mix(slope_heights.x, slope_heights.y, a) + (slope_heights.w - slope_heights.z) * b;
}

// 用同一世界雪墙开口驱动角色前后的薄雾与贴地飞雪。
float wall_openings(vec2 point) {
	return mix(0.26, 1.0, smoothstep(0.19, 0.80, snow_wall_field(point, storm_weather.w)));
}

// y 已扣除坡面高度。远中景随雪墙经过变密，近排保留更多对比。
float fog_depth(float y) {
	float far_air = 1.0 - smoothstep(ridge_y - 40.0, ridge_y + 150.0, y);
	float middle_wall = smoothstep(ridge_y - 185.0, ridge_y - 28.0, y)
		* (1.0 - smoothstep(ridge_y + 36.0, ridge_y + 266.0, y));
	return far_air * 0.075 + middle_wall * 0.255;
}

// 沿同一横向风程移动的断续雪带，薄线和雾肩共用开口。
float burst_ribbons(vec2 point) {
	float x = point.x / 2048.0 - storm_weather.w; // 与雪墙一同回绕的横向相位。
	float shear = sin(TAU * x * 4.0 + point.y * 0.031) * 0.64; // 风切造成的短波折线。
	float lane = 0.5 + 0.5 * sin(point.y * 0.118 + shear); // 各股横向雪丝的垂直间隔。
	float holes = smoothstep(0.26, 0.69, snow_wall_field(point, storm_weather.w)); // 雪带之间保留低密度开口。
	return (pow(lane, 19.0) * 0.52 + pow(lane, 4.0) * 0.23) * holes;
}

void fragment() {
	float shift = slope_at(world.x);
	float y = world.y - shift;
	float x_mask = smoothstep(bottom_band.x - 16.0, bottom_band.x + 6.0, world.x)
		* (1.0 - smoothstep(bottom_band.y - 6.0, bottom_band.y + 16.0, world.x));
	float bottom_guard = x_mask * smoothstep(bottom_band.z - 36.0, bottom_band.z - 9.0, y)
		* (1.0 - smoothstep(bottom_band.w + 9.0, bottom_band.w + 50.0, y));
	float preview_guard = smoothstep(bottom_band.y - 10.0, bottom_band.y + 72.0, world.x);
	float a = 0.0; // 总透明度由所在层的上限约束。
	if (near_layer) {
		// 失焦近雪在持续暴雪中仍是短软片，只有强阵风带出水平冰粒和破碎雪丝。
		float budget = fine_world_snow ? 1.0 : 0.42;
		float close_snow = flakes(flake_travel.xy, flake_direction.xy, WORLD_SPACING.z, 6.2,
			mix(mix(1.06, 1.82, snow_sample.y), 6.6, wind_burst), snow_sample.x * 0.72 * budget, 0.19) * mix(0.13, 0.28, snow_sample.y);
		float peak = smoothstep(0.50, 0.82, storm_weather.y) * smoothstep(0.60, 0.91, snow_sample.x);
		float shards = 0.0; // 非峰值完全跳过这组采样。
		if (fine_world_snow && peak > 0.006) {
			float wind_strip = world.x / 512.0 - storm_weather.w * 4.0 + world.y / 95.0; // 与世界雪墙同向的局部细带。
			float gaps = smoothstep(0.22, 0.86, 0.5 + 0.5 * sin(TAU * wind_strip)); // 破碎雪丝只在局部掠过。
			shards = flakes(flake_travel.zw, flake_direction.zw, WORLD_SPACING.w, 1.23,
				mix(mix(3.7, 6.8, peak), 24.0, wind_burst), mix(0.62, 0.96, wind_burst), 0.44)
				* mix(0.33 * gaps, 0.68, wind_burst) * peak;
		}
		float fog = 0.0; // 阵风实到时才将少量世界散射放到实体前。
		if (storm_weather.x > 0.01) {
			fog = min(0.105, storm_weather.x * wall_openings(world) * fog_depth(y) * 0.37);
		}
		a = min(mix(0.39, 0.58, wind_burst), close_snow + shards + fog)
			* (1.0 - 0.91 * bottom_guard) * (1.0 - 0.91 * preview_guard);
		if (wind_burst > 0.001) {
			a += wind_burst * burst_ribbons(world) * (0.32 + 0.54 * snow_sample.x)
				* (1.0 - 0.55 * bottom_guard) * (1.0 - 0.60 * preview_guard);
		}
	} else {
		float coverage = snow_sample.x * (fine_world_snow ? 1.0 : 0.67); // 低档沿用网格和相位，减少明显雪片。
		float distant = flakes(flake_travel.xy, flake_direction.xy, WORLD_SPACING.x, 1.30,
			mix(mix(1.05, 2.05, snow_sample.y), 6.1, wind_burst), coverage * 0.81, 0.40) * mix(0.28, 0.20, snow_sample.y);
		float middle = flakes(flake_travel.zw, flake_direction.zw, WORLD_SPACING.y, 2.34,
			mix(mix(1.03, 3.05, snow_sample.y), 10.0, wind_burst), coverage, 0.35) * mix(0.49, 0.39, snow_sample.y);
		// 天空的山体退隐已由天空材质处理。世界雪墙在中景最明显，向战场低处逐渐变浅。
		float openings = wall_openings(world);
		float fog = storm_weather.x * openings * fog_depth(y)
			* (1.0 - 0.79 * bottom_guard);
		float streak = pow(0.5 + 0.5 * sin(TAU * (world.x / 256.0 + drift_phase)), 4.0);
		float windswept = pow(0.5 + 0.5 * sin(y * 0.155 + 0.45 * sin(world.x * 0.018)), 4.0);
		float floor_band = smoothstep(ridge_y + 16.0, ridge_y + 64.0, y)
			* (1.0 - smoothstep(bottom_band.w + 22.0, bottom_band.w + 115.0, y));
		float dust = streak * windswept * floor_band * openings * storm_weather.z * 0.26
			* (1.0 - 0.92 * bottom_guard) * (1.0 - 0.65 * preview_guard);
		a = min(0.57, distant + middle + fog + dust);
	}
	vec3 tint = near_layer ? mix(haze_color.rgb, vec3(0.89, 0.93, 0.95), 0.40) : haze_color.rgb;
	tint = mix(tint, vec3(0.77, 0.92, 1.0), wind_burst * 0.46);
	COLOR = vec4(tint, a);
}
