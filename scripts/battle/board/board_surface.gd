## 种植平台实例；运动只改变节点变换，不改地块身份、占用或攻击行。
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

## 配置 [param data] 和 [param owner_game]；必须在入树前调用。
func configure(data: BoardSurfaceDefinition, owner_game: MainGameManager) -> void:
	definition = data
	game = owner_game
	position = data.origin
	set_physics_process(not data.travel_offset.is_zero_approx())

## 视觉场景为平台子节点，不接管种植节点。
func _ready() -> void:
	set_physics_process(not definition.travel_offset.is_zero_approx())
	if definition.visual_scene != null:
		var visual: Node = definition.visual_scene.instantiate() # 每个平台独立的视觉实例。
		add_child(visual)
		move_child(visual, 0)

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

## 按余弦往返，端点速度为零；不改变植物局部坐标。
func _apply_auto() -> void:
	var amount: float = (1.0 - cos(PI * _elapsed / definition.travel_seconds)) * 0.5 # 当前轨道进度。
	position = definition.origin + definition.travel_offset * amount

## 从保存的进度计算当前位姿；不积累逐帧差值。
func _apply_manual() -> void:
	var amount: float = 1.0 if _duration <= 0.0 else clampf(_move_elapsed / _duration, 0.0, 1.0) # 当前进度。
	position = _from.lerp(_target, amount * amount * (3.0 - 2.0 * amount))

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
