## 阳光菇的单株转职生命周期；成熟、实际生产与死亡各自独立结算，子株继承冻结配方。
extends Node
class_name AdventureSunShroomPromotionEffects

## 本株真实阳光菇；只在入树并完成原版初始化后读取组件。
var _plant: Plant010SunShroom
## 本次出战场景，拒绝旧场景的晚到回调。
var _game: MainGameManager
## 来源卡片的不可变配方，供后续成熟扩散完整继承。
var _profile: PlantSpawnProfile
## 本株实际生产组件；额外奖励不进入生产事件。
var _production: CreateSunComponent
## 已验证的本物种事件副本，不从可变库存重新查询。
var _rules: Dictionary = {}
## 本株已经结算正常成熟，防止重复信号；不对下一代设置永久禁用。
var _maturity_handled: bool = false
## 已真实生产的等值储蓄；每株独立且最多五百。
var _savings: int = 0
## 本株储蓄上限；仅从冻结事件读取并限制到五百。
var _savings_cap: int = 0
## 死亡奖励是否已处理，防止同步死亡通知重入。
var _death_paid: bool = false

## [param plant] 为本株；[param events] 为目录验证后的冻结转职事件。
## 入树前只保存规则和安装光环，父节点就绪后才绑定组件，不在出生时补发成熟。
func configure(plant: Plant010SunShroom, events: Array[Dictionary]) -> void:
	_plant = plant
	for event: Dictionary in events: # 拒绝混入其他物种的生命周期事件。
		var kind: String = str(event.get("kind", "")) # 已验证的事件标识。
		if kind.begins_with("sunshroom_"):
			_rules[kind] = event.duplicate(true)
	if _rules.has("sunshroom_savings"):
		_savings_cap = clampi(int(_rules["sunshroom_savings"].get("cap", 500)), 0, 500)
	if _rules.has("sunshroom_moonlight"):
		var aura: AdventureMushroomAwakeAura = AdventureMushroomAwakeAura.new() # 复用具名唤醒来源。
		aura.configure(_plant)
		_plant.add_child(aura)

## 子节点先就绪；等待父节点的原版成长和产阳光组件完成初始化。
func _ready() -> void:
	if not is_instance_valid(_plant):
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 绑定本株真实战斗实例；预览与无配方植物不能触发卡片、扩散或储蓄副作用。
func _bind() -> void:
	_game = Global.main_game
	if _plant.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_instance_valid(_game) or not _game.is_ancestor_of(_plant):
		return
	_profile = _plant.plant_spawn_profile
	_production = _plant.create_sun_component
	if _profile == null or not _profile.matches_plant_type(CharacterRegistry.PlantType.P010SunShroom) \
			or not is_instance_valid(_production):
		return
	if _rules.has("sunshroom_spore_spread") or _rules.has("sunshroom_hive_mind"):
		_plant.signal_matured.connect(_on_matured)
	if _rules.has("sunshroom_savings"):
		_production.production_created.connect(_on_production_created)
		_plant.signal_character_death.connect(_on_death, CONNECT_ONE_SHOT)

## 只结算一次真实成熟；每株子菇自己的正常成长仍可触发相同事件。
func _on_matured() -> void:
	if _maturity_handled or not _battle_active() or not is_instance_valid(_plant) \
			or _plant.is_death or _plant.is_queued_for_deletion() or not _plant.is_grow:
		return
	_maturity_handled = true
	if _rules.has("sunshroom_hive_mind") and is_instance_valid(_game.card_manager):
		AdventureSunShroomCardEffects.halve_remaining_cooldowns(_game.card_manager.card_slot_battle)
	if _rules.has("sunshroom_spore_spread"):
		var radius: int = int(_rules["sunshroom_spore_spread"].get("radius", 3)) # 逻辑十字每个方向的距离。
		AdventureSunShroomPropagation.spread(_plant, radius)

## [param total_value] 是已创建阳光的实际总值；包括幼年、成年和生产加成，不包括奖励提现。
func _on_production_created(total_value: int) -> void:
	if total_value <= 0 or _death_paid or not _battle_active() or not is_instance_valid(_plant) \
			or _plant.is_death or _plant.is_queued_for_deletion():
		return
	_savings = mini(_savings_cap, _savings + total_value)

## 啃食、铲除、碾压等统一角色死亡信号均可结算；直接退场释放不视为死亡。
func _on_death() -> void:
	if _death_paid:
		return
	_death_paid = true
	var payout: int = _savings # 在任何创建回调前清空账本，防止重入或奖励再次记账。
	_savings = 0
	if payout > 0 and _battle_active() and is_instance_valid(_production):
		_production.spawn_specific_sun_batch(payout)

## 正式战斗、当前场景与有效阳光容器缺一不可，结算或续战等待不生成副作用。
func _battle_active() -> bool:
	return is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
			and _game == Global.main_game and _game.get_tree().current_scene == _game \
			and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
			and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false) \
			and is_instance_valid(_game.suns) and not _game.suns.is_queued_for_deletion()
