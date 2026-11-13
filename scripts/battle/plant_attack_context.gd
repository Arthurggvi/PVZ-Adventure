## 冻结植物单次攻击的来源与词条；只在命中时读取当前阳光，不依赖母株或弹体存活。
extends RefCounted
class_name PlantAttackContext

## 近身增伤达到两倍的格距上界。
const CLOSE_FULL_CELLS: float = 0.5
## 原恐惧区域的外缘格距；达到此处时恢复原伤害。
const CLOSE_EDGE_CELLS: float = 189.0 / 80.0
## 光能击杀实际掉落的单份阳光价值。
const KILL_SUN_VALUE: int = 8

## 只作用于僵尸一、二类防具的倍率，不改变临时生命池或本体伤害。
var armor_multiplier: float = 1.0
## 来源所属战场；跨场景后停止修饰与奖励。
var _game: MainGameManager
## 来源发出攻击的轮次，阻止旧攻击影响下一轮。
var _round_index: int = -1
## 冒险阶段资源身份；普通到噩梦可复用轮次，非冒险保持空。
var _phase: StagePhaseDefinition
## 发射者地面世界坐标快照，不使用会随跳跃变化的身体或枪口坐标。
var _origin: Vector2 = Vector2.ZERO
## 来源地块的真实横向间距，单位为世界像素。
var _cell_pitch: float = 1.0
## 本次攻击是否带有近距离增伤。
var _close_damage: bool = false
## 本次攻击是否带有动态阳光增伤和击杀掉落。
var _solar: bool = false
## 本次有效命中待消费的同步奖励资格；负一为空，不能跨帧或重复奖励。
var _reward_frame: int = -1
## 同一攻击上下文已奖励的死亡角色，防止重复回调重复掉落。
var _rewarded_ids: Dictionary[int, bool] = {}

## 从 [param plant] 捕获地面位置、真实格距和战场；无效果或非活动战场返回空。
## [param close_damage] 启用近伤；[param armor_multiplier] 是防具倍率，非法值按一倍。
## [param solar] 启用光能词条；冻结规则后不再读取植物或共享来源。
static func capture(plant: Plant000Base, close_damage: bool,
		armor_multiplier: float, solar: bool) -> PlantAttackContext:
	# 本次规范化后的防具倍率只允许增伤，不接纳非有限参数。
	var factor: float = maxf(1.0, armor_multiplier) if is_finite(armor_multiplier) else 1.0
	if not close_damage and factor <= 1.0 and not solar:
		return null
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	var game: MainGameManager = Global.main_game # 来源必须属于当前战场，预览不能产生攻击上下文。
	if not is_instance_valid(game) or not game.is_ancestor_of(plant):
		return null
	var context: PlantAttackContext = PlantAttackContext.new() # 一次攻击独享且可随弹体变换保留的快照。
	context._game = game
	context._round_index = game.curr_game_round
	context._phase = AdventureSession.get_active_phase(game.game_para)
	if not context.is_active():
		return null
	context._origin = plant.global_position
	context._cell_pitch = maxf(1.0, game.board.local_pitch(plant.plant_cell).x
		if game.board != null else plant.plant_cell.get_global_rect().size.x)
	context._close_damage = close_damage
	context.armor_multiplier = factor
	context._solar = solar
	return context

## 以 [param base_damage] 为已含出战卡与原光环的伤害，按 [param target] 地面位置修饰一次。
## 阳光每十点增加百分之一，允许非整十余额；最高额外百分之一千，即总十一倍。
## 失效战场或目标返回零；无正伤害时不把状态技能变成攻击。
## 调用方必须在本次伤害后同步调用 [method resolve_kill]，未致死也传空值消费奖励资格。
func modify_damage(base_damage: int, target: Character000Base) -> int:
	_reward_frame = -1
	if base_damage <= 0 or not is_active() or not is_instance_valid(target):
		return 0
	var factor: float = 1.0 # 仅本次命中的乘数，不回写弹体基础攻值或出战卡。
	if _close_damage:
		var cells: float = _origin.distance_to(target.global_position) / _cell_pitch # 地面欧氏距离对应的真实格数。
		factor *= 1.0 + clampf((CLOSE_EDGE_CELLS - cells)
			/ (CLOSE_EDGE_CELLS - CLOSE_FULL_CELLS), 0.0, 1.0)
	if _solar and is_instance_valid(_game.card_manager):
		var slots: CardSlotBattle = _game.card_manager.card_slot_battle # 读取当前实际余额，包含收集和种植扣费。
		if is_instance_valid(slots):
			factor *= 1.0 + minf(10.0, maxf(0.0, float(slots.sun_value)) / 1000.0)
	_reward_frame = Engine.get_process_frames() if _solar else -1
	return maxi(0, roundi(float(base_damage) * factor))

## [param casualty] 必须来自本次伤害返回的真实死亡者，可为承受转伤的保护者。
## 消费本次命中资格；最后一击同步触发结算后仍可奖励，但不能跨帧、跨阶段或监听后续死亡。
## [param casualty] 为空也必须消费资格；本次已排队释放的实际死者仍可同步掉落。
func resolve_kill(casualty: Character000Base) -> void:
	var eligible: bool = _reward_frame == Engine.get_process_frames() # 只兑现本帧刚完成的那次有效攻击。
	_reward_frame = -1
	if not eligible or not _solar or not _same_battle_identity() \
			or not is_instance_valid(casualty) or not casualty.is_death:
		return
	if not (casualty is Zombie000Base or casualty is ZB000Base) or not _game.is_ancestor_of(casualty):
		return
	var identity: int = casualty.get_instance_id() # 同一上下文按实际死者身份去重。
	if _rewarded_ids.has(identity) or not is_instance_valid(_game.suns) \
			or not _game.suns.is_inside_tree() or _game.suns.is_queued_for_deletion():
		return
	_rewarded_ids[identity] = true
	BattleSunDrop.spawn(_game, casualty.global_position, KILL_SUN_VALUE)

## 只允许原轮次、原阶段的正式战斗开始新命中；结算资格不会放宽此伤害门禁。
func is_active() -> bool:
	return _same_battle_identity() \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 战场身份不含结束门禁，仅供已开始命中的同步奖励核对；普通与噩梦按资源身份区分。
func _same_battle_identity() -> bool:
	return is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.curr_game_round == _round_index \
		and AdventureSession.get_active_phase(_game.game_para) == _phase
