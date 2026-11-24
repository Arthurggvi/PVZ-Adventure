shader_type canvas_item;
render_mode unshaded;

// 弹道时钟与物理扫掠使用相同单位。
uniform float age = 0.0;
uniform float flight_seconds = 1.71;
uniform float deceleration = 0.105;
uniform vec2 instance_scale = vec2(4.0, 720.0);
varying vec3 needle;

void vertex() {
	float flight = age - INSTANCE_CUSTOM.r * instance_scale.x; // 内外圈各自的离手时间。
	float alive = step(0.0, flight) * (1.0 - step(flight_seconds, flight)); // 折叠尚未出手或已退场的面片。
	float travel = clamp(flight, 0.0, flight_seconds); // Shader 与命中轨迹共用二次减速。
	float offset = INSTANCE_CUSTOM.g * instance_scale.y * travel * (1.0 - deceleration * travel);
	VERTEX.x += offset - 26.0;
	VERTEX *= alive;
	needle = vec3(flight, INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a);
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * vec2(124.0, 48.0) - vec2(26.0, 0.0); // 针心在真实命中轨迹上。
	float reveal = smoothstep(0.0, 0.09, needle.x); // 离心时从焰芯展开轮廓，避免十四枚尖刺挤成实心团。
	float body_scale = mix(0.43, mix(0.91, 0.83, needle.y), reveal);
	vec2 sprite_uv = point / (vec2(34.0, 18.0) * body_scale) + vec2(0.5); // 原版仙人掌尖刺单独采样。
	vec2 sprite_inside = step(vec2(0.0), sprite_uv) * step(sprite_uv, vec2(1.0));
	vec4 sprite = texture(TEXTURE, clamp(sprite_uv, vec2(0.0), vec2(1.0)));
	sprite.a *= sprite_inside.x * sprite_inside.y;
	float tail_length = mix(70.0, 52.0, needle.y) * smoothstep(0.0, 0.15, needle.x) * (1.0 - smoothstep(0.50, 1.50, needle.x) * 0.57); // 主动作有长尾，穿行后缩短。
	float t = clamp((-point.x - 7.0) / max(tail_length, 1.0), 0.0, 1.0);
	float tail = step(point.x, -6.5) * (1.0 - t) * smoothstep(0.001, 0.12, tail_length); // 后端自然收尖。
	float width = mix(3.0, 0.42, t);
	float core = (1.0 - smoothstep(width * 0.3, width + 0.7, abs(point.y))) * tail;
	float haze = exp(-abs(point.y) / (width * 2.5 + 1.0)) * tail * 0.29; // 小尺寸柔辉给拖尾厚度。
	vec3 warm = mix(vec3(1.0, 0.34, 0.25), vec3(1.0, 0.84, 0.40), max(needle.y, needle.z * 0.64));
	vec3 light = mix(warm, vec3(1.0, 0.94, 0.73), core);
	float pigment = max(sprite.r - sprite.g, 0.0); // 只把原画朱红部分换为金色，保留轮廓与反光。
	vec3 body = mix(sprite.rgb, sprite.rgb + vec3(0.08, 0.73, 0.31) * pigment, needle.y * 0.96 + (1.0 - needle.y) * needle.z * 0.25);
	float tail_alpha = max(core * 0.89, haze);
	float opacity = sprite.a + tail_alpha * (1.0 - sprite.a);
	float fade = 1.0 - smoothstep(flight_seconds - 0.22, flight_seconds, needle.x);
	COLOR = vec4(mix(light, body, sprite.a / max(opacity, 0.001)), opacity * fade * (0.45 + 0.55 * reveal));
}
