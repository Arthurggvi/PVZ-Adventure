## 单次离手从同一枪口生成中路电球及两道固定角度的锥形射线。
extends RefCounted
class_name ElectricPeaVolley

## 锥形侧弹相对中路的最大夹角，单位为度；避免持续扩散过快离开棋盘。
const MAX_SPREAD_HALF_ANGLE: float = 14.0


## [param shot] 为此次出手快照；从 [param mouth] 离手，[param origin] 仅冻结枪口到地格中心的高度。
static func emit(shot: ElectricPeaShotContext, origin: PlantCell, mouth: Vector2) -> void:
	_emit_ball(shot, mouth, Vector2.RIGHT, origin)
	if shot.promotions.spread_cells <= 0.0:
		return
	var reach: float = shot.promotions.spread_cells * shot.cell_pitch.x # 到相邻行的参考横距，只定义初始角度。
	var half_angle: float = minf(atan2(shot.cell_pitch.y, reach), deg_to_rad(MAX_SPREAD_HALF_ANGLE)) # 兼容原格距参数，同时保留横跨战场的射程。
	for offset: int in [-1, 1]: # 边行仍朝板外发散，离屏后按弹体统一规则回收。
		var direction := Vector2.from_angle(float(offset) * half_angle) # 两侧相同夹角和实际速率。
		_emit_ball(shot, mouth, direction, origin)


## 从 [param mouth] 生成 [param shot] 对应电球；[param direction] 固定射线方向，[param origin] 提供地面高度。
static func _emit_ball(shot: ElectricPeaShotContext, mouth: Vector2, direction: Vector2, origin: PlantCell) -> void:
	var projectile := ElectricPeaProjectile.new() # 扩散电球各自进行移动、放电及回收。
	projectile.shot = shot
	projectile.flight_direction = direction
	projectile.launch_origin = origin
	projectile.position = shot.game.bullets.to_local(mouth)
	shot.game.bullets.add_child(projectile)
