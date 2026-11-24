## 主动技能单次效果协议：只有 effect 实现战斗写入，运行时负责资格与冷却。
## 具体技能通过继承此资源实现，不允许持有玩家存档或永久运行态。
extends Resource
class_name CharacterSkillEffect

## [param context] 是施放瞬间冻结的战局上下文；返回本次是否允许结算。
## 不得修改战场，本方法可在 UI 状态查询或激活校验中被多次调用。
func can_execute(_context: CharacterSkillContext) -> bool:
	return false

## [param context] 为已校验的本局身份；只有真正提交效果时才返回 true 并启动冷却。
## 延时行为交给战场持有的临时节点或时间轴，不能在此处 await 后重新提交。
func execute(_context: CharacterSkillContext) -> bool:
	return false
