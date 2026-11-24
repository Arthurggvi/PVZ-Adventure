## 救主祈祷的技能编号和参战成员契约。调度器与实体共用这一份定义。
extends RefCounted

## 五种随战斗推进的祈祷，NONE 表示没有待释放的动作。
enum Skill { NONE, VOID, MADNESS, PEACE, DESPAIR, GOSPEL }

## 原画返回真实抬掌帧，由实体提供，调度器无需了解场景节点路径。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")

## 参加同步祈祷的实体，沿用普通 Boss 的受击、阶段和死亡生命周期。
@abstract class Member extends ZB000Base:
	## 返回是否可与同组其他成员在这一帧起手。
	@abstract func can_start_prayer() -> bool

	## 返回战场当前是否满足 [param skill] 的目标条件。
	@abstract func has_prayer_target(skill: Skill) -> bool

	## 为 [param skill] 起手；[param claimed_cells] 在同一轮内分配互斥的目标。成功时返回 true。
	@abstract func start_prayer(skill: Skill, claimed_cells: Dictionary[PlantCell, bool]) -> bool

	## 在组内约定的判定帧提交 [param skill]。
	@abstract func release_prayer(skill: Skill) -> void

	## 返回成员的原画，供同步抬掌和采样已释放动作的余像。
	@abstract func prayer_visual() -> SaviorVisual
