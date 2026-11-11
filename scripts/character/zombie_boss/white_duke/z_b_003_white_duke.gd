extends ZB000Base
class_name ZB003WhiteDuke
## Boss execution state machine. Animation and grave revival live in reused adapters.
enum State { ENTER, OPENING, IDLE, CAST, MOVING, PHASE_CAST, PHASE_OUT, PHASE_IN, DYING }
@export var config: WhiteDukeConfig = WhiteDukeConfig.new()
@onready var visual: WhiteDukeVisual = $Body/WhiteDukeVisual
var behavior := WhiteDukeBehaviorTree.new()
var skills := WhiteDukeSkillExecutor.new()
var state := State.ENTER
var _game: MainGameManager
var _graves: WhiteDukeGraveService
var _active_action: WhiteDukeBehaviorTree.Action = WhiteDukeBehaviorTree.Action.NONE
var _home_x := 0.0
var _move_target := Vector2.ZERO
var _next_lane := 0
var _released := false
var _speed := 1.0
func ready_norm() -> void:
	super.ready_norm()
	visual.player.animation_finished.connect(_on_animation_finished)
	signal_update_speed.connect(_on_speed_changed)
	_set_invulnerable(true)
	_begin_battle.call_deferred()
func ready_show() -> void:
	super.ready_show()
	visual.play_idle()
	set_physics_process(false)
func _begin_battle() -> void:
	var ancestor: Node = get_parent()
	while ancestor != null and not ancestor is MainGameManager:
		ancestor = ancestor.get_parent()
	_game = ancestor as MainGameManager
	if not _is_active() or _game.plant_cell_manager.all_plant_cells.is_empty():
		return
	lane = floori(_game.zombie_manager.all_zombie_rows.size()/2.0)
	var row: Array = _game.plant_cell_manager.all_plant_cells[lane]
	_home_x = (row[-1] as PlantCell).global_position.x + (row[-1] as PlantCell).size.x*1.25
	_return_home()
	_graves = WhiteDukeGraveService.new()
	_graves.name = "WhiteDukeGraveService"
	add_child(_graves)
	_graves.configure(self,_game,config)
	skills.configure(self,_game,config,_graves)
	state = State.ENTER
	visual.play_teleport_in()
func _is_active() -> bool:
	return is_instance_valid(_game) and _game.is_ancestor_of(self) \
		and _game.zombie_manager.is_game_running() \
		and not is_death and not is_queued_for_deletion()

func _physics_process(delta: float) -> void:
	if not _is_active() or _speed <= 0:
		return
	var elapsed := delta*_speed
	match state:
		State.IDLE:
			var action: WhiteDukeBehaviorTree.Action = behavior.tick(elapsed)
			if action != WhiteDukeBehaviorTree.Action.NONE:
				_begin_action(action)
		State.CAST, State.OPENING, State.PHASE_CAST:
			if not _released and visual.player.current_animation == &"point" \
					and visual.player.current_animation_position >= config.summon_release_at:
				_release_summon()
		State.MOVING:
			global_position = global_position.move_toward(_move_target,
				config.lane_change_speed*elapsed)
			if global_position.is_equal_approx(_move_target):
				lane = _next_lane
				z_index = lane*50+40
				signal_status_update.emit()
				skills.lane_change()
				_finish_action()

func _begin_action(action: WhiteDukeBehaviorTree.Action) -> void:
	_active_action = action
	_released = false
	if action == WhiteDukeBehaviorTree.Action.CHANGE_LANE:
		var n := _game.zombie_manager.all_zombie_rows.size()
		_next_lane = (lane+randi_range(1,maxi(1,n-1)))%n
		_move_target = Vector2(_home_x,_row_y(_next_lane))
		state = State.MOVING
		visual.player.play(&"walk")
	else:
		state = State.CAST
		visual.play_summon()

func _release_summon() -> void:
	if _released or not _is_active():
		return
	_released = true
	match state:
		State.OPENING:
			skills.opening()
		State.CAST:
			skills.perform(_active_action)
		State.PHASE_CAST:
			skills.phase_change()

func _finish_action() -> void:
	behavior.complete(_active_action,config.action_delay(boss_phase))
	_active_action = WhiteDukeBehaviorTree.Action.NONE
	state = State.IDLE
	visual.play_idle()

func _on_animation_finished(action: StringName) -> void:
	if state == State.DYING:
		if action == &"teleport_out":
			request_trophy()
			queue_free()
		return
	if not _is_active():
		return
	match state:
		State.ENTER:
			if action == &"teleport_in":
				state = State.OPENING
				_released = false
				visual.play_summon()
		State.OPENING:
			if action == &"point":
				_release_summon()
				_set_invulnerable(false)
				behavior.reset(config.action_delay(boss_phase))
				state = State.IDLE
				visual.play_idle()
		State.CAST:
			if action == &"point":
				_release_summon()
				_finish_action()
		State.PHASE_CAST:
			if action == &"point":
				_release_summon()
				state = State.PHASE_OUT
				visual.play_teleport_out()
		State.PHASE_OUT:
			if action == &"teleport_out":
				_return_home()
				state = State.PHASE_IN
				visual.play_teleport_in()
		State.PHASE_IN:
			if action == &"teleport_in":
				_set_invulnerable(false)
				behavior.reset(config.action_delay(boss_phase))
				state = State.IDLE
				visual.play_idle()

func _apply_boss_visual_phase(phase: int, animated: bool) -> void:
	if phase < 2 or not is_instance_valid(visual):
		return
	visual.set_phase2(true)
	if not animated or not _is_active() or not is_instance_valid(_graves):
		return
	_released = false
	_active_action = WhiteDukeBehaviorTree.Action.NONE
	_set_invulnerable(true)
	reset_control_effects()
	state = State.PHASE_CAST
	visual.player.stop()
	visual.play_summon()

func _row_y(row: int) -> float:
	return _game.zombie_manager.all_zombie_rows[row].zombie_create_position.global_position.y

func _return_home() -> void:
	global_position = Vector2(_home_x,_row_y(lane))
	z_index = lane*50+40
	signal_status_update.emit()

func _set_invulnerable(enabled: bool) -> void:
	hp_component.damage_immune = enabled
	hurt_box_component.change_is_enabling(not enabled,ComponentNormBase.E_IsEnableFactor.Character)
	signal_status_update.emit()

func _on_speed_changed(speed: float) -> void:
	_speed = maxf(0.0,speed)

func character_death() -> void:
	if is_death:
		return
	state = State.DYING
	if is_instance_valid(_graves):
		_graves.stop()
	super.character_death()
	visual.play_teleport_out()
	EventBus.push_event("canvas_layer_effect_once",[CanvasLayerEffect.E_CanvasLayerEffectType.Doom,.65])
	SoundManager.play_character_SFX(&"bossexplosion")
	SoundManager.play_boss_phase_roar()

func _exit_tree() -> void:
	if is_instance_valid(_graves):
		_graves.stop()

func play_summon_visual() -> void:
	visual.play_summon()

func play_teleport_arrive_visual() -> void:
	visual.play_teleport_in()

func play_teleport_depart_visual() -> void:
	visual.play_teleport_out()
