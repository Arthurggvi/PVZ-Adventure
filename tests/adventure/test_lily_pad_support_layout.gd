## 验证正式植物事务的承托锚点：格子 Control 不离开布局树，只有 Node2D 内容随承托物移动。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _cell(kind: PlantCell.PlantCellType) -> PlantCell:
	var cell: PlantCell = load("res://scenes/ui/plant_cell.tscn").instantiate()
	add_child(cell)
	cell.size = Vector2(78, 96)
	cell.plant_cell_type = kind
	cell.init_condition()
	return cell

func _aligned(cell: PlantCell, support: Plant000DownBase) -> bool:
	for slot: CharacterRegistry.PlacePlantInCell in [
			CharacterRegistry.PlacePlantInCell.Norm,
			CharacterRegistry.PlacePlantInCell.Shell]:
		var content: Node2D = cell.plant_container_node[slot]
		var anchor: Control = cell.get_node(
			"PlantNormContainer" if slot == CharacterRegistry.PlacePlantInCell.Norm
			else "PlantShellContainer")
		if content.get_parent() != support.down_plant_container:
			return false
		if content.global_position.distance_to(
				anchor.global_position - support.plant_up_position) > 1.0:
			return false
	return true

func _run() -> void:
	var water: PlantCell = _cell(PlantCell.PlantCellType.Pool)
	var lily: Plant000DownBase = water.create_plant(
		CharacterRegistry.PlantType.P017LilyPad, false, false) as Plant000DownBase
	assert(lily != null)
	var melon: Plant000Base = water.create_plant(
		CharacterRegistry.PlantType.P040MelonPult, false, false)
	assert(melon != null)
	assert(_aligned(water, lily), "support content must be aligned with stable cell anchors")
	var leaf: Sprite2D = lily.get_node("Body/BodyCorrect/Anim_idle")
	assert(leaf.is_visible_in_tree() and leaf.texture != null)
	var norm_content: Node2D = water.plant_container_node[CharacterRegistry.PlacePlantInCell.Norm]
	assert(melon.get_parent() == norm_content)
	assert(water.get_node("PlantNormContainer").get_parent() == water)
	assert(water.get_node("PlantShellContainer").get_parent() == water)
	assert(water.get_new_plant_static_shadow_global_position(
		CharacterRegistry.PlacePlantInCell.Norm).distance_to(melon.global_position) < 0.1)

	# 缩放/重排格子不改变局部承托偏移。
	water.size = Vector2(94, 112)
	await get_tree().process_frame
	assert(_aligned(water, lily), "resizing must preserve supported placement")
	var previous: Vector2 = norm_content.global_position
	lily.position.y += 6.0
	assert(is_equal_approx(norm_content.global_position.y - previous.y, 6.0),
		"upper plant and shell must inherit support motion")
	lily.character_death_disappear()
	await get_tree().process_frame
	var norm_anchor: Control = water.get_node("PlantNormContainer")
	var shell_anchor: Control = water.get_node("PlantShellContainer")
	assert(norm_content.get_parent() == norm_anchor and norm_content.position == Vector2.ZERO)
	var shell: Node2D = water.plant_container_node[CharacterRegistry.PlacePlantInCell.Shell]
	assert(shell.get_parent() == shell_anchor and shell.position == Vector2.ZERO)
	assert(norm_content.global_position.distance_to(norm_anchor.global_position) < 0.1,
		"support removal restores slot to the current layout, not a cached world coordinate")
	assert(water.curr_condition == 9)
	melon.character_death_disappear()
	await get_tree().process_frame
	var lily_again: Plant000DownBase = water.create_plant(
		CharacterRegistry.PlantType.P017LilyPad, false, false) as Plant000DownBase
	assert(lily_again != null and _aligned(water, lily_again))

	# 同一布局实现也必须正确处理屋顶花盆。
	var roof: PlantCell = _cell(PlantCell.PlantCellType.Roof)
	var pot: Plant000DownBase = roof.create_plant(
		CharacterRegistry.PlantType.P034FlowerPot, false, false) as Plant000DownBase
	assert(pot != null and _aligned(roof, pot))
	pot.character_death_disappear()
	await get_tree().process_frame
	assert(roof.plant_container_node[CharacterRegistry.PlacePlantInCell.Norm].get_parent()
		== roof.get_node("PlantNormContainer"))
	print("LILY_PAD_LAYOUT=PASS")
	get_tree().quit(0)
