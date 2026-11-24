// 同一份原图雪线与坡面投影供天空和地板采样，世界坐标不随镜头重置。
uniform sampler2D snow_ridge : hint_default_black, filter_linear, repeat_disable; // 装配后绑定的一行山脊数据。
uniform vec4 snow_ridge_bounds = vec4(0.0); // 左上原点与世界宽高。宽高为零代表未绑定轮廓。
uniform float snow_ridge_descent = 0.0; // 地板实际位移，天空与地板保持同一雪线。

// 天空远雾与迎风雪脊共享的冷灰空气色。
const vec3 SNOW_RIDGE_AIR = vec3(0.49, 0.61, 0.72);

bool snow_has_ridge() {
	return snow_ridge_bounds.z > 0.0 && snow_ridge_bounds.w > 0.0;
}

// 返回 [world_x] 处原图雪线的世界 Y 与行走坡面的纵向偏移。
vec2 snow_ridge_projection(float world_x) {
	float u = (world_x - snow_ridge_bounds.x) / snow_ridge_bounds.z; // 地板实际画幅的归一化 X。
	vec4 sample_data = texture(snow_ridge, vec2(u, 0.5)); // RG 为雪线，BA 为投影坡面。
	vec2 decode = vec2(256.0, 1.0) * (255.0 / 65535.0); // 先线性过滤再还原高低字节。
	return vec2(snow_ridge_bounds.y + snow_ridge_descent + dot(sample_data.rg, decode) * snow_ridge_bounds.w,
		dot(sample_data.ba, decode) * snow_ridge_bounds.w);
}

// [depth] 是雪线两侧的有符号世界距离，[visibility] 与 [wall] 来自同一场天气。
float snow_ridge_haze(float depth, float visibility, float wall) {
	float gap = abs(depth); // 两侧连续，保留贴近雪脊的短雾和较宽的稀薄雾。
	float core = 1.0 - smoothstep(1.5, 24.0, gap); // 羽化交界的贴地雾芯。
	float bank = 1.0 - smoothstep(8.0, mix(58.0, 96.0, visibility), gap); // 向山体和坡面过渡的稀雾。
	return (core * 0.54 + bank * 0.18) * mix(0.70, 1.0, wall) * mix(0.93, 1.08, visibility);
}
