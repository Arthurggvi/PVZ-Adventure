extends "res://scripts/character/zombie/zombie_008_football.gd"
class_name Zombie026AllStar

## Art and keyframes: PvZ2 5.8.1 original ZOMBIE_MODERN_ALLSTAR.PAM (30fps).
## The black uniform is the requested palette adaptation of the original red art.
enum ChargeState { CHARGING, TACKLING, SPENT, DEAD }

const CHARGE_SPEED := 2.0
const SPENT_SPEED := 0.64
const TACKLE_DAMAGE := 1000000

@onready var _visual_animation: AnimationPlayer = $Body/AllStarVisual/AnimationPlayer
@onready var _tackle_sound: AudioStreamPlayer2D = $TackleSound
@onready var _entrance_whistle: AudioStreamPlayer = $EntranceWhistle

var charge_state: ChargeState = ChargeState.CHARGING
var _tackle_target: Plant000Base
var _tackle_hit_applied := false


func _ready() -> void:
	super._ready()
	_visual_animation.animation_finished.connect(_on_visual_animation_finished)
	if character_init_type == E_CharacterInitType.IsShow:
		_play_action(&"idle")


func ready_norm_signal_connect() -> void:
	super.ready_norm_signal_connect()
	# The entrance cue is played only for real battlefield spawns, not previews.
	if character_init_type == E_CharacterInitType.IsNorm:
		_entrance_whistle.play()
	attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
	attack_component.detect_component.signal_can_attack.connect(_on_charge_contact)
	attack_component.signal_change_is_attack.connect(_on_attack_state_changed)
	hp_component.signal_hp_component_death.connect(_on_death)
	signal_character_be_hypno.connect(_retire_charge)
	signal_update_speed.connect(_on_visual_speed_changed)
	move_component.update_move_mode(MoveComponent.E_MoveMode.Speed)
	_set_move_speed(CHARGE_SPEED)
	_play_action(&"run")


func _on_charge_contact() -> void:
	if charge_state != ChargeState.CHARGING or is_death or is_hypno:
		return
	var target: Character000Base = attack_component.detect_component.enemy_can_be_attacked
	if target is Plant000Base and not target.is_death:
		_tackle_target = target as Plant000Base
		_tackle_hit_applied = false
		charge_state = ChargeState.TACKLING
		_set_move_speed(0.0)
		_play_action(&"tackle")
	elif attack_component.detect_component.brain != null or attack_component.detect_component.pot != null:
		_retire_charge()


## Original frame 474 of 5.8.1 PAM: FSCmd "use_action" (relative tackle frame 5).
func _on_visual_tackle_hit() -> void:
	if charge_state != ChargeState.TACKLING or _tackle_hit_applied or is_death:
		return
	_tackle_hit_applied = true
	# Resume slow locomotion on PAM's original use_action frame (474).
	# The tackle recovery clip continues while the zombie advances slowly.
	_set_move_speed(SPENT_SPEED)
	if is_instance_valid(_tackle_target) and not _tackle_target.is_death:
		_tackle_target.be_zombie_eat(TACKLE_DAMAGE, self)


## Original frame 470: FSCmd "Play_Zomb_Modern_Allstar_Tackle".
func _on_original_tackle_sound() -> void:
	if charge_state == ChargeState.TACKLING:
		_tackle_sound.play()


func _on_visual_animation_finished(action: StringName) -> void:
	if charge_state == ChargeState.TACKLING and action == &"tackle":
		_retire_charge()


func _retire_charge() -> void:
	if charge_state == ChargeState.SPENT or charge_state == ChargeState.DEAD:
		return
	_tackle_target = null
	charge_state = ChargeState.SPENT
	_set_move_speed(SPENT_SPEED)
	attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)
	_sync_spent_action()


func _on_attack_state_changed(_attacking: bool) -> void:
	if charge_state == ChargeState.SPENT:
		_sync_spent_action()


func _sync_spent_action() -> void:
	var desired: StringName = &"eat" if is_attack else &"walk"
	if _visual_animation.current_animation != desired or not _visual_animation.is_playing():
		_play_action(desired)


func _on_death() -> void:
	_tackle_target = null
	charge_state = ChargeState.DEAD
	_set_move_speed(0.0)
	_play_action(&"die")


func _play_action(action: StringName) -> void:
	_visual_animation.speed_scale = GlobalUtils.get_dic_product(influence_speed_factors)
	_visual_animation.play(action)


func _on_visual_speed_changed(speed_product: float) -> void:
	_visual_animation.speed_scale = speed_product


func _set_move_speed(speed: float) -> void:
	move_component.update_only_move_speed(speed)
