## 在伤害路由扣本体前采集斯卡蒂冰雕，原僵尸仍走完整死亡与波次事务。
extends CombatHitScope
class_name SnowPeaStatueHit

## 只对本击有效的转职来源。
var _shot: SnowPeaShot

## 该根弹的接触序号，用于排除同击冷萃。
var _contact: int

## [param shot] 为根弹来源；[param contact] 识别其当前接触。
func _init(shot: SnowPeaShot, contact: int) -> void:
	_shot = shot
	_contact = contact

## [param hp] 为转伤和护甲分流后的实际承伤者；[param amount] 为即将扣除的本体伤害。
func before_body_loss(hp: HpComponentZombie, amount: int) -> void:
	if hp.curr_hp > hp.death_hp and hp.curr_hp - amount <= hp.death_hp \
			and hp.owner_character is Zombie000Base and _shot.battle.is_active():
		SnowPeaStatue.capture(hp.owner_character as Zombie000Base, _shot, _contact)
