shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/weather/snow_storm_fields.gdshaderinc"
#include "res://shaders/weather/snow_ground_ridge.gdshaderinc"

uniform sampler2D mountains : source_color, repeat_disable, filter_linear;
uniform sampler2D ribbon : source_color, repeat_disable, filter_linear;
uniform sampler2D clouds : source_color, repeat_enable, filter_linear;
// 静态材质只合成底图和山体，运行时材质按独立素材启用对应效果。
uniform bool animate_aurora = false;
uniform bool has_storm_clouds = false;
uniform vec4 ribbon_region = vec4(0.0, 0.0, 1.0, 1.0);
// 极光两类运动和明暗相位均有界，不跟随风雪加速。
uniform vec2 aurora_phase;
uniform float aurora_swell = 0.5;
uniform float cloud_phase;
uniform float cover;
uniform bool second_ribbon;
// 世界雪墙只改变局部视距，透明山缘仍用原图 alpha。
uniform float visibility_loss = 0.0;
uniform float wall_phase;
uniform vec4 snow_air_color : source_color = vec4(0.79, 0.82, 0.85, 1.0);
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 只扭动独立透明极光条带，底图与固定山体按原 UV 采样。
vec3 light_band(vec2 uv, vec2 offset, vec2 span, float strength, float phase_offset, float storm_light) {
	vec2 p = (uv - offset) / span; // 当前条带的局部坐标。
	float bend = sin(TAU * (p.x * 0.9 + aurora_phase.x + phase_offset)); // 整条光幕的慢摆。
	float fold = sin(TAU * (p.x * 2.8 - aurora_phase.y + phase_offset)); // 反向传播的褶皱。
	p.y += mix(0.14, 0.23, storm_light) * bend + mix(0.042, 0.095, storm_light) * fold;
	p.x += mix(0.018, 0.045, storm_light) * sin(TAU * (p.y * 0.8 + p.x * 1.7 + aurora_phase.y + phase_offset));
	// 柔化图集取样边界，避免扭曲后露出硬边。
	float edge = smoothstep(0.0, 0.13, p.x) * (1.0 - smoothstep(0.87, 1.0, p.x))
		* smoothstep(0.0, 0.11, p.y) * (1.0 - smoothstep(0.82, 1.0, p.y));
	vec2 ribbon_uv = ribbon_region.xy + clamp(p, vec2(0.0), vec2(1.0)) * ribbon_region.zw; // 只读取选定图集条带。
	vec4 glow = texture(ribbon, ribbon_uv); // 真实幕丝和透明边缘。
	vec3 tint = mix(vec3(0.55, 0.70, 0.68), vec3(0.34, 0.96, 0.68), storm_light); // 暴雪天幕中仍可分辨的青绿幕丝。
	return mix(glow.rgb, tint, 0.68) * glow.a * edge * strength * (0.86 + fold * 0.14);
}

// 主战斗镜头的视野开口位于卡槽下方与山脊上方，局部天光沿慢相位张开。
vec3 aurora_skyglow(vec2 uv) {
	vec2 drift = vec2(sin(TAU * aurora_phase.x), cos(TAU * aurora_phase.x)); // 光幕和光晕共用慢相位。
	vec2 center = vec2(0.30, 0.226) + drift * vec2(0.043, 0.019); // 在地图天空内移动，和镜头解耦。
	vec2 ray = (uv - center) / vec2(0.188, mix(0.111, 0.151, aurora_swell)); // 强相位沿竖向铺开。
	float halo = 1.0 - smoothstep(0.045, 1.0, dot(ray, ray)); // 边缘渐隐的局部散射。
	float veil = 0.79 + 0.21 * cos(TAU * (0.83 * ray.x + 0.23 * ray.y - aurora_phase.y)); // 光晕内缓慢流过的明暗间隔。
	return vec3(0.35, 0.88, 0.69) * halo * veil * mix(0.71, 1.03, aurora_swell);
}

void fragment() {
	float wall = snow_wall_field(world, wall_phase); // 与战场中景同相位的远雪墙，密处趋近 1。
	float opening = 1.0 - smoothstep(0.15, 0.44, wall); // 疏处露出短时局部窗口，雪墙移动时沿世界坐标连续。
	float horizon = smoothstep(0.06, 0.39, UV.y); // 近地平线积累较多冷白散射，天顶仍保留夜色。
	float sky_scatter = visibility_loss * mix(0.08, 0.51, horizon) * mix(0.68, 1.0, wall);
	vec3 distant_air = mix(COLOR.rgb, snow_air_color.rgb, sky_scatter); // 给山体使用的无极光散射底色。
	vec3 sky = distant_air;
	if (animate_aurora) {
		float storm_light = smoothstep(0.13, 0.67, visibility_loss); // 只改变极光强时的可见范围和能量，独立慢相位继续运行。
		vec2 offset = mix(vec2(0.13, 0.045), vec2(0.06, 0.042), storm_light); // 暴雪时主幕向战斗区左侧延伸。
		vec2 span = mix(vec2(0.68, 0.32), vec2(0.79, 0.44), storm_light); // 拓宽可见光幕并保留半透明边缘。
		vec3 light = light_band(UV, offset, span, mix(0.36, 1.24, storm_light), 0.0, storm_light); // 主带亮度。
		if (second_ribbon) {
			light += light_band(UV, vec2(0.67, 0.015), vec2(0.33, 0.25), mix(0.14, 0.42, storm_light), 0.41, storm_light);
		}
		light *= mix(mix(0.68, 0.83, storm_light), 1.0, aurora_swell);
		if (storm_light > 0.0) {
			light += aurora_skyglow(UV) * storm_light;
		}
		float transmission = mix(1.0 - cover * 0.23, mix(0.54, 0.94, opening), storm_light); // 雪墙保留明暗变化，密处也有透光。
		vec3 energy = light * transmission; // 已由当前世界雪墙衰减的光幕。
		vec3 emission = energy / (vec3(1.0) + max(energy - vec3(0.50), vec3(0.0))); // 高光软压缩，保留云纹。
		sky += (vec3(1.0) - sky) * emission;
	}
	if (has_storm_clouds) {
		vec4 cloud = texture(clouds, vec2(UV.x - cloud_phase, UV.y)); // 真实前云在光幕之上。
		sky = mix(sky, mix(cloud.rgb, snow_air_color.rgb, sky_scatter), cloud.a * mix(0.33, 1.0, cover));
	}
	vec4 mountain = texture(mountains, UV); // 整幅山体保持原始 UV、比例与透明轮廓。
	float front_relief = smoothstep(0.29, 0.42, UV.y); // 单图前排岩壁多在较低位置，按画布高度近似深度。
	float peak_gap = (1.0 - smoothstep(0.09, 0.25, UV.y)) * opening; // 上方峰顶可能在阵风缝隙短时显露。
	float mountain_scatter = min(0.94, visibility_loss * mix(1.01, 1.34, wall)
		* (1.0 - 0.38 * front_relief) * (1.0 - 0.54 * peak_gap));
	vec3 mountain_air = mix(mountain.rgb, distant_air, mountain_scatter); // 山体融入冷空气，同时真实轮廓挡住极光。
	vec3 landscape = mix(sky, mountain_air, mountain.a); // 山体继续位于极光之前。
	if (snow_has_ridge()) {
		float snowline_depth = world.y - snow_ridge_projection(world.x).x; // 远山底部沿真正雪线被近处空气遮掩。
		landscape = mix(landscape, SNOW_RIDGE_AIR, snow_ridge_haze(snowline_depth, visibility_loss, wall));
	}
	COLOR.rgb = landscape;
}
