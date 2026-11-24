shader_type canvas_item;
render_mode unshaded;

// 正交绘制的花田只有一层纯地貌，没有预烘焙的远近尺度。
uniform sampler2D ground_plane : source_color, filter_linear_mipmap, repeat_enable;
// 虚拟相机俯仰、横滚（弧度）和下沉（本关世界像素）。
uniform vec3 view_pose = vec3(0.0);
// 只改变环境垂直视场，单位为半画幅焦距。
uniform float view_focal = 1.73205;
// 整圈等价的虚拟平面相位和地面贴图尺寸。
uniform vec2 ground_motion = vec2(0.0);
uniform vec2 terrain_extent = vec2(3550.0, 5680.0);
// 原天幕覆盖全部战斗机位，天空映射另留姿态采样余量。
uniform vec2 sky_extent = vec2(2093.32, 1046.66);
// 与下方云位置共用左手画布坐标中的地平线和 60° 垂直视场。
const vec2 VIEW_ORIGIN = vec2(620.0, 408.0);
const float HALF_HEIGHT = 428.57;
const float BASE_FOCAL = 1.73205;
const float CAMERA_HEIGHT = 1560.0;
const float HEIGHT_PER_HEAVE = 3.9;
const vec3 ATMOSPHERE = vec3(0.62, 0.77, 0.87);

varying vec2 world_point;
varying vec4 sprite_color;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	sprite_color = COLOR;
}

void fragment() {
	vec2 q = (world_point - VIEW_ORIGIN) / HALF_HEIGHT;
	float bank_sin = sin(view_pose.y);
	float bank_cos = cos(view_pose.y);
	vec2 banked = vec2(bank_cos * q.x - bank_sin * q.y, bank_sin * q.x + bank_cos * q.y);
	float pitch_cos = cos(view_pose.x);
	float pitch_sin = sin(view_pose.x);
	// Godot 画布 Y 向下。把虚拟相机视线还原为 Y 向上的平面坐标。
	vec3 ray = vec3(banked.x, -banked.y * pitch_cos - view_focal * pitch_sin,
			view_focal * pitch_cos - banked.y * pitch_sin);
	float down = -ray.y;
	// 原画只绘制天空和远山。与地面使用同一倾角，但保留天空自己的取样比例。
	vec2 sky_direction = vec2(ray.x, -ray.y) * (BASE_FOCAL / max(ray.z, 0.55));
	vec2 sky_offset = (sky_direction - q) * HALF_HEIGHT / sky_extent;
	vec2 sky_uv = vec2(0.5, 0.534) + (UV - vec2(0.5, 0.534) + sky_offset) * vec2(0.87, 0.92);
	float ground_weight = smoothstep(0.012, 0.162, down);
	// 以未取模的连续坐标计算 mip 梯度。repeat 由纹理处理，地平线处的相交长度有上限。
	float height = CAMERA_HEIGHT - clamp(view_pose.z, -56.0, 56.0) * HEIGHT_PER_HEAVE;
	float ray_scale = height / max(down, 0.048);
	vec2 terrain_uv = ground_motion.xy + ray.xz * ray_scale / terrain_extent;
	vec2 dx = dFdx(terrain_uv);
	vec2 dy = dFdy(terrain_uv);
	vec4 paint;
	if (ground_weight > 0.0) {
		float distance_to_ground = ray_scale * length(ray);
		// 远端低仰角下的纹理过薄，先由可见距离降低地貌对比，再稳定地混入空气色。
		float clear_air = exp(-distance_to_ground / 9400.0) * mix(0.46, 1.0, smoothstep(0.17, 0.65, down));
		vec3 terrain = textureGrad(ground_plane, terrain_uv, dx, dy).rgb;
		paint = vec4(mix(ATMOSPHERE, terrain, clear_air), 1.0);
		if (ground_weight < 1.0) {
			paint = mix(texture(TEXTURE, sky_uv), paint, ground_weight);
		}
	} else {
		paint = texture(TEXTURE, sky_uv);
	}
	COLOR = paint * sprite_color;
}
