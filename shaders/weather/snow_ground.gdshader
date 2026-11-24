// 雪山的雪面材质。补足贴地明暗，再交由原有积雪和压痕路径合成。
shader_type canvas_item;

#include "res://shaders/weather/snow_surface.gdshaderinc"
#include "res://shaders/weather/snow_ground_ridge.gdshaderinc"
#include "res://shaders/weather/snow_storm_fields.gdshaderinc"

uniform vec2 snow_ridge_weather = vec2(0.0); // 当前能见度损失、世界雪墙周期。
uniform sampler2D snow_base_tones : source_color, filter_linear, repeat_disable; // 原图的低频色调，用来分离云状底色和雪纹。
uniform float snow_slab_top = -2500.0; // 落下去的板块只取裂口近端的源图。
uniform float snow_slab_rim = 2500.0; // 原始棋盘纵深，超过近端边界露出裂面。
uniform vec2 snow_lane_span = vec2(0.0); // 真实战区的左右世界界线，相等时关闭行界光影。
uniform vec3 snow_lane_edges = vec3(0.0, 0.0, 1.0); // 展平后的首末内侧行界及行距，单位为世界像素。
varying vec2 ground_world; // 当前雪面片元的世界位置。
varying vec4 ground_tint; // 取边缘补色时沿用精灵的颜色和透明度。

void vertex() {
	snow_surface_uv = snow_surface_vertex(VERTEX);
	ground_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	ground_tint = COLOR;
}

// 静止的地表样本。纹理由坡面投影定位，不与镜头或天气时钟绑定。
float snow_form_hash(vec2 cell) {
	vec3 p = fract(vec3(cell.x, cell.y, cell.x) * vec3(0.1031, 0.11369, 0.13787)); // 以网格编号生成固定雪堆高度。
	p += vec3(dot(p, p.yzx + vec3(19.19)));
	return fract((p.x + p.y) * p.z);
}

// 返回雪堆的高度和局部梯度。梯度提供迎光面与背风面，不需额外法线贴图。
vec3 snow_form(vec2 uv) {
	vec2 cell = floor(uv); // 当前不规则风积网格。
	vec2 f = fract(uv); // 当前样本在网格内的位置。
	vec2 t = f * f * (3.0 - 2.0 * f); // 高度插值在各格边界连续。
	vec2 rate = 6.0 * f * (1.0 - f); // 高度插值的一阶导数。
	float a = snow_form_hash(cell); // 左上角高度。
	float b = snow_form_hash(cell + vec2(1.0, 0.0)); // 右上角高度。
	float c = snow_form_hash(cell + vec2(0.0, 1.0)); // 左下角高度。
	float d = snow_form_hash(cell + vec2(1.0)); // 右下角高度。
	return vec3(mix(mix(a, b, t.x), mix(c, d, t.x), t.y),
		mix(b - a, d - c, t.y) * rate.x, mix(c - a, d - b, t.x) * rate.y);
}

// [paint] 保留原图的雪纹。[along] 是展平坡面后的纵深，[side_heights] 是左右各 32 世界像素处的坡高。
vec3 snow_terrain_light(vec3 paint, float along, vec2 side_heights) {
	vec2 coords = vec2(ground_world.x / 260.0 + along / 535.0, along / 136.0 - ground_world.x / 720.0); // 沿主风方向拉长雪堆。
	vec3 dunes = snow_form(coords); // 延伸到整个坡体的雪堆明暗。
	vec3 drifts = snow_form(coords * vec2(2.35, 1.83) + vec2(6.14, 8.41)); // 错开细一些的风积雪纹。
	float relief = clamp((dunes.x - 0.5) * 0.11 + dot(dunes.yz, vec2(0.10, -0.125))
		+ dot(drifts.yz, vec2(0.023, -0.041)), -0.18, 0.15); // 明暗变化限制在原雪色周围。
	float slope = (side_heights.x - side_heights.y) / 64.0; // 平滑穿过坡脚和坡顶，不画出直线色块。
	float slope_light = smoothstep(0.015, 0.44, slope) * 0.07; // 迎光坡比平台略亮。
	float near_light = mix(0.936, 1.03, smoothstep(145.0, 620.0, along)); // 近处雪面更实，远处略隐入空气。
	vec3 lit = paint * (near_light + slope_light + relief); // 合成纵深、坡向与小尺度起伏。
	return mix(lit, lit * vec3(0.90, 0.96, 1.01), max(-relief * 1.6, 0.0)); // 背风浅沟保留偏蓝的柔和阴影。
}

// 在真实行界的雪面上加一层迎光雪脊和背风浅影，保留底图纹理。
vec3 snow_lane_light(vec3 snow, float along) {
	float x = ground_world.x; // 与棋盘列界共用世界横坐标。
	if (x <= snow_lane_span.x || x >= snow_lane_span.y) {
		return snow;
	}
	float row = floor((along - snow_lane_edges.x) / snow_lane_edges.z + 0.5); // 最近内侧行界的序号。
	float edge = snow_lane_edges.x + row * snow_lane_edges.z; // 未下沉时的展平纵深。
	if (edge < snow_lane_edges.x || edge > snow_lane_edges.y + 0.25
			|| edge <= snow_slab_top + 0.25 || edge >= snow_slab_rim - 0.25) {
		return snow; // 外缘和脱落板块的断口由裂面负责。
	}
	float gap = along - edge; // 正值朝向镜头，留给积雪的背光侧。
	if (abs(gap) > 12.0) {
		return snow;
	}
	float phase = x * 0.019 + edge * 0.058; // 各行固定而错开的风纹相位。
	gap += sin(phase) * 1.15 + sin(x * 0.047 - edge * 0.031) * 0.45;
	float crest = 1.0 - smoothstep(0.0, 4.4, abs(gap + 1.35)); // 窄亮边向两侧柔化。
	float lee = smoothstep(-0.65, 3.0, gap) * (1.0 - smoothstep(3.2, 10.4, gap)); // 稍宽的冷蓝薄影。
	float ends = smoothstep(0.0, 77.0, x - snow_lane_span.x)
		* smoothstep(0.0, 87.0, snow_lane_span.y - x); // 两端融入雪地，避免形成棋盘外框。
	float strength = ends * (0.86 + 0.14 * sin(phase * 0.57)); // 长向轻微明暗变化保留风积感。
	return snow + (vec3(0.035, 0.042, 0.046) * crest - snow * vec3(0.077, 0.062, 0.046) * lee) * strength;
}

// 雪壳下露出有层理的深色冰岩。沿真实裂线接上碎雪和向下衰减的吹雪。
vec3 snow_fracture_face(float depth, vec3 snow) {
	vec2 rock = vec2(ground_world.x * 0.032 + depth * 0.006, depth * 0.023);
	float variation = snow_form(rock).x;
	float layer_fold = snow_form(vec2(rock.x * 0.52, rock.y * 1.34 + 12.0)).x;
	float bedding = 0.5 + 0.5 * sin(depth * 0.24 + layer_fold * 6.2);
	float groove = smoothstep(0.81, 0.98, bedding) * smoothstep(0.16, 0.57, variation);
	// 原地板的实雪纹保留在冰岩上，裂口下面加冷灰层理和稀薄背光。
	vec3 rock_color = mix(snow * vec3(0.67, 0.76, 0.83), vec3(0.39, 0.53, 0.66), 0.47);
	rock_color *= 0.91 + variation * 0.23 - groove * 0.14;
	float ledge = 1.0 - smoothstep(2.5, 10.0 + variation * 6.4, depth);
	rock_color = mix(rock_color, min(vec3(1.0), snow * vec3(0.94, 1.04, 1.13)), ledge);
	float air = smoothstep(23.0, 185.0, depth);
	return mix(rock_color, SNOW_RIDGE_AIR * 0.88, air * (0.64 + layer_fold * 0.17));
}

void fragment() {
	vec4 paint = COLOR; // 原图和精灵自色。
	float brightness = max(paint.r, max(paint.g, paint.b)); // 动态粉雪的原图容量提示。
	if (!snow_has_ridge()) {
		float coverage = smoothstep(0.06, 0.42, brightness); // 无连续雪线的素材仍按原方式渲染。
		COLOR = vec4(snow_surface_color(paint.rgb / max(coverage, 0.5), brightness), paint.a * coverage);
	} else {
		vec2 elevations = snow_ridge_projection(ground_world.x); // 同一份实测轮廓和棋盘坡面。
		float depth = ground_world.y - elevations.x; // 沿绘制方向到山脊的有符号距离。
		float along = ground_world.y - snow_ridge_descent - elevations.y; // 雪纹和行界随实际坡段及沉降移动。
		float coverage = smoothstep(-0.65, 4.9, depth); // 羽化几像素去掉硬边，不移动雪面主体。
		float rim = -1e4; // 完整雪坡走原有材质路径。
		if (snow_slab_top > -2000.0 || snow_slab_rim < 2000.0) {
			float ragged = (snow_form(vec2(ground_world.x * 0.040, 4.2)).x - 0.5) * 9.0;
			float snow_level = along + ragged;
			coverage *= smoothstep(snow_slab_top - 0.6, snow_slab_top + 2.1, snow_level);
			rim = snow_level - snow_slab_rim;
		}
		// 片元处理器用分支输出颜色，雪线以上透明以露出天空。
		if (coverage > 0.0) {
			float edge = 1.0 - smoothstep(1.0, 10.0, depth); // 只在带黑底的雪线边缘从实雪恢复颜色。
			if (edge > 0.0) {
				vec4 clean_snow = texture(TEXTURE, UV + vec2(0.0, 8.0 * TEXTURE_PIXEL_SIZE.y)) * ground_tint; // 从雪线下方取实雪颜色。
				paint = mix(paint, clean_snow, edge);
			}
			vec3 diffuse = paint.rgb; // 原图细节随坡面受光。
			if (depth > 28.0) {
				vec3 base_tone = texture(snow_base_tones, snow_surface_uv).rgb * ground_tint.rgb; // 从低频底色中分离细雪纹。
				vec3 snow_tone = vec3(0.54, 0.64, 0.75) * ground_tint.rgb; // 将显眼的格状色块收回到环境雪色。
				diffuse = max(vec3(0.0), diffuse + (snow_tone - base_tone) * (0.59 * smoothstep(28.0, 82.0, depth)));
			}
			vec2 side_heights = vec2(snow_ridge_projection(ground_world.x - 32.0).y,
				snow_ridge_projection(ground_world.x + 32.0).y); // 坡脚两侧的样本也用于雪脊过渡。
			vec3 lit = snow_terrain_light(diffuse, along, side_heights); // 地表明暗先于脚印和新雪。
			if (rim <= 0.0) {
				float softened = mix(elevations.y, (side_heights.x + side_heights.y) * 0.5, 0.44); // 仅柔化坡段接缝的积雪轮廓。
				lit = snow_lane_light(lit, along + elevations.y - softened);
			}
			vec3 snow = snow_surface_color(lit, brightness); // 脚印和附着新雪仍盖在地表起伏之上。
			if (depth < 96.0) {
				float wall = snow_wall_field(ground_world, snow_ridge_weather.y); // 与背后天幕共享的风雪遮蔽。
				snow = mix(snow, SNOW_RIDGE_AIR, snow_ridge_haze(depth, snow_ridge_weather.x, wall));
			}
			if (rim > 0.0) {
				snow = snow_fracture_face(rim, snow);
			}
			COLOR = vec4(snow, paint.a * coverage);
		} else {
			COLOR = vec4(0.0);
		}
	}
}
