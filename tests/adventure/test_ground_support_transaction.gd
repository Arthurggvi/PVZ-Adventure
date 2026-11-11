## Cover the actual planting transaction: failed precommit cannot mutate terrain;
## successful placement/clear changes terrain only when Down-slot ownership changes.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _make_cell(kind: PlantCell.PlantCellType) -> PlantCell:
	var cell: PlantCell = load("res://scenes/ui/plant_cell.tscn").instantiate()
	add_child(cell)
	cell.plant_cell_type = kind
	cell.init_condition()
	return cell

func _run() -> void:
	var cell: PlantCell = _make_cell(PlantCell.PlantCellType.Pool)
	var lily_condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
		CharacterRegistry.PlantType.P017LilyPad,
		CharacterRegistry.PlantInfoAttribute.PlantConditionResource)
	assert(cell.curr_condition == 9 and lily_condition.judge_is_can_plant(
		cell, CharacterRegistry.PlantType.P017LilyPad))
	# The first placement validation and init_plant cannot change terrain.
	var precommit: Plant017LilyPad = load(
		"res://scenes/character/plant/plant_017_lily_pad.tscn").instantiate()
	precommit.init_plant({
		Plant000Base.E_PInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Plant000Base.E_PInitAttr.PlantCell: cell,
	})
	assert(cell.curr_condition == 9 and lily_condition.judge_is_can_plant(
		cell, CharacterRegistry.PlantType.P017LilyPad), "precommit must be side-effect-free")
	precommit.free()

	var created := [0]
	cell.signal_plant_create.connect(func(_cell: PlantCell, _species: CharacterRegistry.PlantType):
		created[0] += 1
	)
	var lily: Plant000Base = cell.create_plant(
		CharacterRegistry.PlantType.P017LilyPad, false, false)
	assert(is_instance_valid(lily), "player lily placement must succeed")
	assert(created[0] == 1, "successful placement creates exactly one entity")
	assert(cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Down] == lily)
	var leaf: Sprite2D = lily.get_node("Body/BodyCorrect/Anim_idle")
	assert(leaf.is_visible_in_tree() and leaf.texture != null, "committed lily must be visible")
	assert(cell.curr_condition == 17, "water + lily must become occupied lily terrain")
	assert(cell.create_plant(CharacterRegistry.PlantType.P017LilyPad, false, false) == null,
		"duplicate planting must be rejected")
	assert(created[0] == 1 and cell.curr_condition == 17,
		"rejected duplicate must not mutate the committed cell")
	assert(not lily_condition.judge_is_can_plant(cell, CharacterRegistry.PlantType.P017LilyPad))
	# On this terrain a normal plant can be placed over the lily.
	var pea_condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
		CharacterRegistry.PlantType.P001PeaShooterSingle,
		CharacterRegistry.PlantInfoAttribute.PlantConditionResource)
	assert(pea_condition.judge_is_can_plant(
		cell, CharacterRegistry.PlantType.P001PeaShooterSingle))
	lily.character_death_disappear()
	await get_tree().process_frame
	assert(cell.curr_condition == 9 and cell.plant_in_cell[
		CharacterRegistry.PlacePlantInCell.Down] == null,
		"support release must restore water even after deferred death")
	assert(not pea_condition.judge_is_can_plant(
		cell, CharacterRegistry.PlantType.P001PeaShooterSingle))
	var lily_again: Plant000Base = cell.create_plant(
		CharacterRegistry.PlantType.P017LilyPad, false, false)
	assert(is_instance_valid(lily_again) and created[0] == 2,
		"lily must be replantable after removal")
	assert(cell.curr_condition == 17)
	lily_again.character_death_disappear()
	await get_tree().process_frame
	assert(cell.curr_condition == 9)
	# No support precommit mutations or mistaken roof-pool conversion.
	var roof: PlantCell = _make_cell(PlantCell.PlantCellType.Roof)
	var pot: Plant000Base = roof.create_plant(
		CharacterRegistry.PlantType.P034FlowerPot, false, false)
	assert(is_instance_valid(pot) and roof.curr_condition == 4,
		"roof flowerpot must use same postcommit ownership contract")
	pot.character_death_disappear()
	await get_tree().process_frame
	assert(roof.curr_condition == 33, "roof base terrain must restore on pot removal")
	print("GROUND_SUPPORT_TRANSACTION=PASS")
	get_tree().quit(0)
