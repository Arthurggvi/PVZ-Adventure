extends "res://scripts/character/zombie/zombie_008_football.gd"
class_name Zombie026AllStar

## Authored 12 FPS Reanim keys, continuously interpolated by Godot AnimationPlayer.
## Source parts are external and independent from the inherited (hidden) vanilla visuals.
enum ChargeState { CHARGING, TACKLING, SPENT, DEAD }

## PvZ2 All-Star reference: ~0.5 tile/s charge, ~0.16 tile/s afterward.
## Existing grass board tiles are ~80px and MoveComponent.ori_speed = 20px/s.
## See assets/adventure/zombies/all_star/ART_SOURCE.txt for source and caveats.
const CHARGE_SPEED := 2.0 # 40px/s / 20px/s
const SPENT_SPEED := 0.64 # 12.8px/s / 20px/s
const TACKLE_DAMAGE := 1000000

@onready var _visual_animation: AnimationPlayer = $Body/AllStarVisual/AnimationPlayer
@onready var _tackle_sound: AudioStreamPlayer2D = $TackleSound

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
	var candidate: Character000Base = attack_component.detect_component.enemy_can_be_attacked
	if candidate is Plant000Base and not candidate.is_death:
		_tackle_target = candidate as Plant000Base
		_tackle_hit_applied = false
		charge_state = ChargeState.TACKLING
		_set_move_speed(0.0)
		_play_action(&"tackle")
	elif attack_component.detect_component.brain != null or attack_component.detect_component.pot != null:
		_retire_charge()


## Called by the contact-time method key in the actual external source animation.
func _on_visual_tackle_hit() -> void:
	if charge_state != ChargeState.TACKLING or _tackle_hit_applied or is_death:
		return
	_tackle_hit_applied = true
	_tackle_sound.play()
	if is_instance_valid(_tackle_target) and not _tackle_target.is_death:
		_tackle_target.be_zombie_eat(TACKLE_DAMAGE, self)


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
	_play_action(&"death")


func _play_action(action: StringName) -> void:
	_visual_animation.speed_scale = _visual_speed_multiplier() * GlobalUtils.get_dic_product(influence_speed_factors)
	_visual_animation.play(action)


func _visual_speed_multiplier() -> float:
	return 2.0 if charge_state == ChargeState.CHARGING else 1.0


func _on_visual_speed_changed(speed_product: float) -> void:
	_visual_animation.speed_scale = _visual_speed_multiplier() * speed_product


func _set_move_speed(speed: float) -> void:
	move_component.update_only_move_speed(speed)
