## 融合体只以减伤、护甲结算后的真实本体损血累计分裂，不改变原有死亡与波次回执。
extends HpComponentZombie
class_name HpComponentLargeFusion

## [param amount] 为即将扣除的有效本体生命；死亡通知前发出，监听者只能记账而不能再伤害自身。
signal body_health_lost(amount: int)

## [param amount] 已经过伤害路由；[param cause] 原样交给通用死亡判定。
## 先预留本击跨过的阈值，确保致死一击也会生成后代；过量伤害与护甲损失不计入。
func apply_body_loss(amount: int, cause: CombatHitScope.DeathCause = CombatHitScope.DeathCause.NORMAL) -> void:
	if not is_death and amount > 0:
		var actual_loss: int = mini(amount, maxi(0, curr_hp)) # 本次最多只能损失当前剩余生命。
		if actual_loss > 0:
			body_health_lost.emit(actual_loss)
	super.apply_body_loss(amount, cause)
