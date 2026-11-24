## 用实际 Rig 定位僵尸抖雪源。所有路径相对于 Body，排除掉落件和独立演出。
extends RefCounted

## 与植物共用的天气记录，由正式出战登记器持有。
const ActorCover = preload("res://scripts/weather/snow/snow_actor_cover.gd")

## 按 [param zombie] 的实际 Rig 为 [param cover] 登记抖雪来源，只处理已核对的物种。
static func bind_shed_sources(zombie: Zombie000Base, cover: ActorCover) -> void:
	match zombie.zombie_type:
		CharacterRegistry.ZombieType.Z001Norm, CharacterRegistry.ZombieType.Z003Cone, CharacterRegistry.ZombieType.Z005Bucket:
			_add(zombie.body, cover, ^"BodyCorrect/Anim_head/Anim_head1")
			_add(zombie.body, cover, ^"BodyCorrect/Anim_hair/Anim_hair")
			_add(zombie.body, cover, ^"BodyCorrect/Zombie_outerarm_upper/Zombie_outerarm_upper")
			_add(zombie.body, cover, ^"BodyCorrect/leg/Zombie_innerleg_foot")
			_add(zombie.body, cover, ^"BodyCorrect/leg/Zombie_outerleg_foot")
			if zombie.zombie_type == CharacterRegistry.ZombieType.Z003Cone:
				_add(zombie.body, cover, ^"BodyCorrect/Anim_cone/Anim_cone")
			elif zombie.zombie_type == CharacterRegistry.ZombieType.Z005Bucket:
				_add(zombie.body, cover, ^"BodyCorrect/Anim_bucket/Anim_bucket")
				_add(zombie.body, cover, ^"BodyCorrect/IronNode/Anim_bucket")
		CharacterRegistry.ZombieType.Z004PoleVaulter:
			_add(zombie.body, cover, ^"BodyCorrect/Anim_head1")
			_add(zombie.body, cover, ^"BodyCorrect/Anim_hair")
			_add(zombie.body, cover, ^"BodyCorrect/Zombie_polevaulter_outerarm_upper")
			_add(zombie.body, cover, ^"BodyCorrect/Zombie_polevaulter_innerleg_foot")
			_add(zombie.body, cover, ^"BodyCorrect/Zombie_polevaulter_outerleg_foot")

## 将 [param body] 中位于 [param path] 的实际精灵交给 [param cover]；美术缺失时跳过。
static func _add(body: BodyCharacter, cover: ActorCover, path: NodePath) -> void:
	var sprite: Node2D = body.get_node_or_null(path) as Node2D # 只绑定明确属于身体绘制的精灵。
	if sprite is Sprite2D or sprite is AnimatedSprite2D:
		cover.add_shed_source(sprite)
