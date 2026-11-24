## 从雪山棋盘的两段坡面生成屋顶协议所用的高度区间与各行碰撞线。
extends MainGameSlope

## 与格子共用原图测量数据，坡脚和坡顶恰好落在对应列界上。
const SnowBoard := preload("res://scripts/adventure/snow_mountain_board.gd")

## 装配后把行走交给精确高度采样，弹道及受击仍使用 MainGameSlope。
func _ready() -> void:
	sample_walking_height = true
	for point_index: int in range(0, SnowBoard.RAMP_POINTS.size(), 2): # 每两个端点是一段实际斜坡。
		_add_ramp(SnowBoard.RAMP_POINTS[point_index], SnowBoard.RAMP_POINTS[point_index + 1])
	super()

## 将原图斜面 [param start]、[param finish] 投影为屋顶兼容节点，给六行复用同一坡形。
func _add_ramp(start: Vector2, finish: Vector2) -> void:
	var ramp := Slope.new() # 现有坡面查询和投掷规划消费的区间。
	ramp.position.x = SnowBoard.art_to_world(start).x
	ramp.solid_for_projectiles = true
	var detector := Area2D.new() # 保留旧坡面接口，行走使用精确差量，无需监听区域切换。
	detector.name = "Area2DSlopeDetection"
	detector.collision_layer = 0
	detector.collision_mask = 0
	detector.monitoring = false
	detector.monitorable = false
	ramp.add_child(detector)
	var surfaces := Node2D.new() # 每行独立设置纵向基线。
	surfaces.name = "SlopeReal"
	ramp.add_child(surfaces)
	var segment := SegmentShape2D.new() # 端点的 Y 是水平检测面下方的偏移。
	segment.a = Vector2(0.0, start.y * SnowBoard.ART_SCALE.y)
	segment.b = Vector2((finish.x - start.x) * SnowBoard.ART_SCALE.x, finish.y * SnowBoard.ART_SCALE.y)
	for row: int in range(SnowBoard.ROW_EDGES.size() - 1): # 从远到近建立坡面物理线。
		var surface := Area2D.new() # 对应本行脚点的实际斜面。
		surface.name = "Area2DReal" if row == 0 else "Area2DReal%d" % (row + 1)
		surface.position.y = SnowBoard.lane_foot_y(row) * SnowBoard.ART_SCALE.y
		surface.collision_layer = 1 # 平射弹碰撞遮罩中的世界层。
		surface.monitoring = false
		surface.collision_mask = 0
		var shape := CollisionShape2D.new() # 同斜率的共享线段由行节点定位。
		shape.name = "CollisionShape2D"
		shape.shape = segment
		surface.add_child(shape)
		surfaces.add_child(surface)
		surface.owner = ramp # 沿用屋顶协议，子弹由区域的所有者取得坡面。
	add_child(ramp)
