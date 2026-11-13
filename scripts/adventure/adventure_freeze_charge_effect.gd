## 冻结值按目标独立累积；只降低基础行走速度，满十点交由原生冰冻接口。
extends Node
class_name AdventureFreezeChargeEffect

## 同一目标唯一的冻结值状态节点，来自不同命中的点数在此相加。
const NODE_NAME: StringName = &"AdventureFreezeChargeEffect"
## 触发冰冻所需的点数；达到阈值归零，多余点数不保留。
const MAX_POINTS: float = 10.0
## 每点减少的基础移速比例及深蓝滤镜深度。
const PER_POINT: float = 0.1
## 参照原寒冰菇的完全冰冻秒数。
const FREEZE_SECONDS: float = 3.0
## 原生冰冻结束后的减速秒数。
const FOLLOWUP_SLOW_SECONDS: float = 5.0
## 冻结值满深度的深蓝色，实际活跃点数为一至九时按比例混色。
const DEEP_BLUE: Color = Color(0.08, 0.20, 0.65, 1.0)
## 正常出战的受控僵尸，物种自身决定是否接受寒冷。
var _target: Zombie000Base
## 所属战场及轮次、阶段共同隔离旧的累积状态。
var _game: MainGameManager
## 授予点数时的轮次，换轮后清除原有点数。
var _round: int = -1
## 冒险阶段资源身份，普通到噩梦时不沿用旧点数。
var _phase: StagePhaseDefinition
## 当前未触发冰冻的点数，归零时撤销本状态的移速与滤镜来源。
var _points: float = 0.0

## 为 [param target] 累加 [param points] 点冻结值；无效数值、寒冷免疫及冻后保护期返回false。
## 原生冰冻期间及真正解冻后一秒均不接受新点数，首次接触也遵守该窗口。
static func apply_to(target: Character000Base, points: float) -> bool:
	var zombie: Zombie000Base = target as Zombie000Base # 僵王没有普通移动组件，也保留其寒冷免疫。
	if not is_instance_valid(zombie) or zombie.is_death or zombie.is_hypno \
			or zombie.is_queued_for_deletion() or not zombie.is_inside_tree() \
			or zombie.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_finite(points) or points <= 0.0 or not zombie.can_receive_cold() \
			or zombie.is_ice_charge_blocked() or not is_instance_valid(zombie.move_component):
		return false
	var game: MainGameManager = Global.main_game # 累积只能发生在当前正式战斗。
	if not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion() \
			or game.get_tree().current_scene != game or not game.is_ancestor_of(zombie) \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		return false
	var effect: AdventureFreezeChargeEffect = zombie.get_node_or_null(NodePath(NODE_NAME)) as AdventureFreezeChargeEffect # 目标唯一的累积容器。
	if effect == null:
		effect = AdventureFreezeChargeEffect.new()
		effect.name = NODE_NAME
		effect._target = zombie
		zombie.add_child(effect)
	elif effect._game != game or effect._round != game.curr_game_round \
			or effect._phase != AdventureSession.get_active_phase(game.game_para):
		effect.clear()
	effect._game = game
	effect._round = game.curr_game_round
	effect._phase = AdventureSession.get_active_phase(game.game_para)
	effect._points = minf(MAX_POINTS, effect._points + points)
	if effect._points >= MAX_POINTS:
		effect.clear()
		zombie.be_ice_freeze(FREEZE_SECONDS, FOLLOWUP_SLOW_SECONDS)
	else:
		effect._apply_sources()
		effect.set_physics_process(true)
	return true

## 状态跟随角色的暂停和生命周期，不使用墙钟计算恢复期。
func _ready() -> void:
	set_physics_process(false)
	_target.signal_character_death.connect(clear)
	_target.signal_character_be_hypno.connect(clear)

## [param _delta] 不推进点数；本帧只检查目标和战场是否仍然有效。
func _physics_process(_delta: float) -> void:
	if not _battle_active():
		clear()

## 原生寒冷免疫改变、死亡、魅惑或切换阶段均终止旧点数。
func _battle_active() -> bool:
	return is_instance_valid(_target) and not _target.is_death and not _target.is_hypno \
		and not _target.is_queued_for_deletion() and _target.is_inside_tree() and _target.can_receive_cold() \
		and _target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.is_ancestor_of(_target) and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 点数只写本节点的移动来源与独立蓝色通道，不改变啃咬速度或原有冰色。
func _apply_sources() -> void:
	if not is_instance_valid(_target):
		return
	if is_instance_valid(_target.move_component):
		_target.move_component.set_move_rate_source(get_instance_id(), maxf(0.0, 1.0 - _points * PER_POINT))
	if is_instance_valid(_target.body):
		_target.body.set_other_color(BodyCharacter.E_ChangeColors.FreezeCharge,
			Color.WHITE.lerp(DEEP_BLUE, clampf(_points * PER_POINT, 0.0, 1.0)))

## 只移除本状态的点数、移速来源和滤镜，不解除原生冰冻或其他减速。
func clear() -> void:
	_points = 0.0
	_apply_sources()
	set_physics_process(false)

## 大蒜换行保留点数及独立来源；真正离场才撤销，避免换行成为免费净化。
func _exit_tree() -> void:
	if is_instance_valid(_target) and _target.is_changing_lane:
		return
	clear()
