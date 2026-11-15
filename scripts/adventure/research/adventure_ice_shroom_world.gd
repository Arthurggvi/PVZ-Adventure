## 一次世界施法持有独立暂停来源，时限与母株存亡无关。
extends Node
class_name AdventureIceShroomWorld

## 本次施放所属战场、棋盘、轮次和阶段。
var _battle: RepeaterShotContext
## 唯一有权挂起自然波次的关卡管理器。
var _waves: ZombieWaveManager
## 由寒冰菇实例标识的本次暂停来源。
var _source: StringName
## 剩余暂停时间，单位为有效游戏秒。
var _remaining: float

## 在 [param battle] 的 [param waves] 上以 [param source_id] 暂停自然波次 [param seconds] 秒。
static func start(battle: RepeaterShotContext, waves: ZombieWaveManager, source_id: int, seconds: float) -> void:
	var world := AdventureIceShroomWorld.new() # 关卡持有本次期限，原株可立即离场。
	world._battle = battle
	world._waves = waves
	world._source = StringName("ice_shroom_world_%d" % source_id)
	world._remaining = seconds
	waves.add_child(world)

## 在当前战局登记来源并监听结算边界。
func _ready() -> void:
	_waves.suspend_advancement(_source)
	TreePauseManager.pause_factors_changed.connect(_check_boundary)
	EventBus.subscribe("main_game_progress_update", _on_progress)

## [param delta] 为正常战斗经过的秒数，菜单暂停不流逝。
func _physics_process(delta: float) -> void:
	_remaining -= delta
	_check_boundary()

## [param _progress] 为新的关卡进度，变化时立即核对当前战局。
func _on_progress(_progress: int) -> void:
	_check_boundary()

## 到期或该战局已经结束时立即交还自己的暂停来源。
func _check_boundary() -> void:
	if _remaining <= 0.0 or not _battle.is_active():
		_release()
		queue_free()

## 整个关卡离场时也须释放，防止旧施法保留暂停。
func _exit_tree() -> void:
	EventBus.unsubscribe("main_game_progress_update", _on_progress)
	_release()

## 撤销本次暂停；允许结算和退出分别调用。
func _release() -> void:
	if not _source.is_empty() and is_instance_valid(_waves):
		_waves.resume_advancement(_source)
		_source = &""
