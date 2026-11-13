## 中毒保留原公开入口与独立状态身份，时限和伤害由公共周期状态实现。
extends AdventurePeriodicDamageEffect
class_name AdventurePoisonEffect

## 同一目标的中毒节点名，与灼烧分别存在、分别刷新。
const NODE_NAME: StringName = &"AdventurePoisonEffect"

## 为 [param target] 授予 [param duration] 秒中毒；[param on_kill] 保留最新毒源的真实击杀回调。
## 返回是否接受请求；重施延长时长但不推迟下一跳。
static func apply_to(target: Character000Base, duration: float,
		on_kill: Callable = Callable()) -> bool:
	return AdventurePeriodicDamageEffect.grant(target, duration, on_kill, NODE_NAME, AdventurePoisonEffect)
