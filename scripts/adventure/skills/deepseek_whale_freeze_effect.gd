## 大肥鱼的全场深寒，通过统一控制入口结算敌人的寒冷抗性。
extends CharacterSkillEffect

## 本次深寒的持续时间，单位为游戏秒。
const FREEZE_SECONDS: float = 5.0

## [param context] 必须仍属于可施放的战斗阶段。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active()

## 对 [param context] 当前战场的普通敌对僵尸施加深寒，至少命中一个目标才提交冷却。
func execute(context: CharacterSkillContext) -> bool:
	var applied: bool = false # 记录本次是否有敌人实际受到深寒控制。
	for zombie: Zombie000Base in context.hostile_targets(false): # 快照涵盖全场各行，Boss 和设施免疫。
		if CharacterSkillControlGateway.apply_deep_cold(context, zombie, FREEZE_SECONDS):
			applied = true
	return applied
