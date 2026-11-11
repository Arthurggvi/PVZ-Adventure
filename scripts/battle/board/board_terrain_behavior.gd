## 特殊地形扩展基类；每格独立实例，地形增益必须在 removed 中撤销。
extends Node2D
class_name BoardTerrainBehavior

## 当前地块；由地形层在入树前绑定。
var cell: PlantCell

## 在正式战斗中推进 [param delta]；选卡、暂停和阶段间隙不推进地形效果。
func _physics_process(delta: float) -> void:
	if is_instance_valid(Global.main_game) \
		and Global.main_game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		tick(delta)

## 地形行为可覆盖此方法；[param delta] 是有效战斗秒数。
func tick(_delta: float) -> void:
	pass

## 地形切换或关卡卸载时撤销本行为拥有的状态，不清除其他来源效果。
func removed() -> void:
	pass

## 返回本行为自有状态；不得保存植物实例引用。
func capture_state() -> Dictionary:
	return {}

## 无状态默认行为只接受空字典；自定义行为必须校验所有 [param state] 字段。
func accepts_state(state: Dictionary) -> bool:
	return state.is_empty()

## 应用已校验的 [param state]；不得再次消耗阳光或生成重复占用。
func restore_state(_state: Dictionary) -> void:
	pass

## 统一离树清理，无论来自地形切换还是退出关卡。
func _exit_tree() -> void:
	removed()
