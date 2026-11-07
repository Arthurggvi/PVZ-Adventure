extends Node

## Scene-mode smoke so project Autoloads and the real CharacterRegistry are active.
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/character/zombie/zombie_026_all_star.tscn")
	assert(scene != null, "All-Star packed scene must load")
	var zombie: Zombie026AllStar = scene.instantiate() as Zombie026AllStar
	assert(zombie != null and zombie.zombie_type == CharacterRegistry.ZombieType.Z026AllStar)
	zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
	add_child(zombie)
	await get_tree().process_frame
	var torso: Sprite2D = zombie.get_node("Body/BodyCorrect/Zombie_football_upperbody")
	var flag: Sprite2D = zombie.get_node("Body/BodyCorrect/Zombie_football_upperbody/AdventureTierFlag")
	assert(torso.texture.resource_path.contains("/football/tier3/"),
		"All-Star must load the authored black suit on all body layers")
	assert(not flag.visible, "All-Star must not inherit football rank flags")
	zombie._retire_charge()
	assert(zombie.charge_state == Zombie026AllStar.ChargeState.SPENT)
	assert(is_equal_approx(zombie.move_component.curr_speed_move,
		Zombie026AllStar.SPENT_SPEED))
	assert(CharacterRegistry.ZombieSpawnPower[CharacterRegistry.ZombieType.Z026AllStar] == 12)
	print("ALL_STAR_SCENE_OK")
	get_tree().quit()
