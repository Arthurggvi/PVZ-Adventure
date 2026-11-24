## 钟表匠为当前及十二秒内到场的敌方僵尸和僵王施加同一份行动时钟。
extends CharacterSkillEffect

## 每次施放持续的战斗秒数。
const SLOW_SECONDS := 12.0
## 施放立即生效的初始速度。
const START_RATE := 0.10
## 首个恢复控制点；前半程保持在接近初始行动速度。
const RECOVERY_FIRST_HANDLE := Vector2(0.60, 0.0)
## 第二个恢复控制点；最后阶段快速提升到正常行动速度。
const RECOVERY_SECOND_HANDLE := Vector2(0.88, 0.06)
## 本次施放的独立行动时钟，随装备技能惰性解析。
const Slowdown = preload("res://scripts/adventure/skills/battle_action_slowdown.gd")
## 跟随各目标的世界表盘。
const ClockDials = preload("res://scripts/adventure/skills/midnight_clockmaker_dials.gd")
## 位于战场合成层的镜片。
const Presentation = preload("res://scripts/adventure/skills/midnight_clockmaker_presentation.gd")

## [param context] 仍允许发动角色主动技能时返回 true。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active()

## 施放时捕获已有敌人，空场也可预先发动；后续出生由行动时钟接管。
func execute(context: CharacterSkillContext) -> bool:
	var source: RepeaterShotContext = context.state_source() # 战局、阶段和轮次统一失效。
	if source == null:
		return false
	var phase: AdventureBattleRuntime = context.game.adventure_runtime # 同时持有减速、滤镜和最后一声钟鸣。
	if not is_instance_valid(phase) or phase.is_queued_for_deletion():
		return false
	var targets: Array[Character000Base] = context.hostile_targets(true, false, false) # 包括僵王，行动效果允许暂时关闭受击框的角色进入。
	var slowdown := Slowdown.new(source, targets, SLOW_SECONDS, START_RATE,
		RECOVERY_FIRST_HANDLE, RECOVERY_SECOND_HANDLE) # 每次施放独立存储来源与恢复曲线。
	slowdown.add_child(ClockDials.new(slowdown))
	slowdown.add_child(Presentation.new(slowdown))
	phase.add_child(slowdown)
	return true
