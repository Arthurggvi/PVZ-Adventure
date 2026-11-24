// 逐雪粒绘制，只覆盖自身小面积。两组位移由雪场风同步驱动，不读取屏幕纹理。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D flakes : filter_linear, repeat_disable; // 三格原有雪晶图集。
uniform bool lens_blur = false; // 最近层改用大轮廓的多片失焦形状。
uniform vec2 view_origin; // 视口左上角的逻辑坐标。
uniform vec2 reference_size = vec2(1066.0, 600.0); // 以高 600 像素作为视口参照。
uniform float pixel_scale = 1.0; // 参照像素到实际逻辑像素的倍率。
uniform vec2 travel; // 本层按实时速度积分的参照像素位移。
uniform vec2 velocity; // 同一层的当前风速和落速，参照像素每秒。
uniform float age; // 风雪演出的游戏秒。
uniform float strength; // 控制密度与透明度，范围 0..1。
varying flat vec3 flake; // 当前粒子的透明度、图集索引小数和形状变体。

void vertex() {
	vec4 seed = INSTANCE_CUSTOM; // 各雪粒只在入树时取一次独立种子。
	float depth = mix(0.75, 1.24, seed.z); // 每个粒子沿同一风速保持自己的速度视差。
	float speed = length(velocity); // 决定拉丝与朝向，以实际速度响应白闪后的狂风。
	vec2 axis = speed > 1.0 ? velocity / speed : vec2(-1.0, 0.0); // 沿风的长轴。
	vec2 perpendicular = vec2(-axis.y, axis.x); // 雪晶的短轴。
	float curl = sin(age * mix(1.45, 3.3, seed.z) + seed.x * TAU); // 风中粒子有幅度不同的翻卷。
	float drift = lens_blur ? 16.0 : 7.0; // 近旁的运行路径更显著地卷动。
	vec2 wander = vec2(curl * drift * 0.38, curl * drift + age * (seed.z - 0.5) * 22.0); // 与累计风程叠加，不反转飞行方向。
	float padding = lens_blur ? 182.0 : 70.0; // 循环接缝在最长拖尾以外。
	vec2 period = reference_size + vec2(2.0 * padding); // 从一端离屏后才从另一端进入。
	vec2 center = mod(seed.xy * period + travel * depth + wander, period) - vec2(padding); // 一帧换向也不中断当前位置。
	float width = lens_blur ? mix(37.0, 106.0, seed.z * seed.z) : mix(7.0, 19.0, seed.z); // 镜头雪直径上限可达普通雪粒约五倍。
	float shutter = clamp(speed / 1420.0, 0.0, 1.0); // 风速峰值前已有短拖尾。
	float stretch = lens_blur ? mix(1.20, 2.72, shutter) : mix(1.14, 3.80, shutter); // 不同快门长度使两层清晰可分。
	vec2 offset = (axis * VERTEX.x * stretch + perpendicular * VERTEX.y) * width; // 靠近镜头时雪片变宽也变软。
	VERTEX = view_origin + (center + offset) * pixel_scale;
	float coverage = smoothstep(seed.w - 0.13, seed.w + 0.055, strength); // 密度渐入，原有粒子仍沿自己的轨迹。
	float opacity = smoothstep(0.005, 0.18, strength) * coverage; // 强度归零时没有亮点残留。
	flake = vec3(opacity, seed.x, seed.y);
}

void fragment() {
	vec2 p = 2.0 * UV - 1.0; // 以每个雪片中心为原点的形状坐标。
	vec3 tint; // 根据当前层选用较亮的冰晶或透亮的近镜头雪团。
	float alpha; // 两层的各自轮廓，不使用全屏雾色填充。
	if (lens_blur) {
		float curve = (flake.z - 0.5) * 0.58; // 不同雪片的细软翘边。
		vec2 body = p * vec2(1.0, 1.23); // 柔和失焦的主团。
		vec2 tuft = (p - vec2(0.33, curve)) * vec2(1.42, 2.02); // 拖向一侧的雪团碎屑。
		float grain = exp2(-5.2 * dot(body, body)); // 逐层淡出而无矩形边。
		float trail = exp2(-4.8 * dot(tuft, tuft)); // 大雪在快门期间的次级拖尾。
		float taper = (1.0 - smoothstep(0.72, 1.0, abs(p.x))) * (1.0 - smoothstep(0.68, 1.0, abs(p.y))); // 四边在裁切前透明。
		alpha = (grain * 0.55 + trail * 0.21) * taper * mix(0.63, 0.94, flake.y);
		tint = mix(vec3(0.72, 0.85, 0.97), vec3(0.97, 0.99, 1.0), grain);
	} else {
		float cell = floor(flake.y * 2.999); // 原图三格各宽 20 像素。
		vec2 atlas_uv = vec2((cell + mix(0.025, 0.975, UV.x)) / 3.0, UV.y); // 收半源像素避免取到相邻雪晶。
		float crystal = texture(flakes, atlas_uv).a; // 原有冰晶形状，在横风中拉成不同长度。
		float rim = exp2(-5.5 * dot(p, p)); // 亮核外留轻柔的轮廓，避免远处方正的点。
		alpha = (crystal * 0.59 + rim * 0.28) * mix(0.58, 0.91, flake.z);
		tint = mix(vec3(0.68, 0.84, 0.97), vec3(0.94, 0.99, 1.0), crystal);
	}
	COLOR = vec4(tint, alpha * flake.x);
}
