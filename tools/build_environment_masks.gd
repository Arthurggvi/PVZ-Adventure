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
	_make_menu_sky()
	_make_dock()
	_make_waterfalls()
	print("PASS: masks generated; lighthouse silhouette, dock sea removal and source-map waterfalls registered")
	quit()

## 修正安装遮罩的灯塔矩形占位；保留原始遮罩，只输出新的运行时遮罩。
func _make_menu_sky() -> void:
	var mask := Image.load_from_file("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/masks/main_menu_moving_cloud_safe_mask.png") # 原有树冠和地平线轮廓。
	var source := Image.load_from_file("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png") # 与背景相同的设计坐标。
	# 真实背景的塔顶、檐口及塔身外缘，避免矩形预留区截断云层。
	var lighthouse := PackedVector2Array([
		Vector2(1091,175), Vector2(1097,183), Vector2(1109,190), Vector2(1106,195),
		Vector2(1108,204), Vector2(1113,204), Vector2(1113,217), Vector2(1104,221),
		Vector2(1105,235), Vector2(1109,260), Vector2(1116,275), Vector2(1067,275),
		Vector2(1073,250), Vector2(1077,220), Vector2(1070,216), Vector2(1070,205),
		Vector2(1074,205), Vector2(1074,195), Vector2(1069,194), Vector2(1076,187),
		Vector2(1085,182)])
	mask.convert(Image.FORMAT_RGBA8)
	for y: int in range(135, 275): # 只替换矩形占位范围。
		for x: int in range(1010, 1145): # 不改变既有树冠遮罩。
			var color := source.get_pixel(x, y) # 底部灌木须继续挡云。
			var sky := 1.0 if y < 236 else smoothstep(0.03, 0.10, color.b - maxf(color.r, color.g)) # 天空与远岸植被的色差。
			if Geometry2D.is_point_in_polygon(Vector2(x, y), lighthouse):
				sky = 0.0
			mask.set_pixel(x, y, Color(sky, sky, sky, 1))
	mask.save_png(OUTPUT + "main_sky.png")

## 去掉码头前景误带的矩形海水，原PNG和木板/立柱保持原位。
func _make_dock() -> void:
	var source := Image.load_from_file("res://assets/adventure/main_menu/v6/overlays/dock_foreground.png") # 原遮挡层含不透明海水。
	var mask := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8) # 与码头共用整图坐标的Alpha遮罩。
	mask.fill(Color.TRANSPARENT)
	for y: int in range(440, 860): # 码头局部纵向范围。
		for x: int in range(1140, SIZE.x): # 不处理其他菜单主体。
			var color := source.get_pixel(x, y) # 区分蓝绿水体与暖色木材。
			var water := smoothstep(0.055, 0.14, minf(color.g, color.b) - color.r) # 连续过渡，避免色阈值硬边。
			mask.set_pixel(x, y, Color(1, 1, 1, color.a * (1.0 - water)))
	mask.save_png(OUTPUT + "dock_foreground.png")

## 瀑布轮廓直接定义在真实1920×1080地图上，弃用截图的纵向偏移。
func _make_waterfalls() -> void:
	var regions := { # 两段独立沿真实水体裁剪，水花使用独立锚点。
		"upper_flow.png": PackedVector2Array([
			Vector2(908,434), Vector2(920,432), Vector2(936,434), Vector2(955,437),
			Vector2(976,436), Vector2(964,456), Vector2(962,480), Vector2(951,512),
			Vector2(917,519), Vector2(894,516), Vector2(899,480), Vector2(903,452)]),
		"lower_flow.png": PackedVector2Array([
			Vector2(904,730), Vector2(921,733), Vector2(941,731), Vector2(963,728),
			Vector2(988,725), Vector2(999,739), Vector2(1003,773), Vector2(1011,812),
			Vector2(994,829), Vector2(959,830), Vector2(931,820), Vector2(920,780),
			Vector2(912,751)])}
	for filename: String in regions: # 只生成叠加区域，不挪动岩石。
		var mask := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8) # 与背景共用局部坐标。
		mask.fill(Color.TRANSPARENT)
		_paint_polygon(mask, regions[filename])
		mask.save_png(OUTPUT + filename)

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
