## 技能效果到现有特殊控制系统的适配点，不创建平行冻结或负面状态引擎。
extends RefCounted
class_name CharacterSkillControlGateway

## [param context] 是本次战局；[param target] 必须是允许寒冷的普通敌人。
## [param freeze_seconds] 和 [param followup_seconds] 均为非负游戏秒。
## 复用 AdventureDeepCold，气球/持杆跳跳遵守原有“只能减速”规则；Boss/设施不绕过免疫。
## 仅施加控制，不隐式造成寒冰菇 20 点伤害、珊瑚抑制或波次暂停。
static func apply_deep_cold(context: CharacterSkillContext, target: Zombie000Base,
		freeze_seconds: float, followup_seconds: float = 0.0) -> bool:
	if not is_finite(freeze_seconds) or freeze_seconds <= 0.0 \
			or not is_finite(followup_seconds) or followup_seconds < 0.0 \
			or not CharacterSkillTargetQuery.can_receive_cold(context, target, false):
		return false
	var source: RepeaterShotContext = context.state_source() # 状态本身持有阶段身份，旧阶段自动失效。
	if source == null:
		return false
	return AdventureDeepCold.apply_to(target, source, freeze_seconds + followup_seconds,
		freeze_seconds, AdventureIceShroomCast.ALL_ZOMBIE_STATUSES)
