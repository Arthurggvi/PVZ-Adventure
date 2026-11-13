## 双发弹体与持续场共用的战局快照；派生效果不重新读取卡牌或复生后的植物。
extends RefCounted
class_name RepeaterShotContext

## 本次发射所属的真实战场。
var game: MainGameManager
## 发射时的种植空间身份，防止同场更换棋盘后旧效果继续生效。
var board: BoardRuntime
## 同一战场内的轮次身份。
var round_index: int = -1
## 冒险普通与噩梦的阶段身份。
var phase: StagePhaseDefinition
## 原植物实例标识，复生或重新种植不能继承旧漩涡治疗。
var source_id: int = 0
## 原植物弱引用，已发弹体不延长植物生命。
var _source_ref: WeakRef
## 出手时的卡片与原光环伤害倍率，仅应用一次。
var damage_multiplier: float = 1.0
## 可选攻击词条快照，逐目标由原伤害入口消费。
var attack_context: PlantAttackContext
## 发射行，独立场使用命中时的真实行作为局部中心。
var lane: int = -1
## 来源地块的真实格距，仅供盘外查询回退。
var cell_pitch: Vector2 = Vector2.ONE

## 从实际出手的 [param plant] 捕获战局与原株；非正式战斗返回空。
static func from_plant(plant: Plant000Base) -> RepeaterShotContext:
	if not is_instance_valid(plant) or not is_instance_valid(Global.main_game):
		return null
	var shot := RepeaterShotContext.new() # 每枚根弹独享来源，子星继承同一个只读快照。
	shot.game = Global.main_game
	shot.board = shot.game.board
	shot.round_index = shot.game.curr_game_round
	shot.phase = AdventureSession.get_active_phase(shot.game.game_para)
	shot.source_id = plant.get_instance_id()
	shot._source_ref = weakref(plant)
	shot.lane = plant.lane
	if not shot.is_active() or shot.source_plant() == null:
		return null
	shot.damage_multiplier = maxf(0.0, plant.battle_damage_multiplier)
	shot.attack_context = plant.capture_attack_context()
	shot.cell_pitch = shot.board.local_pitch(plant.plant_cell)
	return shot

## 已发攻击可以脱离母株，但不能脱离原战场、棋盘、轮次或阶段。
func is_active() -> bool:
	return is_same_battle() and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 核对战局身份但不要求仍在战斗阶段，只供已结算命中的治疗与纯视觉兑现。
func is_same_battle() -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game == Global.main_game and game.get_tree().current_scene == game and game.board == board \
		and board != null and game.curr_game_round == round_index \
		and AdventureSession.get_active_phase(game.game_para) == phase

## 返回仍占据原战场真实地块的原植物；死亡、铲除和新实例均返回空。
## [param require_active] 仅可在兑现已完成伤害的治疗时设false，不能据此开始新攻击。
func source_plant(require_active: bool = true) -> Plant000Base:
	var plant: Plant000Base = _source_ref.get_ref() as Plant000Base if _source_ref != null else null # 弱引用仅在兑现治疗时解包。
	if (not is_active() if require_active else not is_same_battle()) \
			or not is_instance_valid(plant) or plant.get_instance_id() != source_id \
			or plant.is_death or plant.is_queued_for_deletion() or not plant.is_inside_tree() \
			or not game.is_ancestor_of(plant):
		return null
	var cell: PlantCell = plant.plant_cell # 移动平台保留同一格身份，位置无需缓存。
	return plant if is_instance_valid(cell) and cell.board == board and cell.living_plants().has(plant) else null

## 在 [param position] 和 [param target_lane] 查询当前格距；不把盘外爆心吸附到最近格。
func pitch_at(position: Vector2, target_lane: int) -> Vector2:
	var cell: PlantCell = board.nearest_cell(position, target_lane) if board != null else null # 最近格只提供尺寸。
	var pitch: Vector2 = board.local_pitch(cell) if cell != null else cell_pitch # 稀疏布局仍保留真实世界单位。
	return Vector2(maxf(1.0, pitch.x), maxf(1.0, pitch.y))

## 将 [param base_damage] 乘以发射时的伤害倍率；百分比跳伤不调用此函数。
func scaled_damage(base_damage: int) -> int:
	return maxi(0, roundi(float(base_damage) * damage_multiplier))

## [param casualty] 只接受本次普通伤害返回的实际死者，不监听未来的任意死亡。
func on_kill(casualty: Character000Base) -> void:
	if attack_context != null:
		attack_context.resolve_kill(casualty)

## 仅为仍存活的原实例恢复 [param actual_loss] 点实际吸取值；返回真正恢复的生命。
func heal_original(actual_loss: int) -> int:
	var plant: Plant000Base = source_plant(false) # 末击同步进入结算仍兑现实吸，跨阶段或替代植物不能受益。
	return plant.hp_component.heal(actual_loss) if plant != null and actual_loss > 0 else 0
