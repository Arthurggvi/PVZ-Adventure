## 峰值主刀光的实际轮廓，同一击对多个受击形状只需构造一次。
extends RefCounted

## 从零起算的图集峰值帧，前景播放与碰撞轮廓共用。
const ATLAS_FRAME: int = 9
## 将峰值帧的连通刀身与瞬时亮核合成，取遮盖率 28% 的外缘。
## 坐标以未倾斜的刀宽和画布高度归一化，保留火翼与凹口，舍去独立飞散的火星。
const OUTLINE: Array[Vector2] = [
	Vector2(0.028, -0.470), Vector2(0.044, -0.438), Vector2(0.058, -0.440),
	Vector2(0.078, -0.370), Vector2(0.102, -0.386), Vector2(0.134, -0.392),
	Vector2(0.136, -0.378), Vector2(0.114, -0.364), Vector2(0.094, -0.326),
	Vector2(0.090, -0.284), Vector2(0.072, -0.236), Vector2(0.074, -0.218),
	Vector2(0.090, -0.208), Vector2(0.074, -0.162), Vector2(0.078, -0.126),
	Vector2(0.104, -0.136), Vector2(0.150, -0.178), Vector2(0.158, -0.198),
	Vector2(0.152, -0.222), Vector2(0.166, -0.242), Vector2(0.196, -0.260),
	Vector2(0.206, -0.282), Vector2(0.210, -0.246), Vector2(0.198, -0.228),
	Vector2(0.200, -0.214), Vector2(0.164, -0.182), Vector2(0.160, -0.160),
	Vector2(0.170, -0.140), Vector2(0.166, -0.102), Vector2(0.172, -0.094),
	Vector2(0.192, -0.098), Vector2(0.262, -0.158), Vector2(0.266, -0.174),
	Vector2(0.276, -0.182), Vector2(0.278, -0.162), Vector2(0.288, -0.156),
	Vector2(0.336, -0.158), Vector2(0.250, -0.134), Vector2(0.166, -0.054),
	Vector2(0.142, 0.002), Vector2(0.154, 0.006), Vector2(0.156, 0.028),
	Vector2(0.176, 0.068), Vector2(0.198, 0.070), Vector2(0.328, 0.024),
	Vector2(0.350, 0.006), Vector2(0.382, -0.056), Vector2(0.402, -0.068),
	Vector2(0.384, -0.048), Vector2(0.360, 0.014), Vector2(0.376, 0.050),
	Vector2(0.352, 0.034), Vector2(0.298, 0.046), Vector2(0.246, 0.076),
	Vector2(0.242, 0.094), Vector2(0.212, 0.132), Vector2(0.204, 0.136),
	Vector2(0.196, 0.108), Vector2(0.186, 0.108), Vector2(0.116, 0.172),
	Vector2(0.104, 0.190), Vector2(0.098, 0.224), Vector2(0.132, 0.226),
	Vector2(0.088, 0.240), Vector2(0.054, 0.278), Vector2(0.050, 0.428),
	Vector2(0.030, 0.450), Vector2(-0.008, 0.454), Vector2(-0.016, 0.464),
	Vector2(-0.050, 0.428), Vector2(-0.056, 0.378), Vector2(-0.090, 0.382),
	Vector2(-0.116, 0.402), Vector2(-0.128, 0.402), Vector2(-0.102, 0.376),
	Vector2(-0.090, 0.342), Vector2(-0.094, 0.330), Vector2(-0.116, 0.334),
	Vector2(-0.108, 0.304), Vector2(-0.126, 0.256), Vector2(-0.120, 0.246),
	Vector2(-0.096, 0.236), Vector2(-0.088, 0.216), Vector2(-0.092, 0.198),
	Vector2(-0.132, 0.154), Vector2(-0.136, 0.108), Vector2(-0.146, 0.094),
	Vector2(-0.136, 0.076), Vector2(-0.160, 0.044), Vector2(-0.184, 0.036),
	Vector2(-0.198, 0.046), Vector2(-0.208, 0.080), Vector2(-0.230, 0.068),
	Vector2(-0.252, 0.030), Vector2(-0.250, -0.014), Vector2(-0.222, -0.042),
	Vector2(-0.210, -0.084), Vector2(-0.220, -0.120), Vector2(-0.218, -0.150),
	Vector2(-0.234, -0.204), Vector2(-0.236, -0.262), Vector2(-0.272, -0.320),
	Vector2(-0.240, -0.334), Vector2(-0.234, -0.358), Vector2(-0.220, -0.370),
	Vector2(-0.192, -0.378), Vector2(-0.148, -0.352), Vector2(-0.148, -0.338),
	Vector2(-0.166, -0.328), Vector2(-0.172, -0.314), Vector2(-0.170, -0.292),
	Vector2(-0.154, -0.266), Vector2(-0.122, -0.244), Vector2(-0.102, -0.246),
	Vector2(-0.082, -0.238), Vector2(-0.060, -0.242), Vector2(-0.054, -0.258),
	Vector2(-0.054, -0.324), Vector2(-0.066, -0.328), Vector2(-0.060, -0.368),
	Vector2(-0.088, -0.386), Vector2(-0.118, -0.370), Vector2(-0.142, -0.378),
	Vector2(-0.162, -0.422), Vector2(-0.154, -0.464),
]

## 在世界坐标系下计算的刀身凸片，以一次落点为局部原点。
var _pieces: Array[ConvexPolygonShape2D] = []
## 与凸片同序的世界包围盒，避开远处凸片的精确查询。
var _piece_bounds: Array[Rect2] = []
## 完整轮廓的世界包围盒，用于第一层粗筛。
var _bounds := Rect2()
## 碰撞变换只承担平移；非等比缩放和剪切已写进各凸片的顶点。
var _pose: Transform2D

## [param blade_to_world] 是前景刀光使用的刀宽、斜率、画布高度及世界中心。
func _init(blade_to_world: Transform2D) -> void:
	_pose = Transform2D(0.0, blade_to_world.origin)
	var basis: Transform2D = blade_to_world # 局部顶点保留非等比投影，原点平移留给形状查询。
	basis.origin = Vector2.ZERO
	var projected: PackedVector2Array = basis * PackedVector2Array(OUTLINE) # 投影一遍，所有凸片复用这个轮廓。
	for polygon: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(projected): # 真实凹口不填成矩形。
		var piece := ConvexPolygonShape2D.new() # 同一落点的所有敌人共享此凸片。
		piece.points = polygon
		var world_rect: Rect2 = _pose * piece.get_rect() # 包围盒与精确碰撞处于同一坐标系。
		_pieces.append(piece)
		_piece_bounds.append(world_rect)
		_bounds = _bounds.merge(world_rect) if _bounds.has_area() else world_rect
	if _pieces.is_empty():
		push_error("冥镰裂地的峰值轮廓无法构造受击形状")

## [param area] 的任一启用受击形状碰到刀身即命中，支持大体型及多形状目标。
func overlaps(area: Area2D) -> bool:
	if not is_instance_valid(area) or area.is_queued_for_deletion():
		return false
	for owner_id: int in area.get_shape_owners(): # 保留物种自己的受击窗口和形状偏移。
		if area.is_shape_owner_disabled(owner_id):
			continue
		var pose: Transform2D = area.global_transform * area.shape_owner_get_transform(owner_id) # 碰撞形状的真实世界位姿。
		for shape_index: int in range(area.shape_owner_get_shape_count(owner_id)): # 普通僵尸与多形状僵王沿用同一路径。
			var shape: Shape2D = area.shape_owner_get_shape(owner_id, shape_index) # 当前启用的敌方受击形状。
			if shape == null:
				continue
			var target_bounds: Rect2 = pose * shape.get_rect() # 粗筛计入目标旋转、缩放及动画位移。
			if not _bounds.intersects(target_bounds, true):
				continue
			for piece_index: int in range(_pieces.size()): # 只对包围盒接触的凸片做精确查询。
				if _piece_bounds[piece_index].intersects(target_bounds, true) \
						and shape.collide(pose, _pieces[piece_index], _pose):
					return true
	return false
