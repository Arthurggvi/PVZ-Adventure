## 验证睡莲在承托其他植物后仍可见，以及承托层复用既有空间偏移机制。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var cell: PlantCell = load("res://scenes/ui/plant_cell.tscn").instantiate()
	add_child(cell)
	cell.size = Vector2(78, 96)
	cell.plant_cell_type = PlantCell.PlantCellType.Pool
	cell.init_condition()
	var lily: Plant017LilyPad = load("res://scenes/character/plant/plant_017_lily_pad.tscn").instantiate()
	lily.character_init_type = Character000Base.E_CharacterInitType.IsShow
	cell.get_node("PlantDownContainer").add_child(lily)
	var upper: Plant000Base = load("res://scenes/character/plant/plant_006_snow_pea.tscn").instantiate()
	upper.character_init_type = Character000Base.E_CharacterInitType.IsShow
	var upper_container: Control = cell.get_node("PlantNormContainer")
	upper_container.add_child(upper)
	var original: Vector2 = upper_container.global_position
	cell.remove_child(upper_container)
	lily.down_plant_container.add_child(upper_container)
	upper_container.global_position = original - lily.plant_up_position
	await get_tree().process_frame
	var leaf: Sprite2D = lily.get_node("Body/BodyCorrect/Anim_idle")
	assert(leaf.is_visible_in_tree() and leaf.texture != null, "Lily pad leaf must remain visible")
	assert(upper_container.get_parent() == lily.down_plant_container, "Supported plant uses float container")
	assert(upper_container.global_position.y < lily.global_position.y - 10.0, "Upper plant must sit above pad")
	assert(cell.plant_cell_type == PlantCell.PlantCellType.Pool, "Water terrain must survive attachment")
	print("LILY_PAD_LAYOUT=PASS")
	get_tree().quit(0)
