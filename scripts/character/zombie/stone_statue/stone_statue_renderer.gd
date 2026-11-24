## 石壳纹理与楔形碎块渲染；正面、石质背面和侧壁分别绘制。
extends RefCounted

## 只在石像视觉脚本被实例化时加载的运动辅助脚本。
const Motion = preload("res://scripts/character/zombie/stone_statue/stone_statue_motion.gd")
## 石像专属小图集的资源目录。
const ASSET_ROOT: String = "res://assets/adventure/zombies/stone_statue/"
## 各款完整壳面在图集中的共同区域，尺寸与站姿及脚底配准一致。
const STATUE_REGION: Rect2 = Rect2(2, 2, 166, 260)
## 各款与碎块分区对应的裂纹区域，绘制时覆盖在壳面上。
const CRACKS_REGION: Rect2 = Rect2(172, 2, 166, 260)

## 只加载 [param skin] 对应的图集和轮廓；缺少资源时记录错误并返回空字典。
static func load_assets(skin: String) -> Dictionary:
	var path: String = ASSET_ROOT + "skin_" + skin # 同名的图集与几何必须成对使用。
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(path + ".json")) # 此皮肤的离线分区。
	if not source is Dictionary or not source.get("parts") is Array:
		push_error("StoneStatue: %s.json 缺失或格式错误" % path)
		return {}
	var atlas: Texture2D = load(path + ".png") as Texture2D # 引擎缓存同一皮肤的底层纹理。
	if atlas == null:
		push_error("StoneStatue: %s.png 加载失败" % path)
		return {}
	var parts: Array[Dictionary] = [] # 本实例的碎块几何，不包含运动状态。
	for raw: Dictionary in source.parts: # 运行时只做一次轻量顶点转换。
		parts.append(_prepare_part(raw, atlas.get_size()))
	return {
		"atlas": atlas,
		"statue": _texture_region(atlas, STATUE_REGION),
		"cracks": _texture_region(atlas, CRACKS_REGION),
		"parts": parts,
	}

## 返回 [param atlas] 中 [param region] 的视图，保留透明边缘而不复制底层像素。
static func _texture_region(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	var texture: AtlasTexture = AtlasTexture.new() # 壳面和裂纹按各自区域绘制。
	texture.atlas = atlas
	texture.region = region
	texture.filter_clip = true
	return texture

## 构建 [param raw] 的前背顶点和图集 UV；[param atlas_size] 的单位为像素。
static func _prepare_part(raw: Dictionary, atlas_size: Vector2) -> Dictionary:
	var rect: Rect2 = _rect(raw.rect) # 正面在图集中的区域。
	var back_rect: Rect2 = _rect(raw.back_rect) # 石质背面的独立区域。
	var origin: Vector2 = Vector2(raw.position[0], raw.position[1]) # 完整石像中的原位置。
	var shift: Vector2 = Vector2(raw.back_shift[0], raw.back_shift[1]) # 背面轻微错位，形成不规则楔形。
	var front: PackedVector3Array = PackedVector3Array() # 局部正面顶点。
	var back: PackedVector3Array = PackedVector3Array() # 比正面更小的背面顶点。
	var front_uv: PackedVector2Array = PackedVector2Array() # 正面纹理坐标。
	var back_uv: PackedVector2Array = PackedVector2Array() # 背面纹理坐标。
	for pair: Array in raw.contour: # 离线已去掉闭合重复点与像素锯齿。
		var point: Vector2 = Vector2(pair[0], pair[1]) # 该顶点在碎块裁图内的位置。
		var centered: Vector2 = point - rect.size * 0.5 # 以物理中心为旋转原点。
		var rear: Vector2 = centered * float(raw.back_scale) + shift # 锥缩后的背面形状。
		front.append(Vector3(centered.x, centered.y, float(raw.thickness) * 0.5))
		back.append(Vector3(rear.x, rear.y, -float(raw.thickness) * 0.5))
		front_uv.append((rect.position + point) / atlas_size)
		back_uv.append((back_rect.position + point) / atlas_size)
	var count: int = front.size() # 每面的顶点数。
	front.append_array(back)
	var stone: Color = Color(raw.stone_rgb[0], raw.stone_rgb[1], raw.stone_rgb[2]) # 普通断面石色。
	return {"rect": rect, "origin": origin, "size": rect.size, "vertices": front, "count": count,
		"front_uv": front_uv, "back_uv": back_uv, "stone": stone}

## 把 JSON 的 [param values] 数组转换为纹理区域。
static func _rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))

## 绘制一块实心石头；[param pose] 与运动碰撞使用相同中心和角度。
## [param canvas] 接收绘制，[param part] 为共享几何，[param atlas] 为前背面图集。
static func draw_piece(canvas: CanvasItem, part: Dictionary, pose: Dictionary, atlas: Texture2D) -> void:
	var center: Vector2 = pose.center # 该块当前的物理中心。
	var angles: Vector3 = pose.angles # 三轴旋转，单位为弧度。
	if angles.length_squared() < 0.000001:
		canvas.draw_texture_rect_region(atlas, Rect2(center - part.size * 0.5, part.size), part.rect)
		return
	var turn: Basis = Motion.rotation(angles) # 与接地检测共用变换。
	var points: PackedVector3Array = PackedVector3Array() # 旋转后的局部三维顶点。
	for vertex: Vector3 in part.vertices: # 不在运行时修改共享几何。
		points.append(turn * vertex)
	var light: Vector3 = Vector3(-0.45, -0.65, 0.75).normalized() # 统一的左上方软光。
	var count: int = part.count # 每个正面或背面的顶点数。
	var faces: Array[Dictionary] = [] # 只收集朝向屏幕的表面。
	for side: int in [1, -1]: # 正面翻走以后只显示普通石背，不透出原画。
		var normal: Vector3 = turn.z * float(side) # 面法线朝向观察者才可见。
		if normal.z <= 0.008:
			continue
		var start: int = 0 if side == 1 else count # 正背顶点分组起点。
		var indices: PackedInt32Array = PackedInt32Array() # 当前表面的索引。
		for index: int in range(count): # 保持离线轮廓顺序。
			indices.append(start + index)
		var strength: float = maxf(0.0, normal.dot(light)) # Lambert 明暗强度。
		var brightness: float = (0.87 + 0.17 * strength) / (0.87 + 0.17 * light.z) if side == 1 else 0.62 + 0.48 * strength # 保持原画正面亮度。
		faces.append(_face(points, indices, center, Color(brightness, brightness, brightness), part.front_uv if side == 1 else part.back_uv))
	for index: int in range(count): # 相邻前后边连接成真正有厚度的侧壁。
		var next: int = (index + 1) % count # 当前侧壁的第二条边。
		var normal: Vector3 = (points[index + count] - points[index]).cross(points[next] - points[index]).normalized() # 楔面法线。
		if normal.z <= 0.002:
			continue
		var tint: Color = part.stone * (0.70 + 0.30 * maxf(0.0, normal.dot(light))) # 侧壁柔和石色。
		tint.a = 1.0
		faces.append(_face(points, PackedInt32Array([index, next, next + count, index + count]), center, tint))
	faces.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.depth) < float(second.depth))
	for face: Dictionary in faces: # 按远到近绘制，消除透明贴纸式前后穿透。
		if face.uv.is_empty():
			canvas.draw_colored_polygon(face.polygon, face.tint)
		else:
			canvas.draw_polygon(face.polygon, PackedColorArray([face.tint]), face.uv, atlas)

## 汇总一个表面的二维投影；[param uv] 为空时使用无纹理石质侧壁。
## [param points] 是旋转后的顶点，[param indices] 选择表面，[param center] 给出物理中心。
## [param tint] 为朝向光照后的不透明颜色。
static func _face(points: PackedVector3Array, indices: PackedInt32Array, center: Vector2, tint: Color, uv: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	var polygon: PackedVector2Array = PackedVector2Array() # 屏幕投影轮廓。
	var depth: float = 0.0 # 平均深度，只用于同一块石头内部排序。
	for index: int in indices: # 从三维旋转结果取出可见表面。
		var point: Vector3 = points[index] # 当前三维顶点。
		polygon.append(center + Vector2(point.x, point.y))
		depth += point.z
	return {"polygon": polygon, "depth": depth / float(indices.size()), "tint": tint, "uv": uv}
