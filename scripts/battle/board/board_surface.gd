## 刚性种植平台实例；地块身份和占用稳定，显式启用的棋盘另按脚点投影攻防行。
extends Node2D
class_name BoardSurface

## 所属战斗，用于统一有效战斗时间。
var game: MainGameManager
## 平台独占的静态声明。
var definition: BoardSurfaceDefinition
## 自动往返的有效累计秒数。
var _elapsed: float = 0.0
## 显式移动覆盖自动往返；不会在结束后突然跳回默认轨道。
var _manual: bool = false
## 显式移动起点。
var _from := Vector2.ZERO
## 显式移动终点。
var _target := Vector2.ZERO
## 显式移动总秒数。
var _duration: float = 0.0
## 显式移动已用秒数。
var _move_elapsed: float = 0.0

## 在入树前装配 [param data] 和 [param owner_game]；阶段交接时可重新配置现有平台。
func configure(data: BoardSurfaceDefinition, owner_game: MainGameManager) -> void:
	definition = data
	game = owner_game
	position = data.origin
	set_physics_process(not data.travel_offset.is_zero_approx())
	if is_node_ready():
		_sync_combat_lanes(true)

## 水体接触区和视觉场景跟随平台，不接管种植节点。
func _ready() -> void:
	set_physics_process(not definition.travel_offset.is_zero_approx())
	for region: Rect2 in definition.water_regions: # 已通过战场预检的水域矩形。
		add_child(WaterBodyArea.from_region(region))
	if definition.visual_scene != null:
		var visual: Node = definition.visual_scene.instantiate() # 每个平台独立的视觉实例。
		add_child(visual)
		move_child(visual, 0)
	_sync_combat_lanes()

## 只有正式战斗推进；[param delta] 已受引擎时间倍率影响，不再次乘速率。
func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	if _manual:
		_move_elapsed = minf(_move_elapsed + delta, _duration)
		_apply_manual()
		if _move_elapsed >= _duration:
			set_physics_process(false)
	else:
		_elapsed = fmod(_elapsed + delta, definition.travel_seconds * 2.0)
		_apply_auto()

## 显式移动至 [param target]；[param seconds] 为有效战斗秒数，0 表示立即定位。
func move_to(target: Vector2, seconds: float) -> void:
	_manual = true
	_from = position
	_target = target
	_duration = seconds
	_move_elapsed = 0.0
	_apply_manual()
	set_physics_process(seconds > 0.0)

## 当前轨迹还能向世界下方移动的最大像素数，用于预留跟踪甲板的入场路线。
func downward_travel_room() -> float:
	if not is_physics_processing():
		return 0.0
	var parent_item := get_parent() as CanvasItem # 位移端点使用平台的父级坐标。
	var to_world: Transform2D = parent_item.get_global_transform() if parent_item != null else Transform2D.IDENTITY # 只取线性部分。
	var endpoint: Vector2 = _target if _manual else definition.origin # 手动轨迹单向完成，自动往返有两个端点。
	var room: float = to_world.basis_xform(endpoint - position).y # 从当前位置到第一个端点的世界纵移。
	if not _manual:
		room = maxf(room, to_world.basis_xform(endpoint + definition.travel_offset - position).y)
	return maxf(room, 0.0)

## 按余弦往返，端点速度为零；不改变植物局部坐标。
func _apply_auto() -> void:
	var amount: float = (1.0 - cos(PI * _elapsed / definition.travel_seconds)) * 0.5 # 当前轨道进度。
	position = definition.origin + definition.travel_offset * amount
	_sync_combat_lanes()

## 从保存的进度计算当前位姿；不积累逐帧差值。
func _apply_manual() -> void:
	var amount: float = 1.0 if _duration <= 0.0 else clampf(_move_elapsed / _duration, 0.0, 1.0) # 当前进度。
	position = _from.lerp(_target, amount * amount * (3.0 - 2.0 * amount))
	_sync_combat_lanes()

## 运动和读档使用相同的脚点投影。[param reconfigured] 允许阶段交接时恢复默认逻辑行。
func _sync_combat_lanes(reconfigured: bool = false) -> void:
	if not is_inside_tree() or not is_instance_valid(game) or game.board == null or game.board.definition == null:
		return
	var project_lanes: bool = game.board.definition.project_surface_combat_lanes # 普通战场没有逐帧计算。
	if not project_lanes and not reconfigured:
		return
	for child: Node in get_children(): # 美术和水域也可挂在平台下，只有种植点参与投影。
		if child is PlantCell:
			var cell: PlantCell = child # 脚点不含植物待机动画或承托层摇摆。
			var lane: int = game.board.lane_at_foot_y(game.to_local(cell.get_spawn_global_position()).y) \
				if project_lanes else cell.row_col.x # 默认布局沿用稳定逻辑行。
			cell.update_combat_lane(lane)

## 返回可序列化运动状态，恢复时无需重放全部历史帧。
func capture_state() -> Dictionary:
	return {"elapsed": _elapsed, "manual": _manual, "from": _from,
		"target": _target, "duration": _duration, "move_elapsed": _move_elapsed}

## 校验 [param state] 的全部位姿字段；不修改当前平台。
static func accepts_state(state: Dictionary) -> bool:
	for key: String in ["elapsed", "duration", "move_elapsed"]: # 必须存在的非负时间。
		if not state.get(key) is float and not state.get(key) is int:
			return false
		if not is_finite(float(state[key])) or float(state[key]) < 0.0:
			return false
	return state.get("manual") is bool and state.get("from") is Vector2 \
		and state.get("target") is Vector2 and (state["from"] as Vector2).is_finite() \
		and (state["target"] as Vector2).is_finite() \
		and float(state["move_elapsed"]) <= float(state["duration"])

## 应用已通过 [method accepts_state] 的 [param state]，不会发起新的移动。
func restore_state(state: Dictionary) -> void:
	_elapsed = fmod(float(state["elapsed"]), definition.travel_seconds * 2.0)
	_manual = bool(state["manual"])
	_from = state["from"]
	_target = state["target"]
	_duration = float(state["duration"])
	_move_elapsed = float(state["move_elapsed"])
	if _manual:
		_apply_manual()
	else:
		_apply_auto()
	set_physics_process((_manual and _move_elapsed < _duration) \
		or (not _manual and not definition.travel_offset.is_zero_approx()))
