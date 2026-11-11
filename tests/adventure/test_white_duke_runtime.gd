extends Node
## Isolated native Boss assets, scheduler and phase config; full encounter smoke follows.
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/character/zombie_boss/zombie_boss_003_white_duke.tscn")
	assert(packed != null)
	var boss: ZB003WhiteDuke = packed.instantiate() as ZB003WhiteDuke
	assert(boss != null)
	boss.character_init_type = Character000Base.E_CharacterInitType.IsShow
	add_child(boss)
	await get_tree().process_frame
	assert(boss.hp_component.max_hp == 90000)
	assert(not boss.phase_two_threshold_inclusive)
	assert(boss.config.action_interval_phase1==5.0)
	assert(boss.config.action_interval_phase2==4.0)
	assert(boss.visual.player.has_animation(&"point"))
	assert(boss.visual.player.has_animation(&"teleport_in"))
	assert(boss.visual.player.has_animation(&"teleport_out"))
	var tree := WhiteDukeBehaviorTree.new()
	tree.reset(0)
	var actions: Array[int] = []
	for i in 8:
		var action: WhiteDukeBehaviorTree.Action = tree.tick(.1)
		actions.append(action)
		tree.complete(action,0)
	assert(actions==[1,5,2,5,3,5,4,5],str(actions))
	var black := BlackGeneralBehaviorTree.new()
	assert(black.tick(.1,false,false)==BlackGeneralBehaviorTree.Action.PLANT_FLAG)
	black.complete(BlackGeneralBehaviorTree.Action.PLANT_FLAG,0)
	assert(black.tick(.1,false,true)==BlackGeneralBehaviorTree.Action.CHANGE_LANE)
	print("WHITE_DUKE_RUNTIME_LOAD_AND_ALTERNATION_PASS",actions)
	get_tree().quit(0)
