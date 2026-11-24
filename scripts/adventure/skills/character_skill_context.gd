## 施放瞬间的战局身份快照；效果不能通过陈旧引用操作下一轮或下一阶段。
extends RefCounted
class_name CharacterSkillContext

## 发出技能的完整战场，不持有全局玩家档案。
var game: MainGameManager
## 施放时的种植空间身份。
var board: BoardRuntime
## 当前战场轮次，避免旧效果泄漏到多轮重开。
var round_index: int
## 施放时的冒险阶段。
var phase: StagePhaseDefinition
## 施放的技能 ID，用于日志与效果来源。
var skill_id: StringName

## 将 [param battle] 和 [param id] 绑定到调用瞬间的真实场景。
func _init(battle: MainGameManager, id: StringName) -> void:
	game = battle
	skill_id = id
	if is_instance_valid(battle):
		board = battle.board
		round_index = battle.curr_game_round
		phase = AdventureSession.get_active_phase(battle.game_para)

## 本次施放的战局和阶段仍存在且允许操作时返回 true。
func is_active() -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game == Global.main_game and game.get_tree().current_scene == game \
		and game.board == board and board != null and game.curr_game_round == round_index \
		and AdventureSession.owns_battle(game.game_para) \
		and AdventureSession.get_active_phase(game.game_para) == phase \
		and AdventureSession.character_skill_id_for(game.game_para) == skill_id \
		and AdventureSession.challenge_state in [AdventureSession.ChallengeState.NORMAL_ACTIVE, \
			AdventureSession.ChallengeState.NIGHTMARE_ACTIVE, AdventureSession.ChallengeState.TERMINAL_ACTIVE] \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not game.get_tree().paused and not PVZCheat.is_open()

## 为已有需要 RepeaterShotContext 的状态组件建立可验证的本局来源。
## 不伪造植物、出战卡 UID 或攻击倍率；只供战斗状态服务使用。
func state_source() -> RepeaterShotContext:
	if not is_active():
		return null
	var source := RepeaterShotContext.new() # 特殊冻结沿用已有的阶段失效判定。
	source.game = game
	source.board = board
	source.round_index = round_index
	source.phase = phase
	return source

## 查询本局所有合法敌对目标。[param bosses] 和 [param structures] 决定包含哪些特殊登记。
## [param require_hurt_box] 为 false 时允许作用于自身动作的效果选中临时无敌的目标。
func hostile_targets(bosses: bool = true, structures: bool = false,
		require_hurt_box: bool = true) -> Array[Character000Base]:
	return CharacterSkillTargetQuery.all_hostiles(self, bosses, structures, require_hurt_box)
