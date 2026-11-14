## 每株只持有一份皇朝攻速；任意施放仍有效时保持同一倍数。
extends Node
class_name AdventureIceShroomDynasty

## 植株内复用的状态节点名称。
const STATUS_NAME: StringName = &"AdventureIceShroomDynasty"
## 接受治疗和攻速的存活植物。
var _plant: Plant000Base
## 作用的棋盘、轮次和阶段。
var _battle: RepeaterShotContext
## 各次施放的实例 ID 映射到独立剩余游戏秒数。
var _sources: Dictionary[int, float] = {}

## 为 [param battle] 的当前存活植物按 [param heal_fraction] 恢复最大生命，
## 并以 [param source_id] 授予 [param seconds] 秒的 [param rate] 倍攻速。
static func apply_to_board(battle: RepeaterShotContext, source_id: int, seconds: float,
		heal_fraction: float, rate: float) -> void:
	var seen: Dictionary[int, bool] = {} # 多格植株共享同一实例，只恢复一次。
	for cell: PlantCell in battle.board.cells(): # 使用当前棋盘及真实植物层。
		for plant: Plant000Base in cell.living_plants(): # 包括同格伴生植物及承托层。
			if not battle.is_active():
				return
			if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
				continue
			var identity: int = plant.get_instance_id() # 按实例区分同种植物。
			if plant.is_hypno or seen.has(identity):
				continue
			seen[identity] = true
			plant.hp_component.heal(roundi(float(plant.hp_component.max_hp) * heal_fraction))
			if battle.is_active() and is_instance_valid(plant) and not plant.is_death and not plant.is_queued_for_deletion():
				_grant(plant, battle, source_id, seconds, rate)

## 在 [param plant] 上登记 [param battle] 的 [param source_id]，以 [param rate] 倍攻速持续 [param seconds] 秒。
static func _grant(plant: Plant000Base, battle: RepeaterShotContext, source_id: int,
		seconds: float, rate: float) -> void:
	var status := plant.get_node_or_null(NodePath(STATUS_NAME)) as AdventureIceShroomDynasty # 复用单株状态。
	if status == null:
		status = AdventureIceShroomDynasty.new()
		status.name = STATUS_NAME
		status._plant = plant
		plant.add_child(status)
	elif not status._sources.is_empty() and not status._battle.is_same_battle():
		status._clear()
	status._battle = battle
	status._sources[source_id] = seconds
	status._set_speed(rate)
	status.set_physics_process(true)

## 入树时监听战局边界，支持同一植株随容器重新入树。
func _enter_tree() -> void:
	set_physics_process(false)
	TreePauseManager.pause_factors_changed.connect(_check_boundary)
	EventBus.subscribe("main_game_progress_update", _on_progress)

## 死亡时同步撤销加速，普通菜单暂停保留剩余时长。
func _ready() -> void:
	_plant.signal_character_death.connect(_clear)

## [param delta] 为有效游戏秒数；最后一个来源到期时才恢复攻速。
func _physics_process(delta: float) -> void:
	_check_boundary()
	for source_id: int in _sources.keys(): # 分别扣除每次施放的时限。
		var remaining: float = _sources[source_id] - delta # 当前来源剩余的游戏秒数。
		if remaining <= 0.0:
			_sources.erase(source_id)
		else:
			_sources[source_id] = remaining
	if _sources.is_empty():
		_clear()

## [param _progress] 是新关卡进度；结算或退出正式战斗立即清理。
func _on_progress(_progress: int) -> void:
	_check_boundary()

## 战局身份失效或目标离场时清理当前来源。
func _check_boundary() -> void:
	if not _sources.is_empty() and (not _battle.is_active() or _plant.is_death \
			or _plant.is_hypno or _plant.is_queued_for_deletion()):
		_clear()

## 离场时移除监听并恢复本节点负责的攻速因子。
func _exit_tree() -> void:
	EventBus.unsubscribe("main_game_progress_update", _on_progress)
	TreePauseManager.pause_factors_changed.disconnect(_check_boundary)
	_clear()

## 清空施放来源，撤销皇朝因子并停止更新。
func _clear() -> void:
	_sources.clear()
	set_physics_process(false)
	if is_instance_valid(_plant):
		_set_speed(1.0)

## 只在变化时将 [param rate] 写入原生速度合成器；生产时钟独立。
func _set_speed(rate: float) -> void:
	var factor := Character000Base.E_Influence_Speed_Factor.Dynasty # 皇朝专用乘数。
	if _plant.influence_speed_factors.get(factor, 1.0) != rate:
		_plant.update_speed_factor(rate, factor)
