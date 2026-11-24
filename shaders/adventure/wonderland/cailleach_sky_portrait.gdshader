// 原画和雪脊卷雾处于同一远景深度，共享天幕的极光、雪墙和真实山形。
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

#include "res://shaders/weather/snow_ground_ridge.gdshaderinc"
#include "res://shaders/weather/snow_storm_fields.gdshaderinc"

// 当前帧在同一页素材中的范围，小位移采样不会越过图集边界。
uniform vec4 frame_uv = vec4(0.0, 0.0, 1.0, 1.0);
// 视口与山体原画在世界坐标中的起点和宽高。
uniform vec4 world_view = vec4(0.0, 0.0, 1332.5, 750.0);
uniform vec4 sky_bounds = vec4(0.0, 0.0, 1332.5, 750.0);
// 能见度损失、雪墙世界位移和极光明灭。
uniform vec3 storm;
// 两次取样共用一张原有关卡风雾，近侧雪脊只多绘制一条低云。
uniform sampler2D blowing_snow : filter_linear, repeat_enable;
uniform sampler2D mountains : filter_linear, repeat_disable;
uniform bool has_mountains = false;
uniform bool ridge_veil = false;
// 「愠怒」期间从远景原画过渡到雪雾中的白影，同一参数也加厚雪脊卷雾。
uniform float anger_veil : hint_range(0.0, 1.0) = 0.0;
// 死亡时沿风向消隐；用于雪脊卷雾时随本场的停雪进度衰减。
uniform float departure_dissolve : hint_range(0.0, 1.0) = 0.0;
// 死亡落星期间只在身体与相邻轮廓上闪出的冷白光。
uniform float death_glow : hint_range(0.0, 1.0) = 0.0;
// 继承精灵淡出，不改变内部光学密度。
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// 每次边缘取样都留在当前帧内，透明样本以预乘颜色送回。
vec4 portrait_sample(sampler2D source, vec2 uv, vec2 texel) {
	vec2 gutter = texel * 0.51; // 防止相邻动画帧串色。
	vec4 art = texture(source, clamp(uv, frame_uv.xy + gutter, frame_uv.zw - gutter)); // 当前帧的色与覆盖率。
	return vec4(art.rgb * art.a, art.a);
}

// 原画上端保留夜空的冷暗调，较低的披风和雪线之间留出较厚的空气。
vec3 winter_light(vec3 art, vec2 frame, float distance_to_ridge, float wall, float aurora) {
	float luminance = dot(art, vec3(0.2126, 0.7152, 0.0722)); // 原画明暗保留，紫灰基色改由实景天光定调。
	vec3 night = mix(vec3(0.145, 0.214, 0.277), vec3(0.76, 0.84, 0.89), pow(luminance, 1.27));
	night += (art - vec3(luminance)) * 0.12;
	vec3 reflected_light = vec3(0.075, 0.22, 0.185) * aurora; // 左侧极光落在衣纹及发丝。
	night += reflected_light * (0.44 + 0.56 * luminance);
	float horizon = 1.0 - smoothstep(14.0, 250.0, max(0.0, distance_to_ridge)); // 向雪脊逐步压低远景反差。
	float scatter = (0.055 + 0.18 * storm.x) * (0.55 + 0.60 * wall)
		+ horizon * (0.12 + 0.18 * wall);
	vec3 air = mix(vec3(0.35, 0.48, 0.60), SNOW_RIDGE_AIR, horizon);
	vec3 color = mix(night, air + reflected_light * 0.23, scatter);
	vec2 eye = (frame - vec2(0.485, 0.224)) / vec2(0.061, 0.049); // 保留原画亮眼的亮度。
	float eye_light = (1.0 - smoothstep(0.12, 1.0, dot(eye, eye))) * smoothstep(0.70, 0.97, luminance);
	return mix(color, vec3(0.83, 0.99, 1.0), eye_light * 0.76);
}

// 低云延续场景的世界风，既掠过人物也掠过其两侧的真实天空。
vec4 drifting_veil(vec2 world, float distance_to_ridge, float wall, float aurora) {
	float band = smoothstep(-12.0, 15.0, distance_to_ridge)
		* (1.0 - smoothstep(49.0, 164.0 + 40.0 * wall + 82.0 * anger_veil, distance_to_ridge));
	float surge = (1.0 - smoothstep(0.0, 53.0, abs(distance_to_ridge)));
	vec2 air_uv = vec2(world.x / 2048.0 - storm.y, distance_to_ridge / 256.0); // 世界雪墙回绕时两路纹理也回到原位。
	float low = texture(blowing_snow, vec2(air_uv.x * 2.0, 0.58 - air_uv.y * 0.52)).a; // 连续低云保留原素材的涡流。
	float high = texture(blowing_snow, vec2(air_uv.x * 4.0 + 0.37,
		0.74 - air_uv.y * 0.77)).a; // 上方疏云从不同区域穿过。
	float depth = (band * (low * 3.25 + high * 1.9) + surge * low * 1.7)
		* (0.50 + 0.64 * storm.x + 0.56 * anger_veil);
	float opacity = (1.0 - exp2(-depth)) * (0.78 + 0.18 * wall);
	vec3 cloud = mix(SNOW_RIDGE_AIR, vec3(0.72, 0.83, 0.89), smoothstep(0.02, 0.43, low + high));
	cloud += vec3(0.01, 0.07, 0.05) * aurora;
	return vec4(cloud * opacity, opacity);
}

vec4 draw_portrait(sampler2D art, vec2 uv, vec2 texel, vec2 world, float gap, float wall, float aurora) {
	vec4 portrait = portrait_sample(art, uv, texel);
	float edge = fwidth(portrait.a); // 仅透明轮廓附近需要额外样本。
	vec2 spread = max(fwidth(uv) * 0.92, texel * 0.85); // 以实际屏幕像素宽度重建帽缘。
	if (edge > 0.018) {
		vec2 horizontal = vec2(spread.x, 0.0); // 横向邻域。
		vec2 vertical = vec2(0.0, spread.y); // 纵向邻域。
		portrait = portrait * 0.50 + 0.125 * (portrait_sample(art, uv - horizontal, texel)
			+ portrait_sample(art, uv + horizontal, texel)
			+ portrait_sample(art, uv - vertical, texel)
			+ portrait_sample(art, uv + vertical, texel));
	}
	float scattering = max(anger_veil, death_glow); // 白影与死亡泛光共用同一组轮廓采样。
	float blurred = portrait.a; // 静态待机不读取大半径轮廓。
	if (scattering > 0.001 && portrait.a < 0.997) {
		vec2 offset = texel * (8.0 + 9.0 * scattering);
		vec2 wind = vec2(offset.x, offset.y * -0.24);
		vec2 lift = vec2(offset.x * 0.18, offset.y * 0.77);
		blurred = portrait.a * 0.29 + 0.1775 * (portrait_sample(art, uv + wind, texel).a
			+ portrait_sample(art, uv - wind, texel).a
			+ portrait_sample(art, uv + lift, texel).a
			+ portrait_sample(art, uv - lift, texel).a);
	}
	if (max(portrait.a, blurred * scattering) <= 0.026) {
		return vec4(0.0);
	}
	vec2 frame = (uv - frame_uv.xy) / max(frame_uv.zw - frame_uv.xy, texel); // 以本帧轮廓辨认脸与披风两侧。
	vec3 color = winter_light(portrait.rgb / max(portrait.a, 0.01), frame, gap, wall, aurora);
	float coverage = smoothstep(0.12, 0.94, portrait.a) * tint.a; // 压下透明边上的浅色杂点。
	if (anger_veil > 0.001) {
		float clearing = smoothstep(0.21, 0.82, wall); // 继承真实掠过身体的雪墙，在近雾疏处看到白影。
		float shell = smoothstep(0.07, 0.96, blurred) * (0.69 - 0.26 * clearing);
		vec3 snow_light = mix(vec3(0.79, 0.87, 0.94), vec3(0.99, 1.0, 1.0), 1.0 - clearing * 0.54);
		coverage = mix(coverage, shell * tint.a, anger_veil);
		color = mix(color, snow_light, anger_veil);
	}
	float halo = 0.0; // 仅在亮起时向轮廓外散射，保留披风和帽檐的原有明暗。
	if (death_glow > 0.001) {
		float detail = dot(color, vec3(0.2126, 0.7152, 0.0722)); // 发丝和积雪更早达到白色。
		color = mix(color, vec3(0.97, 0.991, 1.0), death_glow * mix(0.61, 0.91, detail));
		halo = max(0.0, blurred - portrait.a) * death_glow * 0.61 * tint.a;
	}
	float cap = 0.049 + 0.024 * wall + 0.012 * sin(frame.x * 34.0 + wall * 5.0); // 原图顶端已裁切，帽顶边缘消隐在不同厚度的雪云中。
	float visible = smoothstep(0.002, cap, frame.y); // 白光与本体共享山和雪的遮挡。
	if (has_mountains) {
		vec2 peak_uv = (world - sky_bounds.xy) / sky_bounds.zw; // 前一层天幕实际使用的山体位置。
		float outside_face = smoothstep(0.20, 0.43, abs(frame.x - 0.53)); // 两翼落在山后，脸维持连续深度。
		float overlap = texture(mountains, peak_uv).a * outside_face;
		visible *= 1.0 - smoothstep(0.10, 0.92, overlap) * 0.88;
	}
	if (departure_dissolve > 0.001) {
		float tuft = frame.x + wall * 0.25 + sin(frame.y * 23.0 + wall * 4.6) * 0.079; // 帽檐和披风先后被同一面雪墙扫过。
		float snow_front = mix(1.52, -0.42, departure_dissolve); // 退场由右侧迎风面卷向左侧。
		visible *= (1.0 - smoothstep(snow_front - 0.16, snow_front + 0.16, tuft))
			* (1.0 - 0.38 * departure_dissolve);
	}
	vec4 body = vec4(color * tint.rgb * coverage, coverage); // 预乘颜色与边缘散射合成在同一个画布。
	return (body + vec4(vec3(0.72, 0.90, 1.0) * halo, halo) * (1.0 - coverage)) * visible;
}

void fragment() {
	vec2 world = world_view.xy + SCREEN_UV * world_view.zw; // 同一镜头投影供雪线和中间画布使用。
	float gap = snow_has_ridge() ? snow_ridge_projection(world.x).x - world.y : 260.0; // 雪线以上的真实距离。
	if (ridge_veil && (gap <= -53.0 || gap >= 204.0 + 82.0 * anger_veil)) {
		discard; // 雾带外不计算雪墙或读取两次风雾贴图。
	}
	float wall = snow_wall_field(world, storm.y); // 原场景中推进的暴雪波形。
	float aurora = (1.0 - smoothstep(0.16, 0.77, SCREEN_UV.x))
		* (0.58 + 0.42 * storm.z) * (1.0 - 0.32 * wall); // 从极光开口的一侧照向脸部。
	if (ridge_veil) {
		COLOR = drifting_veil(world, gap, wall, aurora) * tint.a * (1.0 - departure_dissolve);
	} else {
		COLOR = draw_portrait(TEXTURE, UV, TEXTURE_PIXEL_SIZE, world, gap, wall, aurora);
	}
}
