## 沉默仅暂停等阶技能与持续输出，保留原生动作及基础生命、攻击成长。
extends Node
class_name AdventureSilenceEffect

## 每个目标复用一个沉默实例，时长刷新不会重建能力。
const NODE_NAME: StringName = &"AdventureSilenceEffect"
## 僵尸或 Boss；没有等阶技能接口的 Boss 仅表现状态滤镜。
var _target: Character000Base
## 状态所属的实际战场，不能沿用到新场景。
var _game: MainGameManager
## 冻结创建时的游戏轮次。
var _round: int = -1
## 冒险普通与噩梦可共用轮次，额外记录具体阶段。
var _phase: StagePhaseDefinition
## 剩余战斗秒数，重复命中取更长的剩余时间。
var _remaining: float = 0.0
## 是否已登记本次沉默来源。
var _active := false

## 为 [param target] 添加 [param duration] 秒沉默；返回是否接受请求。
static func apply_to(target: Character000Base, duration: float) -> bool:
	if not is_instance_valid(target) or not (target is Zombie000Base or target is ZB000Base) \
			or target.is_death or target.is_hypno or target.is_queued_for_deletion() or not target.is_inside_tree() \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_finite(duration) or duration <= 0.0:
		return false
	var game: MainGameManager = Global.main_game # 只给当前正式战斗中的真实角色授予控制状态。
	if not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion() \
			or game.get_tree().current_scene != game or not game.is_ancestor_of(target) \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		return false
	var effect: AdventureSilenceEffect = target.get_node_or_null(NodePath(NODE_NAME)) as AdventureSilenceEffect # 到期实例仍可被同帧安全复用。
	if effect == null:
		effect = AdventureSilenceEffect.new()
		effect.name = NODE_NAME
		target.add_child(effect)
	if effect._game != game or effect._round != game.curr_game_round \
			or effect._phase != AdventureSession.get_active_phase(game.game_para):
		effect._clear()
	effect._game = game
	effect._round = game.curr_game_round
	effect._phase = AdventureSession.get_active_phase(game.game_para)
	effect._grant(duration)
	return true

## 绑定死亡清理；僵尸在发出死亡信号前已冻结当刻等阶资格。
func _ready() -> void:
	_target = get_parent() as Character000Base
	set_physics_process(false)
	_target.signal_character_death.connect(_clear)
	_target.signal_character_be_hypno.connect(_clear)

## [param duration] 刷新剩余时间，只在首个来源进入时通知能力撤销输出。
func _grant(duration: float) -> void:
	_remaining = maxf(_remaining, duration)
	_active = true
	if _target is Zombie000Base:
		(_target as Zombie000Base).set_tier_suppressed(get_instance_id(), true)
	_target.body.set_other_color(BodyCharacter.E_ChangeColors.Silence, Color(0.55, 0.55, 0.55))
	set_physics_process(true)

## [param delta] 为战斗秒数；恢复只解除本来源，不补发过期事件或出生奖励。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		_clear()
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining == 0.0:
		_clear()

## 状态只能在同一场景、轮次、冒险阶段继续；魅惑与真正离场都清除负面控制。
func _battle_active() -> bool:
	return is_instance_valid(_target) and not _target.is_death and not _target.is_hypno \
		and not _target.is_queued_for_deletion() and _target.is_inside_tree() \
		and is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.is_ancestor_of(_target) and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 仅撤销本来源；亡语仍读取角色已经冻结的沉默资格。
func _clear() -> void:
	_remaining = 0.0
	set_physics_process(false)
	if not _active:
		return
	_active = false
	if is_instance_valid(_target):
		if _target is Zombie000Base:
			(_target as Zombie000Base).set_tier_suppressed(get_instance_id(), false)
		if is_instance_valid(_target.body):
			_target.body.set_other_color(BodyCharacter.E_ChangeColors.Silence, Color.WHITE)

## 大蒜换行不清除沉默；真正拆除效果时恢复本来源管理的输出。
func _exit_tree() -> void:
	if _target is Zombie000Base and (_target as Zombie000Base).is_changing_lane:
		return
	_clear()
