## 单次原版离手生成中路电球及可选的两道扩散支路。
extends RefCounted
class_name ElectricPeaVolley


## [param shot] 为此次出手快照；从 [param mouth] 离手，并以 [param origin] 的真实棋盘位置定位邻行。
static func emit(shot: ElectricPeaShotContext, origin: PlantCell, mouth: Vector2) -> void:
	_emit_ball(shot, mouth, 0, null, null)
	if shot.promotions.spread_cells <= 0.0:
		return
	for offset: int in [-1, 1]: # 越过边界的方向仍有散射球，但不登记虚构攻击行。
		var destination: PlantCell = null # 横向最近的同平台邻格，越界时为空。
		var closest: float = INF # 横向最近的邻格最能代表此处的行距。
		for cell: PlantCell in shot.board.row_cells(shot.lane + offset): # 当前几何随移动平台变化。
			if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree() \
					or cell.board_definition.surface_id != origin.board_definition.surface_id:
				continue
			var distance: float = absf(cell.get_global_rect().get_center().x - origin.get_global_rect().get_center().x) # 选同列或最近的错列地块。
			if distance < closest:
				closest = distance
				destination = cell
		_emit_ball(shot, mouth, offset, origin, destination)


## 从 [param mouth] 生成 [param shot] 对应电球；[param offset] 为射线方向，侧弹保留 [param origin] 与 [param destination]。
static func _emit_ball(shot: ElectricPeaShotContext, mouth: Vector2, offset: int, origin: PlantCell,
		destination: PlantCell) -> void:
	var projectile := ElectricPeaProjectile.new() # 扩散电球各自进行移动、放电及回收。
	projectile.shot = shot
	projectile.spread_direction = offset
	projectile.spread_origin = origin
	projectile.spread_destination = destination
	projectile.position = shot.game.bullets.to_local(mouth)
	shot.game.bullets.add_child(projectile)
