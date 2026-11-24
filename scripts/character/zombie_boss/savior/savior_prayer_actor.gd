## 救主单个成员的祈祷生命周期：管理动作、受击锁和战斗时钟；同组抽签与出手顺序交给行动树。
extends "res://scripts/character/zombie_boss/savior/savior_prayer.gd".Member

## 救主自己的战场结算与特效衔接。
const Combat = preload("res://scripts/character/zombie_boss/savior/savior_combat.gd")
## 房间里与所有存活分身共用的行动接口。
const ActionTree = preload("res://scripts/character/zombie_boss/savior/savior_action_tree.gd")
## 原祈祷动作提供的施法关键帧。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")
## 绝望从原画抬手开始陨落，掌间墨滴不再抢先撞地。
const PrayerEffect = preload("res://scripts/fx/savior_prayer_effect.gd")

## 当前战斗及技能执行器，角色预览没有该实例。
var _combat: Combat
## 当前动作尚未回到站姿。
var _praying := false
## 入场和切镜期间拒绝新技能及来自战斗的伤害。
var _ritual_locked := false
## 原素材及双掌位置沿用已有的场景节点。
@onready var _visual: SaviorVisual = $Body/SaviorVisual

## 将正式战斗的 [param game] 和同场 [param arena] 接入本成员的技能及原画。角色预览不登记。
func _bind_prayer(game: MainGameManager, arena: SaviorBattle) -> void:
	_combat = Combat.new(self, game, arena)
	arena.savior_actions.register(self)
	_visual.prayer_released.connect(_on_prayer_released)
	_visual.prayer_finished.connect(_on_prayer_finished)
	signal_action_rate_changed.connect(_visual.set_action_rate)

## 开始仪式，撤销还没出手的旧动作。已经发射的技能仍沿用战斗时钟。
func begin_ritual() -> void:
	_ritual_locked = true
	_praying = false
	_combat.arena.savior_actions.suspend(self)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	_visual.cancel_prayer()
	_visual.set_action_rate(action_rate())
	signal_status_update.emit()

## 同组演员在合演后同帧归位，恢复各自的受击和共同的时钟。
func finish_ritual() -> void:
	if is_death or is_queued_for_deletion():
		return
	_ritual_locked = false
	if boss_phase >= 2:
		hp_component.combat_minimum_hp = 0
	hurt_box_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
	_combat.arena.savior_actions.resume(self)
	signal_status_update.emit()

## 用 [param delta] 推进在途陨石。仍由救主操控的扫掠沿用本人的行动倍率。
func _physics_process(delta: float) -> void:
	if _active():
		_combat.advance(delta, delta * action_rate())

## 返回本成员出手的原画；调用者在当前帧取样，余像不保留节点引用。
func prayer_visual() -> SaviorVisual:
	return _visual

## 请求同组共同执行 [param skill]。演出、其他祈祷或时停期间拒绝新的动作。
func perform_skill(skill: ActionTree.Skill) -> bool:
	return _combat != null and _combat.arena.savior_actions.request(self, skill)

## 整组确认可同时起手前读取当前战斗与原画状态。
func can_start_prayer() -> bool:
	return _active() and not _ritual_locked and not _praying and _visual.can_cast_prayer()

## [param skill] 的目标来自本局战场，整组在抽签和全场技能结算时共用此查询。
func has_prayer_target(skill: ActionTree.Skill) -> bool:
	return _combat != null and _combat.active() and _combat.has_target(skill)

## 开始 [param skill] 的原画，福音通过 [param claimed_cells] 与同轮其他分身分配不同格子。
func start_prayer(skill: ActionTree.Skill, claimed_cells: Dictionary[PlantCell, bool]) -> bool:
	if not can_start_prayer():
		return false
	var areas: Array[Rect2] = _combat.prepare(skill, claimed_cells) # 福音没有分到格子时，该成员不启动原画。
	if skill == ActionTree.Skill.GOSPEL and areas.is_empty():
		return false
	_visual.set_action_rate(action_rate())
	var profile: PrayerEffect.Profile = PrayerEffect.Profile.PALMS_ONLY if skill == ActionTree.Skill.DESPAIR else PrayerEffect.Profile.GROUND_MARKS # 保留各技能已有的祷告表现。
	if not _visual.cast_prayer(areas, profile):
		return false
	_praying = true
	return true

## [param skill] 已经过整组抬掌检查。释放局部命中，或由唯一的演员提交全场结算。
func release_prayer(skill: ActionTree.Skill) -> void:
	if _active():
		_combat.release(skill, _visual)

## 当前仍存活且本场允许战斗结算。
func _active() -> bool:
	return not is_death and is_inside_tree() and not is_queued_for_deletion() \
		and _combat != null and _combat.active() and not get_tree().paused

## 抬掌的真实原画帧通知共用行动树。
func _on_prayer_released() -> void:
	if _praying and _active():
		_combat.arena.savior_actions.prayer_reached(self)

## 祈祷完整收手后允许下一次行动。
func _on_prayer_finished() -> void:
	_praying = false
	_visual.set_action_rate(action_rate())

## 死亡立即中断待释放的祈祷，保留当前原画帧给退场传送。
func _end_prayer_on_death() -> void:
	_praying = false
	_visual.cancel_prayer(true)
