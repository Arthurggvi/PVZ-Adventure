## 原逐帧僵尸的啃咬适配器；伤害沿用普通攻击，只补回原动画方法轨负责的咬合事件。
extends AttackComponentZombieNorm
class_name AttackComponentZombieImported

## 每次咬合声、植物受咬闪光和大蒜/魅惑菇反应的标准动作间隔。
const BITE_CUE_SECONDS: float = 0.65
## 距离下一次咬合事件已推进的动作秒数；离开目标立即清零。
var _bite_cue_elapsed: float = 0.0

## [param delta] 为物理时间；攻击伤害仍由父类原节奏和真实伤害入口处理。
func _physics_process(delta: float) -> void:
	var zombie: Zombie000Base = owner as Zombie000Base # 只消费既有行动与阵营状态。
	if not is_enabling or not is_attack_res or zombie.is_death or zombie.is_action_suspended():
		_bite_cue_elapsed = 0.0
		return
	_bite_cue_elapsed += delta * zombie.speed_factor_product()
	if _bite_cue_elapsed >= BITE_CUE_SECONDS:
		_bite_cue_elapsed = fmod(_bite_cue_elapsed, BITE_CUE_SECONDS)
		attack_once() # 复用原咬合事件，不能重新实现大蒜换行或魅惑。
	super(delta)
