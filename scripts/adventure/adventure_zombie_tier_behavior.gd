## Bridges configured species traits to existing zombie lifecycle signals.
## This node is attached before the zombie enters the scene tree.
extends Node
class_name AdventureZombieTierBehavior

var _zombie: Zombie000Base
var _rules: Array[Dictionary] = []
var _armor1_consumed := false

func configure(rules: Array[Dictionary]) -> void:
	_rules = rules

func _ready() -> void:
	_zombie = get_parent() as Zombie000Base
	if _zombie == null or _rules.is_empty() or _zombie.adventure_tier_id == &"":
		return
	var listen_for_armor1 := false
	for rule: Dictionary in _rules:
		match StringName(rule.get("trigger", &"")):
			&"armor1_lost":
				listen_for_armor1 = true
			_:
				push_error("Unknown zombie tier trigger: %s" % rule.get("trigger"))
	if listen_for_armor1:
		var hp: HpComponentZombie = _zombie.get_node_or_null("HpComponent") as HpComponentZombie
		if hp != null and hp.max_hp_armor1 > 0:
			hp.signal_armor1_death.connect(_on_armor1_lost)
		else:
			push_error("Armor-loss trait requires armor1 on its zombie")

func _on_armor1_lost() -> void:
	if _armor1_consumed:
		return
	_armor1_consumed = true
	# Armor and body may die from the same hit; resolve after damage settlement.
	call_deferred("_resolve_trigger", &"armor1_lost")

func _resolve_trigger(trigger: StringName) -> void:
	if not is_instance_valid(_zombie) or _zombie.is_death 			or _zombie.is_hypno or _zombie.is_queued_for_deletion():
		return
	for rule: Dictionary in _rules:
		if rule.get("trigger") != trigger:
			continue
		match StringName(rule.get("effect", &"")):
			&"timed_speed_boost":
				_apply_speed_boost(rule)
			_:
				push_error("Unknown zombie tier effect: %s" % rule.get("effect"))

func _apply_speed_boost(rule: Dictionary) -> void:
	var multiplier: float = float(rule.get("multiplier", 1.0))
	var duration: float = float(rule.get("duration", 0.0))
	AdventureZombieTimedSpeedBoost.apply_to(_zombie, multiplier, duration)
	var radius_cells: int = int(rule.get("radius_cells", 0))
	if radius_cells <= 0:
		return
	var game = Global.main_game
	if not is_instance_valid(game) or not is_instance_valid(game.zombie_manager) 			or not is_instance_valid(game.plant_cell_manager):
		return
	var grid: Array[Array] = game.plant_cell_manager.all_plant_cells
	if grid.is_empty() or _zombie.lane < 0 or _zombie.lane >= grid.size():
		return
	var row: Array = grid[_zombie.lane]
	if row.is_empty() or not is_instance_valid(row[0]):
		return
	var cell_width: float = (row[0] as PlantCell).size.x
	for ally: Zombie000Base in AdventureZombieTierNeighbors.allied_in_range(
			_zombie, game.zombie_manager.all_zombies_1d, cell_width, radius_cells):
		AdventureZombieTimedSpeedBoost.apply_to(ally, multiplier, duration)
