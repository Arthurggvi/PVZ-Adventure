## 双发火豆仍使用原版分摊溅射；红焰只向实际命中的附带目标追加一秒灼烧。
extends "res://scripts/bullet/component/spatter_component_fire_pea.gd"
class_name RepeaterFireSplash

## [param enemy] 是原生溅射已筛选的目标；[param damage_per_enemy] 是原规则分摊后的攻值。
func attack_enemy(enemy: Character000Base, damage_per_enemy: int) -> void:
	var bullet: Bullet000NormBase = get_parent() as Bullet000NormBase # 同一颗火豆负责来源门禁。
	if bullet == null or not bullet.is_attack_active():
		return
	super(enemy, damage_per_enemy)
	if StringName(bullet.get("kind")) == &"ember":
		RepeaterProjectileEffects.burn(enemy, bullet.get("shot") as RepeaterShotContext)
