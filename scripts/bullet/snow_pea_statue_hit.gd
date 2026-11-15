## 寒冰命中在真实承伤者处记录受击前寒冷，并为合格根攻击登记斯卡蒂来源。
extends CombatHitScope
class_name SnowPeaStatueHit

## 本击的冻结转职来源，登记后可脱离弹体和母株继续存在。
var _shot: SnowPeaShot

## 该根弹的接触序号，用于排除同击冷萃。
var _contact: int
## 本次获准承伤者扣血前的寒冷快照，脆性不能读取原被保护者或本击刚施加的减速。
var was_slowed: bool = false

## [param shot] 为根弹来源；[param contact] 识别其当前接触。
func _init(shot: SnowPeaShot, contact: int) -> void:
	_shot = shot
	_contact = contact

## [param target] 为代伤路由确定的实际承伤者；在护甲、格挡及首次致死扣血前登记。
## 已消费的重复命中不续记来源；冰锥的接触序号为0，不会递归登记。
func try_claim(target: Character000Base) -> bool:
	if not super(target):
		return false
	if target is Zombie000Base:
		was_slowed = target.is_cold_slowed()
		SnowPeaStatueMark.register(target, _shot, _contact)
	return true
