shader_type canvas_item;
render_mode unshaded, blend_disabled;

// 由本次施放的 BackBufferCopy 提供，已经包含地形、敌我、天气和本关照明。
uniform sampler2D battle_image : hint_screen_texture, repeat_disable, filter_linear;
// 施放时为 1，到期为 0。
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// 已经过的战斗秒；开启暂停时保持原样。
uniform float seconds = 0.0;

// 按视口比例矫正后的中心，偏向战场主体并避开左上方卡槽。
const vec2 FOCUS = vec2(0.54, 0.55);
// 黄铜镜片的高光。
const vec3 GOLD = vec3(0.99, 0.79, 0.44);
// 边缘双影的冷钢色。
const vec3 STEEL = vec3(0.54, 0.68, 0.90);

void fragment() {
	vec2 uv = SCREEN_UV; // 当前像素在视口中的坐标。
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0); // 横竖镜片保持圆形。
	vec2 point = (uv - FOCUS) * aspect; // 以战场主体为中心的等比坐标。
	float radius = length(point); // 当前像素到镜心的距离。
	vec2 radial = point / max(radius, 0.001) / aspect; // 换回屏幕坐标后沿径向分离采样。
	float weight = pow(strength, 1.15); // 后半段逐步恢复，最后一秒只留轻微边缘余韵。
	float edge = smoothstep(0.23, 0.77, radius); // 中央保留落点可读性。
	float controls = mix(0.47, 1.0, smoothstep(0.085, 0.26, uv.y)); // 顶部卡槽保留更接近原色的对比度。

	float opening = 1.0 - smoothstep(0.10, 1.06, seconds); // 只在起手扫一次，淡出后保留稳定变色。
	float front = mix(0.05, 1.06, smoothstep(0.02, 1.08, seconds)); // 冲击环从镜心赶向外缘。
	float ripple = exp(-pow(abs(radius - front) * 27.0, 2.0)) * opening; // 窄环避免扫过时大面积遮挡。
	float drift = 0.78 + 0.22 * cos(seconds * 0.94 - radius * 5.5); // 慢速呼吸，方向和相位连续。
	vec2 offset = radial * (edge * drift * 0.011 + ripple * 0.012) * weight * controls; // 双层玻璃仅在边缘轻微错位。
	vec3 source = textureLod(battle_image, uv, 0.0).rgb; // 原场景颜色也用于完整复原。
	vec3 outside = textureLod(battle_image, uv + offset, 0.0).rgb; // 外侧镜像。
	vec3 inside = textureLod(battle_image, uv - offset * 0.55, 0.0).rgb; // 内侧反射。
	vec3 refracted = source * 0.74 + outside * 0.17 + inside * 0.09; // 画面主体保留在回声之上。
	float luma = dot(refracted, vec3(0.2126, 0.7152, 0.0722)); // 按实际亮度分离阴影和暖高光。
	vec3 palette = mix(vec3(0.64, 0.77, 1.10), vec3(1.12, 0.90, 0.72), smoothstep(0.16, 0.85, luma)); // 冷暗部配钟铜色亮点。
	vec3 graded = (mix(refracted, vec3(luma), 0.55) * palette + vec3(0.025, 0.018, 0.037)) * (1.0 - 0.22 * edge); // 边缘压暗以凸显战场中央。

	float angle = atan(point.y, point.x + 0.00001); // 镜片边缘的高光沿圆周缓慢扫动。
	float glint = pow(0.5 + 0.5 * cos(angle + seconds * 0.73 + 0.6), 10.0); // 柔化角度端点。
	float rim = exp(-pow(abs(radius - 0.59) * 164.0, 2.0)); // 只留一圈窄边。
	graded += GOLD * (ripple * 0.095 + rim * glint * 0.115);
	graded += STEEL * exp(-pow(abs(radius - 0.64) * 120.0, 2.0)) * glint * 0.052;
	COLOR = vec4(mix(source, graded, weight * controls), 1.0);
}
