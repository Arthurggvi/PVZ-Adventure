// 用和雾体共用的风轴与进度打散原画边缘。保留图集本身的透明度和角色着色。
shader_type canvas_item;
render_mode unshaded;

uniform vec2 viewport_size = vec2(1066.0, 600.0);
uniform vec2 focus_px = vec2(0.0);
uniform vec2 fog_radius = vec2(280.0, 210.0);
uniform vec2 wind_axis = vec2(-1.0, 0.0);
uniform float wind_travel = 0.0;
uniform float presence = 1.0;
uniform float glow = 0.0;

void fragment() {
	vec2 crosswind = vec2(wind_axis.y, -wind_axis.x); // 和镜头雾相同的侧风轴。
	vec2 offset_px = SCREEN_UV * viewport_size - focus_px;
	vec2 air = vec2(dot(offset_px, wind_axis), dot(offset_px, crosswind)) / fog_radius;
	float flow = air.x - wind_travel / fog_radius.x;
	// 交错的软边让披风、头巾与手杖在不同雾层中显隐。
	float folds = 0.13 * sin(air.y * 11.0 + flow * 4.7)
		+ 0.060 * sin(air.y * 22.0 - flow * 11.0);
	float threshold = clamp(0.49 + 0.44 * air.x + folds, 0.19, 0.81);
	float reveal = smoothstep(threshold - 0.175, threshold + 0.175, presence);
	float edge = 4.0 * reveal * (1.0 - reveal); // 只提高被雾切开的薄层亮度。
	vec3 tint = mix(COLOR.rgb, vec3(0.92, 0.966, 1.0), glow * (0.21 + 0.65 * edge));
	COLOR = vec4(tint, COLOR.a * reveal);
}
