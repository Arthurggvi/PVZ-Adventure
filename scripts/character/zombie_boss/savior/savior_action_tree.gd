## 教堂救主按遭遇共用起手时钟、技能抽签和同一次出手。
extends "res://scripts/character/zombie_boss/savior/savior_prayer.gd"

## 同一动作中的全场声音由实际落点或下坠的第一位成员提交。
enum Cue { MADNESS_LANDING, DESPAIR_DESCENT, DESPAIR_LANDING }

## 从仪式结束或上次起手算起的基础动作秒数，按共同的行动倍率推进。
const PRAYER_SECONDS := Vector2(8.0, 6.0)
## 无垠和安乐使用同一场黑幕和实际抬掌余像。
const BlackFlash = preload("res://scripts/fx/savior_black_flash.gd")

## 按 Boss 总血条分组，各分组只维护一份行动进度。
class Encounter:
	## 登记顺序优先保留本体，阵亡后顺延给存活分身。
	var members: Array[Member] = []
	## 开场或分裂的合演期间不积累行动时钟。
	var ritual := true
	## 下一次起手之前剩余的动作秒。
	var remaining := 0.0
	## 本轮所有人的同一技能。
	var skill: Skill = Skill.NONE
	## 本轮实际起手的演员。
	var casters: Array[Member] = []
	## 仍未到抬掌释放帧的演员编号。
	var waiting: Dictionary[int, bool] = {}

## 当前场景的同一张战斗黑幕。
var _flash: BlackFlash
## 整组 ID 与曾登记过的原体、分身状态。
var _encounters: Dictionary[int, Encounter] = {}
## 每次起手只为整组抽取一次。
var _rng := RandomNumberGenerator.new()
## 每类全场表现最近一次实际发生的物理帧。
var _last_cue_frames: Dictionary[Cue, int] = {}

## [param flash] 属于当前正式棋盘的黑幕；随机序列也仅用于本场。
func configure(flash: BlackFlash) -> void:
	_flash = flash
	_rng.randomize()

## 按 [param actor] 的遭遇 ID 登记本体或已落位的分身。
func register(actor: Member) -> void:
	var id: int = actor.boss_encounter_group_id() # 分身继承本体编号。
	var encounter: Encounter = _encounters.get(id) # 第一名到场时建组。
	if encounter == null:
		encounter = Encounter.new()
		_encounters[id] = encounter
	encounter.members.append(actor)

## 独立死亡或撤离时移除 [param actor]，剩余分身继续沿用当前时钟。
func unregister(actor: Member) -> void:
	var id: int = actor.boss_encounter_group_id() # 父级可能已经在退出。
	var encounter: Encounter = _encounters.get(id) # 死亡与离树可以各通知一次。
	if encounter == null or not encounter.members.has(actor):
		return
	encounter.members.erase(actor)
	encounter.casters.erase(actor)
	encounter.waiting.erase(actor.get_instance_id())
	if encounter.members.is_empty():
		_encounters.erase(id)
		if is_instance_valid(_flash):
			_flash.cancel_void(id)
		return

## [param actor] 进入仪式时收回尚未出手的动作。已经开始的余波可自然完成。
func suspend(actor: Member) -> void:
	var encounter: Encounter = _encounters.get(actor.boss_encounter_group_id()) # 同一场分裂的成员共享锁。
	encounter.ritual = true
	encounter.skill = Skill.NONE
	encounter.casters.clear()
	encounter.waiting.clear()

## [param actor] 所在的仪式结束，整组从对应阶段重新等待一次完整间隔。
func resume(actor: Member) -> void:
	var encounter: Encounter = _encounters.get(actor.boss_encounter_group_id()) # 三名演员会在同一帧归位。
	if encounter == null or not encounter.ritual:
		return
	encounter.ritual = false
	encounter.remaining = _interval(actor)

## [param delta] 是本次战斗物理步长。整组用第一位存活成员的行动倍率推进一次。
func advance(delta: float) -> void:
	for encounter: Encounter in _encounters.values(): # 多个独立遭遇不会共用一次抽签。
		if encounter.ritual:
			continue
		_release_if_ready(encounter) # 某位在起手后阵亡时，其余成员可在下一步接手。
		var members: Array[Member] = _living_members(encounter) # 按登记顺序保留领头人，TMC-112 为整组提供同一倍率。
		if members.is_empty():
			continue
		encounter.remaining = maxf(0.0, encounter.remaining - delta * members[0].action_rate())
		if encounter.remaining > 0.0 and not is_zero_approx(encounter.remaining):
			continue
		if not members.all(_can_start):
			continue
		var available: Array[Skill] = [] # 从当前可用技能中等概率抽取一次，全组共用结果。
		for skill: Skill in [Skill.VOID, Skill.MADNESS, Skill.PEACE, Skill.DESPAIR, Skill.GOSPEL]: # 目标条件对同一战场的分身一致。
			if members[0].has_prayer_target(skill):
				available.append(skill)
		if not available.is_empty():
			_start(encounter, members, available[_rng.randi_range(0, available.size() - 1)])

## 从 [param actor] 请求指定的 [param skill]。同组仍须同时就绪并使用同一释放帧。
func request(actor: Member, skill: Skill) -> bool:
	if skill <= Skill.NONE or skill > Skill.GOSPEL:
		return false
	var encounter: Encounter = _encounters.get(actor.boss_encounter_group_id()) # 必须来自本场登记。
	if encounter == null or encounter.ritual or not encounter.members.has(actor):
		return false
	var members: Array[Member] = _living_members(encounter) # 手动请求也通过同一预备动作。
	return members.has(actor) and members.all(_can_start) and actor.has_prayer_target(skill) \
		and _start(encounter, members, skill)

## [param actor] 抵达真实抬掌帧；全组已到齐时，在这同一帧提交所有判定。
func prayer_reached(actor: Member) -> void:
	var encounter: Encounter = _encounters.get(actor.boss_encounter_group_id()) # 可能刚被半血仪式中断。
	if encounter != null and encounter.waiting.erase(actor.get_instance_id()):
		if encounter.skill == Skill.MADNESS:
			actor.prayer_visual().hold_prayer()
		_release_if_ready(encounter)

## 同一物理步只为 [param cue] 播一次全场效果，各处命中及局部绘制照常执行。
func claim_cue(cue: Cue) -> bool:
	var frame: int = Engine.get_physics_frames() # 同帧其他落点仍完整绘制及命中。
	if frame == _last_cue_frames.get(cue, -1):
		return false
	_last_cue_frames[cue] = frame
	return true

## 用 [param skill] 同时启动 [param encounter] 的 [param members]；福音优先分配独立格子。
func _start(encounter: Encounter, members: Array[Member], skill: Skill) -> bool:
	var claimed_cells: Dictionary[PlantCell, bool] = {} # 本轮已分配的福音格，其他技能不写入。
	encounter.skill = skill
	for actor: Member in members: # 所有人同一物理帧从原画第一帧起手。
		if actor.start_prayer(skill, claimed_cells):
			encounter.casters.append(actor)
			encounter.waiting[actor.get_instance_id()] = true
	if encounter.casters.is_empty():
		encounter.skill = Skill.NONE
		return false
	encounter.remaining = _interval(members[0])
	return true

## [param encounter] 的当前祈祷都达到关键帧后，分派局部判定或唯一的全场判定。
func _release_if_ready(encounter: Encounter) -> void:
	if encounter.ritual or encounter.skill == Skill.NONE or not encounter.waiting.is_empty():
		return
	var skill: Skill = encounter.skill # 出手前消费状态，处理同步死亡回调也不会重入。
	var casters: Array[Member] = encounter.casters.filter(_is_alive) # 每名存活者保留自己的局部判定。
	encounter.skill = Skill.NONE
	encounter.casters.clear()
	if casters.is_empty():
		return
	if skill in [Skill.VOID, Skill.PEACE] and not casters[0].has_prayer_target(skill):
		return # 抬掌前最后一个目标已消失时，取消全场结算和对应黑闪。
	if skill == Skill.VOID:
		var id: int = casters[0].boss_encounter_group_id() # 结算属于整组，抬掌者只在当前帧提供余像。
		_flash.play_void(id, casters[0].prayer_visual(), _resolve_void.bind(id))
	elif skill == Skill.PEACE:
		_flash.play_quick()
		casters[0].release_prayer(skill)
	else:
		for actor: Member in casters: # 先出招者的同步回调不能让已经阵亡的演员继续出手。
			if _is_alive(actor):
				actor.release_prayer(skill)

## 黑场抵达时重新查询 [param id] 的存活成员；整组已撤销时没有判定。
func _resolve_void(id: int) -> void:
	var encounter: Encounter = _encounters.get(id) # 余像的原始演员可能早已退场。
	if encounter == null:
		return
	for actor: Member in encounter.members: # 不把还有效的公共判定绑定到某个演员的生死。
		if _is_alive(actor):
			if actor.has_prayer_target(Skill.VOID):
				actor.release_prayer(Skill.VOID)
			return

## [param encounter] 中当前仍可保留战斗行动的一组演员。
func _living_members(encounter: Encounter) -> Array[Member]:
	return encounter.members.filter(_is_alive)

## [param actor] 同时通过存活与祈祷动作检查。
func _can_start(actor: Member) -> bool:
	return actor.can_start_prayer()

## [param actor] 死亡演出不算在场，也不能在此前登记的抬掌帧释放技能。
func _is_alive(actor: Member) -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_death and not actor.is_queued_for_deletion()

## [param actor] 的阶段由真实半血分裂和存活分身决定。
func _interval(actor: Member) -> float:
	return PRAYER_SECONDS.y if actor.boss_phase >= 2 else PRAYER_SECONDS.x
