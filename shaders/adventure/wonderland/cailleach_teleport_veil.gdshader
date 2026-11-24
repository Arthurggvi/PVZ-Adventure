// 随暴雪推进的白雾、漫射光和局部镜头失焦。沿风轴拉长雾体和真实画面的采样。
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D battle_image : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 viewport_size = vec2(1066.0, 600.0);
uniform vec2 focus_px = vec2(0.0);
uniform vec2 fog_radius = vec2(280.0, 210.0);
uniform vec2 wind_axis = vec2(-1.0, 0.0);
uniform float wind_travel = 0.0;
uniform float mist = 0.0;
uniform float glow = 0.0;
uniform float wake = 0.0;

// 给连续的雾带取低频值噪声。格点不随屏幕尺寸或帧号跳动。
float mist_hash(vec2 cell) {
	vec3 p = fract(cell.xyx * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float mist_noise(vec2 p) {
	vec2 cell = floor(p); // 四角采样保留跨格连续性。
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(p)); // 格内缓动。
	float top = mix(mist_hash(cell), mist_hash(cell + vec2(1.0, 0.0)), blend.x);
	float bottom = mix(mist_hash(cell + vec2(0.0, 1.0)), mist_hash(cell + vec2(1.0)), blend.x);
	return mix(top, bottom, blend.y);
}

void fragment() {
	vec2 crosswind = vec2(wind_axis.y, -wind_axis.x); // 与流向垂直的轴。
	vec2 offset_px = SCREEN_UV * viewport_size - focus_px; // 以原画中心为局部雾心。
	vec2 air = vec2(dot(offset_px, wind_axis), dot(offset_px, crosswind)) / fog_radius;
	float travel = wind_travel / fog_radius.x; // 平流距离换成雾体局部尺度。
	vec2 current = air - vec2(travel, 0.0); // 雾纹随真实风场推进。
	float swelling = mist_noise(current * vec2(2.3, 4.1) + vec2(3.7, 1.1)); // 慢变的大团雾。
	float eddy = mist_noise(current * vec2(4.7, 12.0) + vec2(-4.5, 6.8)); // 更薄的密度褶皱。

	// 近身雾受风推向下游，贴地雾带在人物隐去后仍往前流。
	vec2 body = air - vec2(wake * 0.57, -0.04 + (swelling - 0.5) * 0.34);
	vec2 tail = (air - vec2(0.39 + wake * 0.68, 0.46 + (eddy - 0.5) * 0.25)) * vec2(0.67, 2.65);
	float folds = smoothstep(0.25, 0.77, 0.41 * swelling + 0.59 * eddy); // 雾褶之间留出能看见轮廓和雪片的薄处。
	float cloud = exp2(-2.65 * dot(body, body)) * (0.32 + 0.30 * swelling + 0.47 * folds);
	float streamer = exp2(-2.35 * dot(tail, tail)) * (0.10 + 0.47 * eddy);
	float diffusion = mist * (cloud + streamer); // 有厚度的白雾，同时决定局部失焦。
	float bloom = glow * exp2(-3.4 * dot(air * vec2(0.83, 1.02), air * vec2(0.83, 1.02)));
	if (diffusion + bloom < 0.004) {
		discard;
	}

	float focus_loss = clamp(diffusion * 1.19 + bloom * 0.24, 0.0, 1.0);
	vec2 smear = wind_axis * (12.0 * focus_loss) / viewport_size;
	float lod = 4.05 * focus_loss; // 原画、地面和世界雪片一起散焦。
	vec3 sharp = textureLod(battle_image, SCREEN_UV, 0.0).rgb;
	vec3 soft = 0.54 * textureLod(battle_image, SCREEN_UV, lod).rgb
		+ 0.23 * textureLod(battle_image, SCREEN_UV - smear, lod).rgb
		+ 0.23 * textureLod(battle_image, SCREEN_UV + smear, lod).rgb;
	vec3 scene = mix(sharp, soft, focus_loss * 0.91);
	float white_mist = 1.0 - exp(-1.47 * diffusion); // 透射率在边缘自然回到原画。
	vec3 scatter = mix(vec3(0.899, 0.945, 0.983), vec3(0.995, 0.995, 1.0), 0.34 + 0.63 * bloom);
	scene = mix(scene, scatter, white_mist);
	scene += max(vec3(0.0), vec3(1.0) - scene) * (0.37 * bloom); // 雾内柔和泛光。
	COLOR = vec4(scene, 1.0);
}
