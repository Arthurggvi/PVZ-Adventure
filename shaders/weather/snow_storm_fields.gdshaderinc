// 天空和中景共用的低频雪墙。每 2048 世界像素横向无缝回绕。
float snow_wall_hash(vec2 cell) {
	vec3 p = fract(vec3(mod(cell.x, 8.0), cell.y, mod(cell.x, 8.0)) * vec3(0.1031, 0.11369, 0.13787)); // X 方向八格一圈。
	p += vec3(dot(p, p.yzx + vec3(19.19)));
	return fract((p.x + p.y) * p.z);
}

// world 是世界像素，travel 是本场风推移的一圈比例。0 表示雪墙开口，1 表示密层。
float snow_wall_field(vec2 world, float travel) {
	float phase = world.x / 2048.0 - travel; // 世界与天空共享同一横向采样位置。
	vec2 coord = vec2(phase * 8.0, world.y / 170.0 + 0.40 * sin(TAU * phase * 2.0)); // 拉长并弯曲风带。
	vec2 cell = floor(coord); // 当前低频噪声格。
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(coord)); // 保证跨格连续。
	float a = mix(snow_wall_hash(cell), snow_wall_hash(cell + vec2(1.0, 0.0)), f.x); // 上沿密度。
	float b = mix(snow_wall_hash(cell + vec2(0.0, 1.0)), snow_wall_hash(cell + vec2(1.0)), f.x); // 下沿密度。
	return mix(a, b, f.y);
}
