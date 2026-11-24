## 石像的短入场地纹、灰尘和接地阴影；全部由少量二维图元完成。
extends RefCounted

## 源图坐标中的脚点；与既有僵尸根节点的地面位置对应。
const FOOT: Vector2 = Vector2(110.0, 252.0)
## 灰尘本色略偏暖，避免纯白强光遮住草坪。
const DUST: Color = Color(0.59, 0.57, 0.48)

## 向 [param canvas] 绘制入场地纹；[param age] 从突然出现时开始计秒。
static func arrival_ground(canvas: CanvasItem, age: float) -> void:
	if age < 0.0 or age > 0.65:
		return
	var strength: float = (1.0 - age / 0.65) * 0.35 # 短暂深色接地，不使用发光传送门。
	ellipse(canvas, FOOT, Vector2(39.0 + age * 20.0, 10.0), Color(0.20, 0.23, 0.16, strength))
	for index: int in range(7): # 不规则的短裂地线，避免规则圆环的贴图感。
		var angle: float = float(index) * 0.91 + 0.3 # 固定排列保证回放稳定。
		var direction: Vector2 = Vector2(cos(angle), sin(angle) * 0.29) # 压扁到草坪平面。
		canvas.draw_line(FOOT + direction * 24.0, FOOT + direction * (40.0 + float(index % 3) * 6.0), Color(0.19, 0.22, 0.15, strength), 1.5, true)

## 向 [param canvas] 绘制少量贴地扬尘；[param age] 是当前入场时间。
static func arrival_dust(canvas: CanvasItem, age: float) -> void:
	if age < 0.0 or age > 0.65:
		return
	for index: int in range(9): # 每个粉尘团只用两个软层，控制绘制开销。
		var phase: float = float(index) * 2.399 # 固定散布方向。
		var center: Vector2 = FOOT + Vector2(cos(phase) * (16.0 + age * 65.0), -age * (13.0 + float(index % 3) * 9.0) + sin(phase) * 4.0) # 贴地向两侧散开。
		var opacity: float = sin(PI * clampf(age / 0.65, 0.0, 1.0)) * 0.30 # 不在首帧留下满屏白雾。
		_puff(canvas, center, Vector2(7.0 + age * 10.0, 4.0 + age * 7.0), opacity)

## 石块在草坪上的独立阴影；[param state] 包含接地高度，非僵尸身体位置。
## [param canvas] 接收源图坐标绘制，[param pose] 给出该块本帧的位置。
static func fragment_shadow(canvas: CanvasItem, state: Dictionary, pose: Dictionary) -> void:
	var center: Vector2 = pose.center # 当前石块投影中心。
	var lift: float = maxf(0.0, float(state.floor) - center.y) # 石块离地越远，阴影越淡。
	var radius: float = clampf(state.part.size.x * 0.26, 3.0, 15.0) # 按实际碎块尺寸取阴影宽度。
	var opacity: float = 0.21 * clampf(1.0 - lift / 200.0, 0.15, 1.0) # 接触处最深。
	ellipse(canvas, Vector2(center.x, float(state.floor) + 1.0), Vector2(radius, 2.4), Color(0.12, 0.16, 0.10, opacity))

## 接地后才扬尘；[param pose] 的 settle_age 来自同一套接地判定。
## [param canvas] 接收绘制，[param state] 给出该碎块对应的地面高度。
static func impact_dust(canvas: CanvasItem, state: Dictionary, pose: Dictionary) -> void:
	if not pose.landed:
		return
	var age: float = pose.settle_age # 该石块撞地后的秒数。
	if age > 0.42:
		return
	var opacity: float = sin(PI * clampf(age / 0.42, 0.0, 1.0)) * 0.26 # 撞地很快达到峰值后散去。
	var center: Vector2 = Vector2(pose.center.x, float(state.floor) - age * 13.0) # 小范围抬升的粉尘。
	_puff(canvas, center, Vector2(5.0 + age * 23.0, 3.0 + age * 10.0), opacity)

## 用两层椭圆给 [param center] 的石粉柔化边缘，避免硬圆点。
## [param canvas] 接收绘制，[param size] 为椭圆半径，[param opacity] 为中心透明度。
static func _puff(canvas: CanvasItem, center: Vector2, size: Vector2, opacity: float) -> void:
	ellipse(canvas, center, size * 1.22, Color(DUST, opacity * 0.34))
	ellipse(canvas, center, size, Color(DUST, opacity * 0.65))

## 画低顶点椭圆；[param radius] 为横纵半径，单位为源图像素。
## [param canvas] 接收绘制，[param center] 为中心，[param color] 包括此次绘制的透明度。
static func ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array() # 十二边形在游戏显示尺寸下足够平滑。
	for index: int in range(12): # 少量固定顶点，不创建节点或粒子资源。
		var angle: float = TAU * float(index) / 12.0 # 当前椭圆顶点角度。
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_colored_polygon(points, color)
