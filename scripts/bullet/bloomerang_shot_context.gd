## 单次回旋镖的冻结规则与战局身份；派生弹保留来源，独立计算成长和命中。
extends RefCounted
class_name BloomerangShotContext

## 原战场，已发出的弹体不依赖母株继续存活。
var game: MainGameManager
## 发射时的棋盘身份，防止同场景更换棋盘后遗留攻击。
var board: BoardRuntime
## 发射轮次，补投与分裂不会重新捕获新轮次。
var round_index: int = -1
## 发射阶段的资源身份，区分普通与噩梦轮次复用。
var phase: StagePhaseDefinition
## 原发射植物实例，复生的新实例不能接收旧弹补投。
var source_id: int = 0
## 原始抛出方向，只有正负一；返程由弹体反向。
var launch_direction: int = 1
## 是否可以在真实回收后额外抛出一次。
var allow_echo: bool = false
## 是否为暴雨产生的单程弱镖。
var is_split: bool = false
## 每一程最多命中的不同目标数量。
var hit_limit: int = 3
## 岚刀的弹速倍率，不参与动画攻速或伤害。
var flight_multiplier: float = 1.0
## 每次有效命中后增加的基础伤害倍率。
var growth_step: float = 0.0
## 同一枚弹体的总成长倍率上限。
var growth_cap: float = 3.0
## 追猎按命中前已损生命计算的比例。
var missing_health_fraction: float = 0.0
## 追猎对僵王按最大生命限定的附伤比例。
var boss_bonus_cap_fraction: float = 0.002
## 是否在有效命中后分裂；弱镖永久关闭此入口。
var split_enabled: bool = false
## 本枚弹体的基础伤害倍率；弱镖不继承母镖的成长次数。
var base_multiplier: float = 1.0
## 出手时的出战伤害修正，后续派生不再读取原植物。
var damage_multiplier: float = 1.0
## 共享词条的单次攻击上下文，由发射事务在实际出手时捕获。
var attack_context: PlantAttackContext
## 暴雨派生弹的基础伤害比例。
var _weak_base_multiplier: float = 0.5

## 从 [param plant] 与事件表 [param rules] 冻结一次自然攻击。
## [param throw_direction] 规范为正负一；[param allow_followup] 仅允许根镖取得螺旋资格。
static func from_plant(plant: Plant000Base, rules: Dictionary,
		throw_direction: int, allow_followup: bool = true) -> BloomerangShotContext:
	if not is_instance_valid(plant) or not is_instance_valid(Global.main_game):
		return null
	var shot := BloomerangShotContext.new() # 事务开始时固定战场身份，不由延迟子弹重建。
	shot.game = Global.main_game
	shot.board = shot.game.board
	shot.round_index = shot.game.curr_game_round
	shot.phase = AdventureSession.get_active_phase(shot.game.game_para)
	shot.source_id = plant.get_instance_id()
	shot.launch_direction = -1 if throw_direction < 0 else 1
	if not shot.is_active() or not shot.source_present(plant):
		return null
	shot.damage_multiplier = maxf(0.0, plant.battle_damage_multiplier)
	shot.allow_echo = allow_followup and rules.has("bloomerang_spiral")
	shot.hit_limit = 3 + maxi(0, int(_number(rules, "bloomerang_slice", "extra_hits", 2.0))) \
		if rules.has("bloomerang_slice") else 3
	if rules.has("bloomerang_storm_blade"):
		shot.flight_multiplier += maxf(0.0, _number(rules, "bloomerang_storm_blade", "flight_speed_bonus", 0.7))
	if rules.has("bloomerang_crescent"):
		shot.growth_step = maxf(0.0, _number(rules, "bloomerang_crescent", "step", 0.3))
		shot.growth_cap = maxf(1.0, _number(rules, "bloomerang_crescent", "max_multiplier", 3.0))
	if rules.has("bloomerang_hunt"):
		shot.missing_health_fraction = clampf(_number(rules, "bloomerang_hunt", "missing_health_ratio", 0.09), 0.0, 1.0)
		shot.boss_bonus_cap_fraction = clampf(_number(rules, "bloomerang_hunt", "boss_cap_ratio", 0.002), 0.0, 1.0)
	shot.split_enabled = rules.has("bloomerang_rain")
	shot._weak_base_multiplier = clampf(_number(rules, "bloomerang_rain", "weak_base_multiplier", 0.5), 0.0, 1.0)
	return shot

## 只允许原战场、棋盘、轮次与阶段继续攻击；普通暂停由节点的物理时钟处理。
func is_active() -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game == Global.main_game and game.get_tree().current_scene == game and game.board == board \
		and board != null and game.curr_game_round == round_index \
		and AdventureSession.get_active_phase(game.game_para) == phase \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## [param plant] 必须是仍登记在原战场的原实例；睡眠、零攻速和无效化不抹掉其身体。
func source_present(plant: Plant000Base) -> bool:
	if not is_instance_valid(plant) or plant.get_instance_id() != source_id \
			or plant.is_death or plant.is_queued_for_deletion() or not plant.is_inside_tree() \
			or not is_active() or not game.is_ancestor_of(plant):
		return false
	var cell: PlantCell = plant.plant_cell # 按稳定格子身份跟随移动平台，不依赖发射时像素位置。
	return is_instance_valid(cell) and not cell.is_queued_for_deletion() \
		and cell.board == board and cell.living_plants().has(plant)

## 以 [param throw_direction] 派生同次事务的另一枚根镖，保留每枚独立的回收资格。
func for_direction(throw_direction: int) -> BloomerangShotContext:
	var result: BloomerangShotContext = _copy() # 弹体各持独立快照，不能互相修改方向。
	result.launch_direction = -1 if throw_direction < 0 else 1
	return result

## 额外抛出的单枚回旋镖保留攻击词条，但不能再次触发螺旋。
func for_echo() -> BloomerangShotContext:
	var result: BloomerangShotContext = _copy() # 保留原轮次，不能在结算回调中跨轮发射。
	result.allow_echo = false
	return result

## 暴雨沿 [param throw_direction] 创建半基础伤害的新镖；不继承成长、不折返且不再分裂。
func for_split(throw_direction: int) -> BloomerangShotContext:
	var result: BloomerangShotContext = for_direction(throw_direction) # 弱镖的伤害成长由新弹体单独记录。
	result.is_split = true
	result.allow_echo = false
	result.split_enabled = false
	result.base_multiplier = _weak_base_multiplier
	return result

## 复制冻结标量与战局引用，不读取当前植物、阶段或卡牌。
func _copy() -> BloomerangShotContext:
	var result := BloomerangShotContext.new() # RefCounted 不使用动态属性枚举复制。
	result.game = game
	result.board = board
	result.round_index = round_index
	result.phase = phase
	result.source_id = source_id
	result.launch_direction = launch_direction
	result.allow_echo = allow_echo
	result.is_split = is_split
	result.hit_limit = hit_limit
	result.flight_multiplier = flight_multiplier
	result.growth_step = growth_step
	result.growth_cap = growth_cap
	result.missing_health_fraction = missing_health_fraction
	result.boss_bonus_cap_fraction = boss_bonus_cap_fraction
	result.split_enabled = split_enabled
	result.base_multiplier = base_multiplier
	result.damage_multiplier = damage_multiplier
	result.attack_context = attack_context
	result._weak_base_multiplier = _weak_base_multiplier
	return result

## 从 [param rules] 中读取 [param event] 的 [param parameter]；非字典或非法数字退回 [param fallback]。
static func _number(rules: Dictionary, event: String, parameter: String, fallback: float) -> float:
	var payload: Variant = rules.get(event, {}) # 空字典仍是已启用事件，仅参数使用默认值。
	if not payload is Dictionary:
		return fallback
	var value: Variant = payload.get(parameter, fallback) # 拒绝非数值和非有限参数影响飞行终止。
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback
