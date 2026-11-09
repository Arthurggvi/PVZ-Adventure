extends Node
class_name AdventureZombieBungeeTier

const BLAST_PROFILE := preload("res://resources/combat/jackbox_explosion_profile.tres")
var _bungee: Zombie021Bungi
var _burst: AdventureZombieDeathBurst
var _blast_on_land := false

func setup(zombie: Zombie021Bungi, rule: Dictionary) -> void:
    _bungee = zombie
    zombie.linger_seconds = float(rule.get("linger", 2.0))
    zombie.hp_component.damage_block.set_source(get_instance_id(),
            int(rule.get("block", 0)))
    var on_steal := int(rule.get("steal_blast", 0))
    var on_land := int(rule.get("landing_blast", 0))
    if on_steal > 0 or on_land > 0:
        _burst = AdventureZombieDeathBurst.new()
        zombie.add_child(_burst)
        _burst.setup(zombie, maxi(on_steal, on_land), BLAST_PROFILE, false)
    if on_steal > 0:
        zombie.signal_plant_stolen.connect(_on_stolen)
    if on_land > 0:
        _blast_on_land = true
        zombie.signal_bungee_landed.connect(_on_landed)

func _on_stolen(_plant_cell: PlantCell) -> void:
    if is_instance_valid(_burst):
        _burst.trigger_once()

func _on_landed() -> void:
    if not _blast_on_land or not is_instance_valid(_bungee) or _bungee.is_death:
        return
    if is_instance_valid(_burst):
        _burst.trigger_once()
    _bungee.character_death_disappear()
