## 恐惧以独立来源反转行走并禁用攻击，不改变魅惑阵营或原生转身状态。
extends Node
class_name AdventureFearEffect

## 每个目标复用一个恐惧实例，重施仅刷新剩余秒数。
const NODE_NAME: StringName = &"AdventureFearEffect"
## 当前被恐惧的僵尸，Boss 没有统一行走能力，因此不接受该效果。
var _target: Zombie000Base
## 状态所属的实际战场，不能沿用到新场景。
var _game: MainGameManager
## 冻结创建时的游戏轮次。
var _round: int = -1
## 冒险普通与噩梦可共用轮次，额外记录具体阶段。
var _phase: StagePhaseDefinition
## 剩余战斗秒数，随场景暂停与倍速推进。
var _remaining: float = 0.0
## 当前是否已登记反向行走来源。
var _active := false

## 为 [param target] 添加 [param duration] 秒恐惧；返回是否接受请求。
static func apply_to(target: Character000Base, duration: float) -> bool:
	if not is_instance_valid(target) or not target is Zombie000Base \
			or not target.can_receive_control_effects() \
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
	var zombie: Zombie000Base = target as Zombie000Base # 只接入具备统一移动和攻击门禁的角色。
	if not is_instance_valid(zombie.move_component):
		return false
	var effect: AdventureFearEffect = target.get_node_or_null(NodePath(NODE_NAME)) as AdventureFearEffect # 原节点到期后保留，避免同帧重施撞上待删除节点。
	if effect == null:
		effect = AdventureFearEffect.new()
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

## 在角色入树后绑定死亡清理，所有状态都由本节点唯一持有。
func _ready() -> void:
	_target = get_parent() as Zombie000Base
	set_physics_process(false)
	_target.signal_character_death.connect(_clear)
	_target.signal_character_be_hypno.connect(_clear)

## [param duration] 刷新剩余时间；不会重复翻转方向。
func _grant(duration: float) -> void:
	_remaining = maxf(_remaining, duration)
	_active = true
	_target.move_component.set_flee_source(get_instance_id(), true)
	_target.body.set_other_color(BodyCharacter.E_ChangeColors.Fear, Color(0.24, 0.24, 0.24))
	set_physics_process(true)

## [param delta] 为战斗秒数，结束时只撤销自己的方向、攻击和滤镜来源。
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
		and _target.can_receive_control_effects() \
		and not _target.is_queued_for_deletion() and _target.is_inside_tree() \
		and is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.is_ancestor_of(_target) and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 到期或死亡均可重复调用；角色其他减速和攻击禁用原因保持不变。
func _clear() -> void:
	_remaining = 0.0
	set_physics_process(false)
	if not _active:
		return
	_active = false
	if is_instance_valid(_target):
		if is_instance_valid(_target.move_component):
			_target.move_component.set_flee_source(get_instance_id(), false)
		if is_instance_valid(_target.body):
			_target.body.set_other_color(BodyCharacter.E_ChangeColors.Fear, Color.WHITE)

## 大蒜换行短暂离树不结束状态；真正移除节点时撤销来源。
func _exit_tree() -> void:
	if is_instance_valid(_target) and _target.is_changing_lane:
		return
	_clear()
