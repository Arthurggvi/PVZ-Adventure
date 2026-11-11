## 冒险豌豆转职的命中结算；子弹仍由原版投射物组件执行正常伤害。
extends RefCounted
class_name AdventurePeaProjectileEffects

## [param bullet] 已结算直接伤害的原版子弹；[param target] 直接目标。
## [param position] 命中位置；[param skills] 来自权威转职目录的效果参数。
static func impact(target: Character000Base, position: Vector2,
		bullet: Bullet000NormBase, skills: Dictionary) -> void:
	if target == null or not is_instance_valid(bullet):
		return
	if is_instance_valid(target) and target is Zombie000Base and not target.is_death:
		# 淬火允许击退带防具的僵尸；震撼不影响二类防具。
		var zombie: Zombie000Base = target as Zombie000Base
		var knockback: float = 0.0
		if bullet is Bullet006PeaFire and skills.has("pea_fire"):
			knockback = float(skills["pea_fire"].get("knockback", 0.0))
		if skills.has("pea_shock") and zombie.iron_type != Zombie000Base.IronType.IronArmor2:
			knockback = maxf(knockback, float(skills["pea_shock"].get("knockback", 0.0)))
		if knockback > 0.0:
			zombie.apply_projectile_knockback(knockback)
	if skills.has("pea_splash"):
		_splash(target, position, bullet.last_impact_damage, skills["pea_splash"])

## 仅在实际命中时遍历一次存活敌人；不按帧扫描、不伤害魅惑僵尸和直击目标。
static func _splash(direct: Character000Base, position: Vector2,
		hit_damage: int, rule: Dictionary) -> void:
	var game: MainGameManager = Global.main_game
	if not is_instance_valid(game) or not is_instance_valid(game.zombie_manager):
		return
	var radius: float = maxf(0.0, float(rule.get("radius", 0.0)))
	var damage: int = maxi(0, roundi(float(hit_damage) * float(rule.get("damage", 0.0))))
	if damage <= 0 or radius <= 0.0:
		return
	var manager: ZombieManager = game.zombie_manager
	for zombie: Zombie000Base in manager.all_zombies_1d:
		if zombie == direct or not is_instance_valid(zombie) or zombie.is_death \
				or zombie.is_queued_for_deletion() or zombie.is_hypno \
				or not is_instance_valid(zombie.hurt_box_component) \
				or not zombie.hurt_box_component.is_enabling:
			continue
		if zombie.hurt_box_component.global_position.distance_to(position) <= radius:
			zombie.be_attacked_bullet(damage, BulletRegistry.AttackMode.Norm, true, false)
	if not is_instance_valid(manager.zombie_boss_root):
		return
	for entry: Node in manager.zombie_boss_root.get_children():
		var boss: ZB000Base = entry as ZB000Base
		if not is_instance_valid(boss) or boss == direct or boss.is_death \
				or not is_instance_valid(boss.hurt_box_component) \
				or not boss.hurt_box_component.is_enabling:
			continue
		if boss.hurt_box_component.global_position.distance_to(position) <= radius:
			boss.be_attacked_bullet(damage, BulletRegistry.AttackMode.Norm, true, false)
