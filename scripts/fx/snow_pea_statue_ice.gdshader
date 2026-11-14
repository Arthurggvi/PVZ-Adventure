// 以原画透明轮廓约束冰壳；只改变材质，不使用矩形遮罩覆盖角色。
shader_type canvas_item;
render_mode unshaded;

// 结晶从脚底上升的归一化进度，完成后保持 1。
uniform float formation : hint_range(0.0, 1.0) = 0.0;
// 当前冰雕的世界纵向上下界，适配不同体型和定格姿势。
uniform vec2 vertical_bounds = vec2(0.0, 100.0);
// 分件共享世界坐标，使相邻肢体的切面与结晶前沿保持连续。
varying vec2 ice_position;
// 保存画布乘色；片元阶段的 COLOR 已含纹理，不能再乘一次原画。
varying vec4 item_tint;

void vertex() {
	ice_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	item_tint = COLOR;
}

void fragment() {
	// 原画仍保留眼睛、衣褶和面部明暗，冰色不依赖原有减速乘色。
	vec4 source = texture(TEXTURE, UV);
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 icy = mix(source.rgb, vec3(luminance) * vec3(0.66, 0.93, 1.08), 0.72);
	icy += vec3(0.06, 0.14, 0.19);
	// 大而稀疏的三角切面有明暗差，不把身体切成密集网格。
	vec2 lattice = vec2(ice_position.x + ice_position.y * 0.32, ice_position.y) / 37.0;
	vec2 cell = floor(lattice);
	vec2 local = fract(lattice);
	float side = step(local.x, local.y);
	float facet = fract(sin(dot(cell + vec2(side * 0.71, side * 1.37), vec2(127.1, 311.7))) * 43758.5453);
	icy += vec3(0.045, 0.065, 0.075) * (facet - 0.40);
	float seam = (1.0 - smoothstep(0.012, 0.030, abs(local.x - local.y))) * step(0.58, facet);
	icy += vec3(0.16, 0.24, 0.27) * seam;
	// 向透明边缘内侧取样，形成薄霜白边，完全不扩张原画轮廓。
	vec2 pixel = TEXTURE_PIXEL_SIZE * 1.4;
	float neighbor = min(min(texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a,
		texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, pixel.y)).a,
		texture(TEXTURE, UV - vec2(0.0, pixel.y)).a));
	float rim = clamp(source.a - neighbor, 0.0, 1.0);
	icy = mix(icy, vec3(0.80, 0.96, 1.0), rim * 0.70);
	// 冻结前沿短暂泛白；完成后保留清透的静态冰壳，不持续闪烁。
	float front = mix(vertical_bounds.y + 12.0, vertical_bounds.x - 12.0, formation);
	float frozen = smoothstep(front - 9.0, front + 9.0, ice_position.y);
	float glow = (1.0 - smoothstep(0.0, 10.0, abs(ice_position.y - front))) * (1.0 - step(0.99, formation));
	vec3 color = mix(source.rgb * vec3(0.80, 0.94, 1.0), icy, frozen);
	color = mix(color, vec3(0.86, 0.98, 1.0), glow * 0.60);
	COLOR = vec4(color, source.a * mix(1.0, 0.91, frozen)) * item_tint;
}
