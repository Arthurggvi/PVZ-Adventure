## 一个正式遭遇的入场与分裂仪式。战斗提交由演员提供，特写节点拥有时停。
extends Node

## 三次特写和时停由同一个节点取得并归还。
const SplitPortraits = preload("res://scripts/character/zombie_boss/savior/savior_split_portraits.gd")
## 原画的祈祷、停姿和传送材质。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")
## 传送原画的完整显现时长。
const ARRIVAL_SECONDS := 0.96
## 同轮尚未执行会暂停的动作或处于攻击后的正常收手。
enum Stage { IDLE, ARRIVAL, ENTRANCE_PRAYER, SPLIT_PRAYER, SPLIT_BLACK, PORTRAITS, GROUP_READY, STRIKE_BLACK, CROSS, LOWER }

## 只保留排队演员的实例编号，清场和退场不必等到导演取出请求。
class Request:
	## 实际演员在本次战斗中的实例编号。
	var actor_id: int
	## 分裂请求携带角色提供的战斗操作；空回调为正常入场。Callable 不持有演员节点的所有权。
	var split: Callable

	## [param id] 标记演员，只有分裂时才提供 [param commit_split]。
	func _init(id: int, commit_split: Callable = Callable()) -> void:
		actor_id = id
		split = commit_split

## 本次实际取得的战斗宿主。
var _battle: MainGameManager
## 同一战场的演出宿主。由场景注入，避免与导演互相预加载。
var _arena
## 尚待播放的演出请求，取出时才解析演员。
var _queue: Array[Request] = []
## 当前半血仪式在落黑时唯一可调用的角色操作；取出后立即消费。
var _split_action: Callable
## 镜头顺序固定为本体、第二路分身、第四路分身。
var _members: Array[ZB000Base] = []
## 当前仪式所处的步骤。
var _stage := Stage.IDLE
## 当前步骤的时间。
var _elapsed := 0.0
## 复用当前战场的特写序列，正常入场不取得时停。
@onready var _portraits: SplitPortraits = $SplitPortraits

## [param battle] 提供正式镜头和棋盘，[param arena] 提供这一场战斗的演出通道。
func configure(battle: MainGameManager, arena: CanvasLayer) -> void:
	_battle = battle
	_arena = arena
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 18
	set_process(false)

## 为实际入场的 [param actor] 登记一次传送祈祷。
func queue_entrance(actor: ZB000Base) -> void:
	_queue.append(Request.new(actor.get_instance_id()))
	set_process(true)

## [param actor] 已锁住半血门槛，落黑时交给 [param commit_split] 提交并返回完整分身队形。
func queue_split(actor: ZB000Base, commit_split: Callable) -> void:
	_queue.append(Request.new(actor.get_instance_id(), commit_split))
	set_process(true)

## [param delta] 通常用战斗时钟。特写镜头和半速原画使用未缩放的电影时间。
func _process(delta: float) -> void:
	if not _battle.zombie_manager.is_game_running():
		cancel()
		return
	if get_tree().paused and not _portraits.active:
		return
	if _stage == Stage.IDLE:
		_open_next()
		return
	if not _has_members():
		_finish()
		return
	_elapsed += delta
	match _stage:
		Stage.ARRIVAL:
			_arena.savior_teleport.arrive(_members[0], _elapsed / ARRIVAL_SECONDS)
			if _elapsed >= ARRIVAL_SECONDS:
				_visual(_members[0]).stage_prayer(1.0, false)
				_set_stage(Stage.ENTRANCE_PRAYER)
		Stage.ENTRANCE_PRAYER:
			if _visual(_members[0]).is_ritual_pose_held():
				_try_flash(Stage.STRIKE_BLACK, _entrance_impact)
		Stage.SPLIT_PRAYER:
			if _visual(_members[0]).is_ritual_pose_held():
				_try_flash(Stage.SPLIT_BLACK, _split_in_black)
		Stage.PORTRAITS:
			if _portraits.advance(delta, _arena.savior_flash, _arena.present_frozen_ritual) and _stage == Stage.PORTRAITS:
				_set_stage(Stage.GROUP_READY)
		Stage.GROUP_READY:
			if _elapsed >= 0.22:
				_try_flash(Stage.STRIKE_BLACK, _entrance_impact)
		Stage.CROSS:
			if not _arena.savior_entry_cross.is_running():
				_lower_hands()
		Stage.LOWER:
			if _members.all(func(member: ZB000Base) -> bool: return _visual(member).animation != &"pray"): # 所有存活演员实际收手后再恢复。
				_finish()

## 取下一段可播放的真实入场，失效或已经退场的请求直接释放。
func _open_next() -> void:
	while not _queue.is_empty():
		var next: Request = _queue.pop_front() # 离场的演员无需主动从队列注销。
		var candidate: Object = instance_from_id(next.actor_id) # 已回收的实例解析为 null。
		if not _alive(candidate):
			continue
		var actor := candidate as ZB000Base # 存活和类型已由 _alive 确认。
		_members.assign([actor])
		_split_action = next.split
		if _split_action.is_valid():
			_visual(actor).stage_prayer(1.0, false)
			_set_stage(Stage.SPLIT_PRAYER)
		else:
			_arena.set_savior_light(actor, 0.0)
			_set_stage(Stage.ARRIVAL)
		return
	set_process(false)

## 等正在执行的黑闪自然退场，接入本次 [param next] 和落黑回调 [param impact]。
func _try_flash(next: Stage, impact: Callable) -> void:
	if _arena.savior_flash.play_ritual(_visual(_members[0]), impact):
		_set_stage(next)

## 只在整个屏幕已落黑时落位并提交新增的独立血池。补间使用正式景别。
func _split_in_black() -> void:
	if _stage != Stage.SPLIT_BLACK or not _has_members():
		return
	var commit := _split_action # 动作只消费一次，角色负责实际成员、生命及失败策略。
	_split_action = Callable()
	var clones: Array[ZB000Base] = commit.call() # 同步取得完整队形，镜头只读取结果。
	if _stage != Stage.SPLIT_BLACK:
		_restore_actors(clones) # 登记或血量观察者同步结束了战斗，不能重新取得镜头与暂停。
		return
	if clones.is_empty():
		_lower_hands()
		return
	_members.append_array(clones)
	if not _has_members() or not _battle.zombie_manager.is_game_running():
		_finish()
		return
	_set_stage(Stage.PORTRAITS)
	_portraits.begin(_members, _battle.camera_2d, _arena.savior_teleport, _arena.set_savior_light)

## 入场和三位合演在各自黑场时共用一次全局结算，每位自己打出十字。
func _entrance_impact() -> void:
	if _stage != Stage.STRIKE_BLACK or not _has_members():
		return
	_members[0].call(&"resolve_entrance_impact")
	if _battle.zombie_manager.is_game_running() and _stage == Stage.STRIKE_BLACK:
		_arena.savior_entry_cross.begin(_members)
		_set_stage(Stage.CROSS)

## 十字走完再同时收手，避免中途出现新的随机动作。
func _lower_hands() -> void:
	for member: ZB000Base in _members: # 各演员从各自停留的同一原画帧继续。
		if _alive(member):
			_visual(member).finish_ritual_pose()
	_set_stage(Stage.LOWER)

## 恢复参与者的灯光、受击和共同的行动时钟。
func _finish() -> void:
	_portraits.release()
	_restore_actors(_members)
	_members.clear()
	_split_action = Callable()
	_set_stage(Stage.IDLE)

## 为 [param actors] 中仍存活的演员收回传送并恢复行动，包含组提交过程中被同步打断的增援。
func _restore_actors(actors: Array[ZB000Base]) -> void:
	for member: ZB000Base in actors: # 各自归位并继续使用独立生命。
		if _alive(member):
			_arena.savior_teleport.finish_arrival(member)
			_visual(member).cancel_prayer()
			member.call(&"finish_ritual")

## 正式战斗结束时退回机位并清除待开场的请求。
func cancel() -> void:
	_queue.clear()
	if _stage != Stage.IDLE:
		_finish()
	set_process(false)

## 转到 [param next] 并从该步骤的第一拍开始。
func _set_stage(next: Stage) -> void:
	_stage = next
	_elapsed = 0.0

## 返回 [param actor] 的实际入场原画节点。
func _visual(actor: ZB000Base) -> SaviorVisual:
	return actor.get_node(^"Body/SaviorVisual") as SaviorVisual

## 演员还有有效可播放的出战实体。
func _alive(actor: Variant) -> bool:
	return is_instance_valid(actor) and actor is ZB000Base and actor.is_inside_tree() \
		and not actor.is_death and not actor.is_queued_for_deletion()

## 任一演员在演出中强制离场时安全结束事务和时停。
func _has_members() -> bool:
	return not _members.is_empty() and _members.all(_alive)
