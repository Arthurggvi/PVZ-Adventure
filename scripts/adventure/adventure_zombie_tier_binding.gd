## Applies the immutable zombie tier catalog to a freshly spawned battle instance.
## No stage configuration, saving, allocation, or UI side effects here.
extends ZombieSpawnModifier
class_name AdventureZombieTierBinding

var _tier_id: StringName

func _init(tier_id: StringName) -> void:
	_tier_id = tier_id

const Tiers = preload("res://scripts/adventure/adventure_zombie_tier_catalog.gd")

## Called before add_child(). Component _ready derives HP bars from final max HP.
## Ordinary bite damage scales; special attacks (hammer, crush, etc.) stay intact.
func apply(zombie: Zombie000Base) -> bool:
	var id: StringName = _tier_id
	if zombie == null or zombie.is_inside_tree() or zombie.adventure_tier_id != &"":
		return false
	var tier: Dictionary = Tiers.get_tier(id)
	if tier.is_empty():
		return false
	var hp: HpComponentZombie = zombie.get_node_or_null("HpComponent") as HpComponentZombie
	if hp == null:
		return false
	var attack: AttackComponentZombieNorm = zombie.get_node_or_null("AttackComponent") as AttackComponentZombieNorm
	hp.max_hp = Tiers.scaled(hp.max_hp, float(tier.hp))
	hp.max_hp_armor1 = Tiers.scaled(hp.max_hp_armor1, float(tier.armor))
	hp.max_hp_armor2 = Tiers.scaled(hp.max_hp_armor2, float(tier.armor))
	var stages: HpStageChangeComponent = zombie.get_node_or_null(
		"HpStageChangeComponent") as HpStageChangeComponent
	if stages != null:
		stages.scale_spawn_thresholds(float(tier.hp), float(tier.armor))
	if attack != null:
		attack.init_attack_value_per_min = Tiers.scaled(
			attack.init_attack_value_per_min, float(tier.attack))
	zombie.adventure_tier_id = id
	zombie.modulate = tier.tint
	return true
