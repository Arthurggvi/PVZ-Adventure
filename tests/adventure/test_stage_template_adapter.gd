## 独立 P1 模板边界测试，不读取当前玩家或写任何存档。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var original: ResourceLevelData = load("res://resources/adventure/island_lawn.tres")
	assert(original != null)
	assert(AdventureLevelTemplateAdapter.validate(original).is_empty())
	var source_wave: int = original.max_wave
	var runtime: ResourceLevelData = AdventureLevelTemplateAdapter.build(original, 8)
	assert(runtime != null and runtime != original)
	assert(runtime.look_show_zombie and runtime.can_choosed_card)
	assert(runtime.max_choosed_card_num == 8)
	assert(original.max_wave == source_wave and original.max_choosed_card_num == 2)
	runtime.max_wave = 30
	assert(original.max_wave == source_wave)
	var special: ResourceLevelData = original.duplicate(true)
	special.card_mode = ConstLevelData.E_CardMode.ConveyorBelt
	assert(not AdventureLevelTemplateAdapter.validate(special).is_empty())
	assert(AdventureLevelTemplateAdapter.build(special, 8) == null)
	var boss: ResourceLevelData = original.duplicate(true)
	boss.win_on_boss_death = true
	assert(not AdventureLevelTemplateAdapter.validate(boss).is_empty())
	assert(AdventureLevelTemplateAdapter.build(boss, 8) == null)
	assert(AdventureLevelTemplateAdapter.build(original, 16) == null)
	assert(AdventureLevelTemplateAdapter.build(null, 8) == null)
	print("PASS: stage template validation, mandatory draft, isolated runtime copy")
	get_tree().quit(0)
