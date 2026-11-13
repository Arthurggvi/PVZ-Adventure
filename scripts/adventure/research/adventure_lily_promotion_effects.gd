## 睡莲的周期治疗与护甲；只服务当前真正承托的植物，不修改植物原生行为时钟。
extends Node
class_name AdventureLilyPromotionEffects

## 承托和生命基数均来自这株真实睡莲。
var _plant: Plant000DownBase
## 首次就绪时绑定的战场，旧场景控制器不能向新战场发放收益。
var _game: MainGameManager
## 从冻结卡牌读取的周期规则。
var _rules: Dictionary[StringName, Dictionary] = {}
## 各效果只累计来源可生效的战斗时间。
var _elapsed: Dictionary[StringName, float] = {}

## [param plant] 为来源睡莲；[param events] 为本株冻结的转职事件。
func configure(plant: Plant000DownBase, events: Array[Dictionary]) -> void:
	_plant = plant
	for event: Dictionary in events: # 其他植物的事件不进入本控制器。
		var kind: StringName = StringName(event.get("kind", "")) # 同类周期只保留一份冻结规则。
		if kind in [&"lily_heal", &"lily_armor"]:
			_rules[kind] = event.duplicate(true)
			_elapsed[kind] = 0.0

## 等待父植物的原生生命组件就绪；离树配置阶段不读取 onready 成员。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	if not is_instance_valid(_plant):
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 绑定只执行一次；正常暂停和承托重挂不会重置已经累计的周期。
func _bind() -> void:
	_game = Global.main_game
	set_process(not _rules.is_empty())

## [param delta] 使用战场的游戏时间；无效化、结算与离场期间不累计收益。
func _process(delta: float) -> void:
	if not _source_active():
		return
	for kind: StringName in _rules: # 不同规则独立累计，后续调整间隔也不会互相干扰。
		var rule: Dictionary = _rules[kind] # 本株不可变规则。
		var interval: float = maxf(0.1, float(rule.get("interval_seconds", 5.0))) # 避免异常零间隔。
		_elapsed[kind] += delta
		while _elapsed[kind] >= interval: # 低帧率仍按实际经过的完整周期结算。
			_elapsed[kind] -= interval
			_grant(kind, float(rule.get("health_fraction", 0.1)))

## 来源必须仍是本战场当前承托者，死亡或等阶无效化后不再产生新收益。
func _source_active() -> bool:
	return is_instance_valid(_plant) and is_instance_valid(_game) \
		and not _plant.is_death and not _plant.is_queued_for_deletion() and _plant.is_inside_tree() \
		and _plant.can_process() and _plant.is_ancestor_of(self) \
		and not _plant.has_node(NodePath(AdventurePlantNullification.NODE_NAME)) \
		and not _game.is_queued_for_deletion() and _game.is_inside_tree() and _game == Global.main_game \
		and _game.get_tree().current_scene == _game and _game.is_ancestor_of(_plant) and _game.board != null \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false) \
		and is_instance_valid(_plant.plant_cell) and _plant.plant_cell.board == _game.board \
		and _plant.plant_cell.get_support_plant() == _plant

## 按来源最终最大生命的 [param fraction] 发放 [param kind]，不使用当前血量或护甲作基数。
func _grant(kind: StringName, fraction: float) -> void:
	if not _source_active() or _plant.hp_component == null or _plant.hp_component.is_death:
		return
	var amount: int = maxi(0, roundi(float(_plant.hp_component.max_hp) * fraction)) # 星级与最终生命词条已经投影。
	if amount <= 0:
		return
	for target: Plant000Base in _plant.supported_plants(): # 每次脉冲读取真实对象，铲除或换株后不沿用旧目标。
		var hp: HpComponentPlant = target.hp_component as HpComponentPlant # 复用可回复生命与可消耗护甲协议。
		if hp == null:
			continue
		if kind == &"lily_heal":
			hp.heal(amount)
		else:
			hp.grant_bonus_armor(amount)
