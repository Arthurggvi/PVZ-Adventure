## 从原始背景生成保守局部遮罩；不修改、重画或覆盖任何原始美术。
extends SceneTree

## 所有蒙版以相同1920×1080背景设计空间保存。
const SIZE := Vector2i(1920, 1080)
## 仅保存新增的版本化效果遮罩。
const OUTPUT := "res://assets/adventure/environment_fx/v1/generated_masks/"

## 构建原背景水色范围及少量地形多边形，不能使用游戏截图。
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_make_sea("res://assets/adventure/main_menu/v6/background/coastal_yard.png", "main_sea.png", false)
	_make_sea("res://assets/adventure/zombie_island/map/zombie_island_background_1920x1080.png", "island_sea.png", true)
	var fog := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8) # 墓地区域的透明蒙版。
	fog.fill(Color.TRANSPARENT)
	var polygons := [ # 参考背景坐标换算，限制在墓地地面与低洼区域。
		PackedVector2Array([Vector2(315,180),Vector2(365,145),Vector2(485,165),Vector2(550,190),Vector2(590,230),Vector2(470,270),Vector2(340,240)]),
		PackedVector2Array([Vector2(555,260),Vector2(640,235),Vector2(805,290),Vector2(870,355),Vector2(760,392),Vector2(600,355)])]
	for polygon: PackedVector2Array in polygons: # 仅绘制蒙版，不重绘地形。
		for index: int in range(polygon.size()): # 原参考点转入背景设计空间。
			polygon[index] *= Vector2(1920.0 / 1066.0, 1080.0 / 600.0)
		_paint_polygon(fog, polygon)
	fog.save_png(OUTPUT + "graveyard.png")
	var temple := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8) # 限定脑罩附近，不照亮整座神殿。
	temple.fill(Color.TRANSPARENT)
	for y: int in range(148): # 脑罩局部纵向像素范围。
		for x: int in range(1450, 1748): # 脑罩局部横向像素范围。
			var distance := (Vector2(x, y) - Vector2(1598, 68)) / Vector2(120, 64) # 背景脑穹顶椭圆。
			if distance.length_squared() < 1.0:
				temple.set_pixel(x, y, Color.WHITE)
	temple.save_png(OUTPUT + "temple.png")
	print("PASS: four environment masks generated from original backgrounds and local terrain geometry")
	quit()

## [param source] 为原始背景；[param filename] 为新增蒙版；[param island] 区分保守海岸区域。
func _make_sea(source: String, filename: String, island: bool) -> void:
	var original := Image.load_from_file(source) # 读取真正原图，不读取截图或候选天空图。
	var region := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8) # 海水蒙版。
	region.fill(Color.TRANSPARENT)
	for y: int in range(SIZE.y): # 原背景逐行读取。
		for x: int in range(SIZE.x): # 原背景当前行像素。
			var uv := Vector2(x / 1920.0, y / 1080.0) # 背景归一化坐标。
			var allowed := (uv.y > 0.75 and (uv.x < 0.17 or uv.x > 0.83)) or (uv.y > 0.89 and uv.x > 0.28 and uv.x < 0.60) # 保守的岛外海岸范围。
			if not island:
				allowed = x > 1140 and y > 580
			if not allowed:
				continue
			var color := original.get_pixel(x, y) # 排除木板、土地、灰色礁石及绿色毒液。
			if color.b > color.r * 1.22 and color.g > color.r * 1.2 and color.b - color.r > 0.08:
				region.set_pixel(x, y, Color.WHITE)
	region.save_png(OUTPUT + filename)

## 在 [param image] 上填入 [param polygon] 的内部，边界仍在背景设计坐标中。
func _paint_polygon(image: Image, polygon: PackedVector2Array) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO) # 减少逐像素检查范围。
	for point: Vector2 in polygon: # 计算局部多边形边界。
		bounds = bounds.expand(point)
	for y: int in range(int(bounds.position.y), int(bounds.end.y) + 1): # 地形区域纵向范围。
		for x: int in range(int(bounds.position.x), int(bounds.end.x) + 1): # 地形区域横向范围。
			if Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
				image.set_pixel(x, y, Color.WHITE)
