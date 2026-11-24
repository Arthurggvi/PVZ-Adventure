## Applies the immutable zombie tier catalog to a freshly spawned battle instance.
## No stage configuration, saving, allocation, or UI side effects here.
extends ZombieSpawnModifier
class_name AdventureZombieTierBinding

var _tier_id: StringName

func _init(tier_id: StringName) -> void:
	_tier_id = tier_id

func for_child() -> ZombieSpawnModifier:
	return AdventureZombieTierBinding.new(_tier_id)

const Tiers = preload("res://scripts/adventure/adventure_zombie_tier_catalog.gd")

## 将已转为友军的 [param zombie] 提高一阶。按相同倍率提高生命和防具，保留已破防具及伤势比例。
static func promote_hypnotized(zombie: Zombie000Base) -> void:
	var ids: Array[StringName] = Tiers.tier_ids() # 空等阶按原版一阶计算。
	var index: int = maxi(0, ids.find(zombie.adventure_tier_id)) # 五阶仍保留原属性。
	if index >= ids.size() - 1:
		return
	var old: Dictionary = Tiers.get_tier(ids[index]) # 升阶只乘相邻两档之比。
	var next_id: StringName = ids[index + 1] # 克隆和原生派生共用更新后的出生配置。
	var next: Dictionary = Tiers.get_tier(next_id) # 生命、防具、攻击和标识来自同一目录。
	var body_factor: float = float(next.hp) / float(old.hp) # 保留本体损伤比例。
	var gear_factor: float = float(next.armor) / float(old.armor) # 防具可有独立成长。
	var health := zombie.hp_component as HpComponentZombie # 调整本体、各装备上限和当前血池。
	health.max_hp = Tiers.scaled(health.max_hp, body_factor)
	if health.scale_death_hp_on_promotion:
		health.death_hp = Tiers.scaled(health.death_hp, body_factor)
	health.combat_minimum_hp = Tiers.scaled(health.combat_minimum_hp, body_factor)
	health.curr_hp = maxi(health.death_hp + 1, Tiers.scaled(health.curr_hp, body_factor))
	health.max_hp_armor1 = Tiers.scaled(health.max_hp_armor1, gear_factor)
	health.max_hp_armor2 = Tiers.scaled(health.max_hp_armor2, gear_factor)
	if health.curr_hp_armor1 > 0:
		health.curr_hp_armor1 = Tiers.scaled(health.curr_hp_armor1, gear_factor)
	if health.curr_hp_armor2 > 0:
		health.curr_hp_armor2 = Tiers.scaled(health.curr_hp_armor2, gear_factor)
	zombie.hp_stage_change_component.scale_spawn_thresholds(body_factor, gear_factor)
	var attack := zombie.attack_component as AttackComponentZombieNorm # 原生等阶同样只提高普通啃食基数。
	if attack != null:
		attack.scale_base_attack(float(next.attack) / float(old.attack))
	zombie.adventure_tier_id = next_id
	zombie.combat_spawn_modifier = AdventureZombieTierBinding.new(next_id)
	zombie.modulate = next.tint # 实战重标等阶，保留本体正在使用的部件和破损姿势。

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
	# 只在冒险出生时接入实例级美术；没有配置时维持既有颜色标识。
	var game: MainGameManager = Global.main_game # 正式出生复用本战场的素材缓存，独立实例仍使用普通路径。
	var art_loaded: bool = game.zombie_manager.apply_spawn_appearance(zombie, id) \
		if is_instance_valid(game) and is_instance_valid(game.zombie_manager) else AdventureZombieTierArt.apply(zombie, id)
	zombie.adventure_tier_id = id
	zombie.modulate = Color.WHITE if art_loaded else tier.tint
	var rules: Array[Dictionary] = AdventureZombieTierTraits.for_spawn(int(zombie.zombie_type), id)
	if not rules.is_empty():
		var behavior := AdventureZombieTierBehavior.new()
		behavior.name = "AdventureTierBehavior"
		behavior.configure(rules)
		zombie.add_child(behavior)
	return true
