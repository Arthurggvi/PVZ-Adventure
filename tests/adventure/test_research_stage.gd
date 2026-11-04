## Single read-only scene validation: greenhouse art, animation and shared panel.
extends Node

const Stage = preload("res://scripts/adventure/ui/research_lab_stage.gd")

func _ready() -> void:
	call_deferred("_check")

func _check() -> void:
	var initial_coins: int = Global.global_game_state.coin_value
	var stage: AdventureResearchLabStage = Stage.new()
	get_tree().root.add_child(stage)
	await get_tree().create_timer(0.15).timeout
	var bg: Node2D = stage.get_node("GreenhouseBackgroundFX")
	var panel: AdventureResearchWindow = stage.get_node("ResearchPanel")
	assert(bg.get_child_count() == 17, "One base + 5 overlays + 11 dust motes")
	var room: Sprite2D = bg.get_node("room/Art")
	assert(room.texture.get_size() == Vector2(1920, 1080))
	assert(panel.with_background and panel.mode == "craft")
	var left_vine: Node2D = bg.get_node("vine_l")
	var before: float = left_vine.rotation
	await get_tree().create_timer(0.26).timeout
	assert(absf(left_vine.rotation - before) > 0.0001, "Independent vine animation runs")
	panel.choose_mode("upgrade")
	assert(panel.mode == "upgrade" and panel.ui.action.disabled)
	panel.choose_mode("promotion")
	assert(panel.mode == "promotion" and panel.ui.action.disabled)
	panel.choose_mode("craft")
	assert(Global.global_game_state.coin_value == initial_coins)
	stage.request_close()
	await get_tree().create_timer(0.27).timeout
	assert(not is_instance_valid(stage), "Stage and all FX should free on close")
	print("RESEARCH_LAB_STAGE_PASS background, animated layers, modes, close, no save edits")
	get_tree().quit(0)
