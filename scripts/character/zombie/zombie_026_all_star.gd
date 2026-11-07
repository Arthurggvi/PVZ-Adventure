extends "res://scripts/character/zombie/zombie_008_football.gd"
class_name Zombie026AllStar

## The externally authored source timeline defines every visual clip.
## The tackle damage event is bound to the actual contact frame.
enum ChargeState { CHARGING, TACKLING, SPENT, DEAD }

const CHARGE_SPEED := 4.5
const SPENT_SPEED := 0.7
const TACKLE_DAMAGE := 1000000
const TACKLE_HIT_FRAME := 3

@onready var _visual: AnimatedSprite2D = $Body/AllStarVisual
@onready var _tackle_sound: AudioStreamPlayer2D = $TackleSound

var charge_state: ChargeState = ChargeState.CHARGING
var _tackle_target: Plant000Base
var _tackle_hit_applied := false


func _ready() -> void:
	super._ready()
	_visual.frame_changed.connect(_on_visual_frame_changed)
	_visual.animation_finished.connect(_on_visual_animation_finished)
	if character_init_type == E_CharacterInitType.IsShow:
		_visual.play(&"idle")


func ready_norm_signal_connect() -> void:
	super.ready_norm_signal_connect()
	attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
	attack_component.detect_component.signal_can_attack.connect(_on_charge_contact)
	attack_component.signal_change_is_attack.connect(_on_attack_state_changed)
	hp_component.signal_hp_component_death.connect(_on_death)
	signal_character_be_hypno.connect(_retire_charge)
	move_component.update_move_mode(MoveComponent.E_MoveMode.Speed)
	_set_move_speed(CHARGE_SPEED)
	_visual.play(&"run")


func _on_charge_contact() -> void:
	if charge_state != ChargeState.CHARGING or is_death or is_hypno:
		return
	var candidate: Character000Base = attack_component.detect_component.enemy_can_be_attacked
	if candidate is Plant000Base and not candidate.is_death:
		_tackle_target = candidate as Plant000Base
		_tackle_hit_applied = false
		charge_state = ChargeState.TACKLING
		_set_move_speed(0.0)
		_visual.play(&"tackle")
	elif attack_component.detect_component.brain != null or attack_component.detect_component.pot != null:
		_retire_charge()


func _on_visual_frame_changed() -> void:
	if charge_state != ChargeState.TACKLING or _visual.animation != &"tackle":
		return
	if _tackle_hit_applied or _visual.frame != TACKLE_HIT_FRAME:
		return
	_tackle_hit_applied = true
	_tackle_sound.play()
	if is_instance_valid(_tackle_target) and not _tackle_target.is_death:
		_tackle_target.be_zombie_eat(TACKLE_DAMAGE, self)


func _on_visual_animation_finished() -> void:
	if charge_state == ChargeState.TACKLING and _visual.animation == &"tackle":
		_retire_charge()


func _retire_charge() -> void:
	if charge_state == ChargeState.DEAD or charge_state == ChargeState.SPENT:
		return
	_tackle_target = null
	charge_state = ChargeState.SPENT
	_set_move_speed(SPENT_SPEED)
	attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)
	_sync_post_charge_visual()


func _on_attack_state_changed(_attacking: bool) -> void:
	if charge_state == ChargeState.SPENT:
		_sync_post_charge_visual()


func _sync_post_charge_visual() -> void:
	if charge_state != ChargeState.SPENT:
		return
	var desired: StringName = &"eat" if is_attack else &"walk"
	if _visual.animation != desired or not _visual.is_playing():
		_visual.play(desired)


func _on_death() -> void:
	_tackle_target = null
	charge_state = ChargeState.DEAD
	_set_move_speed(0.0)
	_visual.play(&"death")


func _set_move_speed(speed: float) -> void:
	move_component.update_only_move_speed(speed)
