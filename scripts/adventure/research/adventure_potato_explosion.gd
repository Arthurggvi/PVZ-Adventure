## 冒险土豆地雷共用的爆炸结算：原地引爆与土豆子弹落地统一命中、击杀和收益。
extends RefCounted
class_name AdventurePotatoExplosion

## 土豆子弹与母雷共用实际爆炸半径及状态过滤，不通过物理子弹直接扣血。
static func detonate(game: MainGameManager, position: Vector2, lane: int,
		parameters: Dictionary) -> int:
	if not is_instance_valid(game) or not is_instance_valid(game.plant_cell_manager):
		return 0
	var shape: Shape2D = parameters.get("shape") as Shape2D
	if shape == null:
		return 0
	var profile := CombatExplosionProfile.new()
	profile.shape = shape
	profile.hit_offset = parameters.get("offset", Vector2.ZERO)
	profile.collision_mask = 4
	profile.lane_radius = maxi(0, int(parameters.get("lane_radius", 0)))
	var areas: Array[Area2D] = CombatExplosion.query_areas(
		game.get_world_2d().direct_space_state, profile, position)
	var hit: Dictionary[int, bool] = {}
	var kills: Array[Vector2] = []
	var damage: int = maxi(0, int(parameters.get("damage", 0)))
	var allowed: int = int(parameters.get("statuses", 21))
	for area: Area2D in areas:
		if not is_instance_valid(area) or not is_instance_valid(area.owner):
			continue
		var target: Character000Base = area.owner as Character000Base
		if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
				or not target.is_inside_tree() or hit.has(target.get_instance_id()):
			continue
		if target is Zombie000Base:
			var zombie: Zombie000Base = target as Zombie000Base
			if zombie.is_hypno or (int(zombie.curr_be_attack_status) & allowed) == 0 \
					or absi(zombie.lane - lane) > profile.lane_radius:
				continue
			hit[zombie.get_instance_id()] = true
			var death_position: Vector2 = zombie.global_position
			zombie.be_bomb(damage, false)
			if zombie.is_death:
				kills.append(death_position)
		elif target is ZB000Base or target is EnemyStructureBase:
			if is_instance_valid(target.hurt_box_component) and target.hurt_box_component.is_enabling:
				hit[target.get_instance_id()] = true
				var death_position: Vector2 = target.global_position
				target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, false, false)
				if target is ZB000Base and target.is_death:
					kills.append(death_position)
	_award_kills(game, kills, parameters)
	return kills.size()

## 所有击杀收益基于本次爆炸中从存活变为死亡的目标，护甲破坏不算击杀。
static func _award_kills(game: MainGameManager, kills: Array[Vector2],
		parameters: Dictionary) -> void:
	if kills.is_empty():
		return
	var seconds: float = float(parameters.get("cooldown_per_kill", 0.0))
	if seconds > 0.0 and is_instance_valid(game.card_manager):
		var cards: CardSlotBattle = game.card_manager.card_slot_battle
		var uid: String = str(parameters.get("card_uid", ""))
		if is_instance_valid(cards):
			var card: Card = cards.find_plant_card_by_uid(uid) # 只返还来源卡的冷却。
			if card != null:
				card.adventure_adjust_remaining_cooldown(-seconds * kills.size())
	var sun_value: int = int(parameters.get("sun_per_kill", 0))
	if sun_value <= 0 or not is_instance_valid(game.suns):
		return
	for origin: Vector2 in kills:
		var sun: Sun = SceneRegistry.SUN.instantiate() as Sun
		if sun == null:
			return
		sun.init_sun(sun_value, game.suns.to_local(origin))
		game.suns.add_child(sun)
		var motion: Tween = sun.create_tween()
		motion.tween_property(sun, "position:y", -24.0, 0.23).as_relative().set_trans(Tween.TRANS_QUAD)
		motion.tween_property(sun, "position:y", 28.0, 0.37).as_relative().set_trans(Tween.TRANS_QUAD)
		sun.spawn_sun_tween = motion
		motion.finished.connect(sun.on_sun_tween_finished)
