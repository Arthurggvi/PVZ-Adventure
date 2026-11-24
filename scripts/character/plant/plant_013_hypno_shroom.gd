## 魅惑菇保留原版啃食入口，转职按原生种植、睡眠和死亡事件发动。
extends Plant000Base
class_name Plant013HypnoShroom

## 配置在出战实例出生前冻结。
var _rules: Dictionary[String, Dictionary] = {}
## 只有成功放置的植株能通过随后真实的唤醒事件发动幻觉。
var _placed: bool = false
## 在离树准备时区分种下与恢复、关卡预置。
var _new_placement: bool = false

## [param events] 为合法冻结转职；白昼耐性在原生首次睡眠判断前生效。
func configure_promotions(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 效果参数不依赖后续库存。
		_rules[String(event.kind)] = event.duplicate(true)
	if _rules.has("hypno_day_awake"):
		is_sleep_in_day = false

## [param origin] 为当前事务来源，复生和读档不会重放种下事件。
func prepare_placement_action(origin: PlantCell.PlacementOrigin = PlantCell.PlacementOrigin.Player) -> bool:
	_new_placement = origin in [PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.Spawned,
		PlantCell.PlacementOrigin.Companion, PlantCell.PlacementOrigin.Transformation]
	return true

## 成功占格后开始监听实际唤醒。原生夜晚和白昼耐性在这一步发动。
func commit_placement_action() -> void:
	if _placed:
		return
	_placed = true
	if _new_placement and _illusion_on_placement():
		_cast_illusion()

## 睡眠组件先提交状态，再接收其从睡眠到清醒的变化。
func ready_norm_signal_connect() -> void:
	super()
	if _rules.has("hypno_illusion"):
		sleep_component.signal_not_is_sleep.connect(_on_awakened)

## 已恢复植株的后续真实唤醒可生效，恢复动作本身不重放种下或唤醒。
## [param state] 为存档原生状态。
func load_game_data_plant(state: Dictionary) -> void:
	super.load_game_data_plant(state)
	_placed = true

## [param attack_zombie] 本次啃食者；孢子分支把原生接触魅惑改为有效死亡触发。
func _be_zombie_eat_once_special(attack_zombie: Zombie000Base) -> void:
	if not (_rules.has("hypno_splash") and _promotions_enabled()):
		hypno_zombie(attack_zombie)

## 清醒时将 [param zombie] 交给原生魅惑。原版和临时无效化期间保留本株消耗。
func hypno_zombie(zombie: Zombie000Base) -> void:
	if is_sleeping or is_death or not is_instance_valid(zombie):
		return
	SoundManager.play_character_SFX("MindControlled")
	var battle: RepeaterShotContext = RepeaterShotContext.from_plant(self) if _promotions_enabled() else null # 正式占格才携带转职来源。
	if battle != null:
		AdventureHypnoCast.charm(zombie, battle, _rules)
	else:
		zombie.be_hypno()
	character_death()

## 在基类释放格子和来源之前冻结亡语资格，再按原死亡顺序结算。
func character_death() -> void:
	if is_death:
		return
	var battle: RepeaterShotContext # 仅真实死亡、清醒和已选孢子同时成立时捕获。
	if not is_sleeping and is_can_death_language and death_recording_enabled \
			and _rules.has("hypno_splash") and _promotions_enabled():
		battle = RepeaterShotContext.from_plant(self)
	var origin: Vector2 = global_position # 原地世界位置在释放格子之前采样。
	super()
	if battle != null:
		SoundManager.play_character_SFX("MindControlled")
		AdventureHypnoCast.spread_to_nearest(origin, int(_rules["hypno_splash"].count), battle, _rules)

## 只允许清醒状态变化后的正常发动，区分常醒规则与日眠苏醒。
func _on_awakened() -> void:
	if _placed and not _illusion_on_placement():
		_cast_illusion()

## 白昼耐性和真实夜战把幻觉触发从唤醒切到种下。
func _illusion_on_placement() -> bool:
	return _rules.has("hypno_day_awake") or not sleep_component.is_sleep_environment()

## 九宫格以发动时的实际占格为准；已持有的友军不重复赋能。
func _cast_illusion() -> void:
	if not _rules.has("hypno_illusion") or not _promotions_enabled() or is_sleeping:
		return
	var battle: RepeaterShotContext = RepeaterShotContext.from_plant(self) # 拒绝换场、预览和结算期。
	if battle != null:
		AdventureHypnoCast.spread_in_area(plant_cell, battle, _rules)

## 词条的临时无效化不改变原版魅惑入口。
func _promotions_enabled() -> bool:
	return not _rules.is_empty() and not has_node(NodePath(AdventurePlantNullification.NODE_NAME))
