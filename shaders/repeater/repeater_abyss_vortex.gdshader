// 地狱裂隙：有湍流细节的熔火围绕暗核旋入；透明烟焰只覆盖局部，不采样屏幕。
shader_type canvas_item;
render_mode unshaded, blend_mix;

// 可暂停战斗年龄，单位秒。
uniform float age = 0.0;
// 战斗场完整寿命，单位秒。
uniform float lifetime = 5.0;
// 只控制噪声细节与覆盖率，不能改变任何伤害。
uniform int quality = 0;
// 各个裂隙独立错相。
uniform float phase = 0.0;
// 保留外部透明度与颜色调制。
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// 无纹理散列避免大量正弦随机采样。
float hash21(vec2 p) {
	vec2 v = fract(p * vec2(123.34, 456.21)); // 平滑噪声所需的格点随机值。
	v += dot(v, v + 45.32);
	return fract(v.x * v.y);
}

// 连续值噪声，给火焰提供真正的团块与微粒层次。
float noise21(vec2 p) {
	vec2 cell = floor(p); // 格点位置。
	vec2 local = fract(p); // 格内位置。
	vec2 ease = local * local * (3.0 - 2.0 * local); // 保持跨格连续。
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), ease.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), ease.x), ease.y);
}

// 三层湍流，低画质去掉最细层；所有层均为固定次数。
float fire_noise(vec2 p) {
	float value = noise21(p) * 0.57 + noise21(p * 2.03 + vec2(7.8, 4.1)) * 0.28; // 大团火焰与细丝。
	if (quality < 2) {
		value += noise21(p * 4.17 + vec2(2.6, 13.4)) * 0.15;
	}
	return value;
}

// 预乘透明度逐层合成，保留熔火饱和度和透明外缘。
vec4 layer(vec4 back, vec3 ink, float opacity) {
	float alpha = clamp(opacity, 0.0, 1.0); // 每层覆盖率必须有界。
	return vec4(ink * alpha + back.rgb * (1.0 - alpha), alpha + back.a * (1.0 - alpha));
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0; // 裂隙局部坐标。
	float opening = smoothstep(0.015, 0.38, age); // 撕开后再形成卷流。
	float closing = smoothstep(0.0, 0.55, lifetime - age); // 同心坍缩退场。
	float fade = smoothstep(0.0, 0.055, age) * smoothstep(0.0, 0.12, lifetime - age); // 首尾光量连续。
	float size = max(0.035, closing * (0.56 + opening * 0.44)); // 压缩全部火焰与暗核。
	vec2 p = q / size; // 同一生命周期缩放。
	p.x /= max(0.045, opening); // 初始是一条不规则纵向裂缝。
	vec2 disk = vec2(p.x * 0.962 - p.y * 0.272, p.x * 0.272 + p.y * 0.962); // 盘面倾斜，保持纵深。
	float radius = length(p); // 黑核近圆径向距离。
	float angle = atan(p.y, p.x); // 黑核周围火冠的角度。
	float clock = age * 1.8 + phase; // 可暂停流动时间。
	vec2 rim_domain = vec2(cos(angle + clock * 0.23), sin(angle + clock * 0.23)) * 5.7; // 周向无缝噪声。
	float rim_noise = fire_noise(rim_domain + vec2(clock * 0.17, -clock * 0.31)); // 火舌不停侵蚀黑核边缘。
	float horizon = 0.218 + (rim_noise - 0.5) * 0.07; // 黑核缩小并失去均匀圆形。
	float void_mask = 1.0 - smoothstep(horizon - 0.018, horizon + 0.009, radius); // 小区域黑核，外围不铺黑底。
	float rim = exp(-pow((radius - horizon - 0.007) / 0.024, 2.0)); // 白热内焰宽度。
	float corona = exp(-pow((radius - horizon - 0.07 - rim_noise * 0.045) / 0.070, 2.0)); // 厚实而不规则的红色火冠。
	vec2 orbit = vec2(disk.x, disk.y / 0.59); // 厚盘取代像土星环的细椭圆。
	float orbit_radius = length(orbit); // 熔火卷流半径。
	float orbit_angle = atan(orbit.y, orbit.x); // 盘内方位角。
	float turn = orbit_angle + orbit_radius * 4.7 - clock * 0.42; // 向心扭曲纹理域。
	vec2 flow = vec2(cos(turn), sin(turn)) * (orbit_radius * 8.0 + 1.0); // 沿流线拉伸的噪声坐标。
	float turbulence = fire_noise(flow + vec2(clock * 0.31, -clock * 0.20)); // 多尺度熔火体积细节。
	float fibers = noise21(flow * 4.9 + vec2(clock * 0.71, clock * 0.13)); // 细碎火丝与火花。
	float swirl = orbit_angle * 3.0 + orbit_radius * 12.0 - clock * 1.45 + (turbulence - 0.5) * 2.8; // 三股不规则火臂。
	float stream = pow(0.5 + 0.5 * sin(swirl), 1.8); // 宽而柔和的火臂，不是细线环。
	float band = smoothstep(0.17, 0.30, orbit_radius) * (1.0 - smoothstep(0.62, 0.95, orbit_radius)); // 两端收束且边缘透明。
	float body = band * stream * smoothstep(0.15, 0.70, turbulence); // 火焰块体密度。
	float smoke = band * (0.20 + stream * 0.80) * smoothstep(0.22, 0.72, turbulence); // 气体只跟随火臂。
	float heat = smoothstep(0.35, 0.83, turbulence + fibers * 0.18); // 炽热细节分布。
	float front = smoothstep(-0.035, 0.13, disk.y); // 前半火焰跨过核下缘。
	vec3 flame = mix(vec3(0.59, 0.025, 0.055), vec3(1.0, 0.32, 0.045), heat); // 深红阴影到橙红火焰。
	flame = mix(flame, vec3(1.0, 0.78, 0.30), heat * heat * (0.55 + 0.30 * fibers)); // 热团内部熔金高光。
	vec4 result = vec4(0.0); // 预乘叠加结果。
	result = layer(result, vec3(0.16, 0.018, 0.095), smoke * 0.50 + corona * 0.11); // 透明炭紫烟边衬托火焰。
	result = layer(result, flame, body * (1.0 - front) * 0.94); // 后方火焰先绘制。
	result = layer(result, vec3(0.013, 0.003, 0.019), void_mask * 0.97); // 小黑核截住后方火臂。
	result = layer(result, vec3(0.78, 0.055, 0.028), corona * (0.18 + rim_noise * 0.55)); // 红焰有厚度而非描边。
	result = layer(result, mix(vec3(1.0, 0.34, 0.06), vec3(1.0, 0.92, 0.66), rim_noise), rim * 0.96); // 零碎白热内缘。
	result = layer(result, flame, body * front * 0.91); // 前方热气绕过并掩映黑核。
	float grains = smoothstep(0.79, 0.96, fibers) * body; // 少量悬浮白热颗粒，禁止铺满整个画布。
	result = layer(result, vec3(1.0, 0.89, 0.55), grains * 0.82);
	float jet = exp(-pow((disk.y - 0.06 - sin(disk.x * 10.0 + clock) * 0.025) / 0.04, 2.0)); // 非直线的透镜火流。
	jet *= exp(-pow((disk.x - 0.18) / 0.32, 2.0)) * smoothstep(0.12, 0.25, abs(disk.x)) * heat;
	result = layer(result, vec3(1.0, 0.68, 0.24), jet * 0.46); // 小面积不对称亮斑。
	float edge = 1.0 - smoothstep(0.88, 0.99, length(q)); // 四周不出现贴片边缘。
	float crowd = quality == 2 ? 0.78 : 1.0; // 密集效果抑制透明叠加光量。
	COLOR = vec4(result.rgb / max(result.a, 0.001), result.a * fade * edge * crowd) * tint;
}
