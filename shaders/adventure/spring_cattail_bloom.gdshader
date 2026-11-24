shader_type canvas_item;
render_mode unshaded;

// 四处格心各有独立的爆裂时刻，末爆偏金。
uniform float age = 0.0;
uniform float fuse_seconds = 0.23;
uniform float ring_gap = 0.135;
uniform vec2 instance_scale = vec2(4.0, 720.0);
varying vec3 beat;

void vertex() {
	float local_age = age - INSTANCE_CUSTOM.r * instance_scale.x; // 负值为蓄光，零为外圈射出。
	beat = vec3(local_age, INSTANCE_CUSTOM.g, INSTANCE_CUSTOM.b);
	VERTEX *= step(-fuse_seconds, local_age) * (1.0 - step(0.62, local_age)); // 只着色当前活动的局部面片。
}

// [radius] 为像素归一化半径，[time] 为本圈离手后的年龄。
float ripple(float radius, float time, float pace) {
	float t = clamp(time / 0.41, 0.0, 1.0); // 第一段迅速打开，末端转薄消散。
	float edge = mix(0.064, pace, 1.0 - pow(1.0 - t, 1.85));
	float ring = 1.0 - smoothstep(0.003, mix(0.034, 0.012, t), abs(radius - edge));
	return ring * step(0.0, time) * (1.0 - t) * (1.0 - t);
}

void fragment() {
	vec2 point = UV - vec2(0.5);
	float time = beat.x;
	float ground = length((point - vec2(0.0, 0.052)) * vec2(1.0, 1.68)); // 地面反光压成透视椭圆。
	float radius = length(point);
	float angle = atan(point.y, point.x);
	float charge = clamp(1.0 + time / fuse_seconds, 0.0, 1.0) * (1.0 - step(0.0, time));
	float fuse_radius = mix(0.143, 0.039, charge); // 细弧向点火位置收束。
	float segments = smoothstep(0.23, 0.76, 0.5 + 0.5 * cos(angle * 5.0 - charge * 3.2));
	float fuse = (1.0 - smoothstep(0.003, 0.012, abs(ground - fuse_radius))) * segments * charge;
	float spark = exp(-radius * mix(38.0, 18.0, charge)) * charge;
	float outer = ripple(radius, time, 0.43);
	float inner = ripple(radius, time - ring_gap, 0.315);
	float burst = exp(-max(time, 0.0) * 16.0) * step(0.0, time); // 每处只亮很短的中心焰芯。
	float core = exp(-radius * 25.0) * burst * 1.8;
	float wash = exp(-ground * 10.0) * burst * 0.66; // 柔和受光仅限格心附近。
	float sector = (angle + 3.14159265) * 1.75 + beat.z * 7.0; // 少量径向碎光打破冲击环的整齐边缘。
	float key = fract(floor(sector) * 0.6180339);
	float shard_at = (0.21 + key * 0.22) * (1.0 - exp(-max(time, 0.0) * 5.0));
	float shard = (1.0 - smoothstep(0.035, 0.16, abs(fract(sector) - 0.5)))
		* exp(-abs(radius - shard_at) * 74.0) * smoothstep(0.0, 0.055, time)
		* (1.0 - smoothstep(0.18, 0.59, time));
	vec3 red_gold = mix(vec3(1.0, 0.26, 0.15), vec3(1.0, 0.63, 0.19), beat.y * 0.83);
	vec3 golden_white = vec3(1.0, 0.92, 0.67);
	float warm = max(fuse * 0.78, max(outer * 0.87 + inner * 0.61, wash));
	float white = max(core, max(spark * 0.88, shard * 0.78));
	float alpha = clamp(warm + white, 0.0, 0.95);
	COLOR = vec4(mix(red_gold, golden_white, white / max(warm + white, 0.001)), alpha);
}
