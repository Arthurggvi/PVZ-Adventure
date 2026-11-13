## 单一 AdventureState 内存中的僵尸岛进度，不再测试独立磁盘文件。
extends Node

const Progress = preload("res://scripts/adventure/island_progress.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := AdventureState.new()
	var progress := Progress.new(state)
	assert(not progress.started and not progress.intro_completed and not progress.stage_1_cleared)
	assert(not progress.record_victory())
	progress.start()
	assert(progress.started)
	assert(progress.complete_intro())
	assert(progress.record_victory())
	assert(state.regions.zombie_island.stage_1_cleared)
	var restored := AdventureState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert(restored != null)
	var resumed := Progress.new(restored)
	assert(resumed.started and resumed.intro_completed and resumed.stage_1_cleared)
	assert(not FileAccess.file_exists("user://phase1_tests/old_zombie_island.json"))
	print("PASS: in-memory island progress and AdventureState JSON")
	get_tree().quit(0)
