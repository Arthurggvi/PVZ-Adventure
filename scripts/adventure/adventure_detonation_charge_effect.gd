## 引爆值由目标唯一持有；满十点先归零，再通知最新命中来源安排一次爆炸。
extends Node
class_name AdventureDetonationChargeEffect

## 同一目标的唯一计数节点，来自不同植物的点数在此累积。
const NODE_NAME: StringName = &"AdventureDetonationChargeEffect"
## 触发引爆所需点数；达到时清零，超出部分不保留。
const MAX_POINTS: float = 10.0
## 当前目标，设施及已魅惑角色不接受该状态。
var _target: Character000Base
## 创建状态的正式战场，禁止跨场景使用旧点数。
var _game: MainGameManager
## 原轮次与冒险阶段共同隔离普通、噩梦和续战。
var _round: int = -1
## 阶段资源身份，非冒险时保持空。
var _phase: StagePhaseDefinition
## 尚未引爆的点数，有限且非负。
var _points: float = 0.0

## 给 [param target] 累加 [param points]；[param on_detonate] 接收世界位置和攻击行。
## 回调必须为独立来源快照，不能依赖即将销毁的弹体；无效目标/回调返回 false。
static func apply_to(target: Character000Base, points: float, on_detonate: Callable) -> bool:
	if not is_instance_valid(target) or not (target is Zombie000Base or target is ZB000Base) \
			or not target.can_receive_negative_effects() or target.is_death or target.is_hypno \
			or target.is_queued_for_deletion() or not target.is_inside_tree() \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not is_finite(points) or points <= 0.0 or not on_detonate.is_valid():
		return false
	var game: MainGameManager = Global.main_game # 只有当前正式战斗允许累积新点数。
	if not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion() \
			or game.get_tree().current_scene != game or not game.is_ancestor_of(target) \
			or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		return false
	var effect: AdventureDetonationChargeEffect = target.get_node_or_null(NodePath(NODE_NAME)) as AdventureDetonationChargeEffect # 一个目标只持有一个计数器。
	if effect == null:
		effect = AdventureDetonationChargeEffect.new()
		effect.name = NODE_NAME
		effect._target = target
		target.add_child(effect)
	elif effect._game != game or effect._round != game.curr_game_round \
			or effect._phase != AdventureSession.get_active_phase(game.game_para):
		effect.clear()
	effect._game = game
	effect._round = game.curr_game_round
	effect._phase = AdventureSession.get_active_phase(game.game_para)
	effect._points = minf(MAX_POINTS, effect._points + points)
	if effect._points >= MAX_POINTS:
		var position: Vector2 = target.global_position # 先冻结位置，再清零，回调重入也不会再次消费旧点数。
		var lane: int = target.lane # Boss 按来源命中时的空间坐标结算，行号只用于普通敌人筛选。
		effect.clear()
		on_detonate.call(position, lane)
	else:
		effect.set_physics_process(true)
	return true

## 暂停跟随目标；死亡与魅惑同步清空计数。
func _ready() -> void:
	set_physics_process(false)
	_target.signal_character_death.connect(clear)
	_target.signal_character_be_hypno.connect(clear)

## [param _delta] 不消耗点数；只核对目标和原战局身份。
func _physics_process(_delta: float) -> void:
	if not _battle_active():
		clear()

## 非法目标、离场、跨轮、阶段结束均拒绝保留旧计数。
func _battle_active() -> bool:
	return is_instance_valid(_target) and not _target.is_death and not _target.is_hypno \
		and not _target.is_queued_for_deletion() and _target.is_inside_tree() \
		and _target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and _game.get_tree().current_scene == _game \
		and _game.is_ancestor_of(_target) and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 清零后保留休眠节点供同一目标复用，不持有来源回调或延迟动作。
func clear() -> void:
	_points = 0.0
	set_physics_process(false)

## 换行时保留同一角色点数；真正离树才清空。
func _exit_tree() -> void:
	if is_instance_valid(_target) and _target is Zombie000Base \
			and (_target as Zombie000Base).is_changing_lane:
		return
	clear()
