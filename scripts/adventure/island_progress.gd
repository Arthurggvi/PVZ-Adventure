## 僵尸岛地区进度视图。所有字段直接来自 AdventureState.regions，不拥有独立存档。
extends RefCounted

const REGION_ID := "zombie_island"

var _state: AdventureState

var started: bool:
	get:
		return _flag("started")

var intro_completed: bool:
	get:
		return _flag("intro_completed")

var stage_1_cleared: bool:
	get:
		return _flag("stage_1_cleared")

func _init(state: AdventureState) -> void:
	assert(state != null, "IslandProgress requires AdventureState")
	_state = state

func _flag(key: String) -> bool:
	var region: Dictionary = _state.regions.get(REGION_ID, {})
	return region.get(key, false) == true

func _set_flag(key: String) -> void:
	var region: Dictionary = _state.regions.get(REGION_ID, {}).duplicate(true)
	region[key] = true
	_state.regions[REGION_ID] = region

func start() -> void:
	_set_flag("started")

func complete_intro() -> bool:
	if not started:
		return false
	_set_flag("intro_completed")
	return true

func record_victory() -> bool:
	if not intro_completed:
		return false
	_set_flag("stage_1_cleared")
	return true
