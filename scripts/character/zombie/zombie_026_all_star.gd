extends "res://scripts/character/zombie/zombie_008_football.gd"
class_name Zombie026AllStar

enum ChargeState { CHARGING, SPENT }

const CHARGE_SPEED := 4.5
const SPENT_SPEED := 0.7
const TACKLE_DAMAGE := 1000000

@onready var _source_visual: AnimatedSprite2D = $Body/AllStarVisual
@onready var _tackle_sound: AudioStreamPlayer2D = $TackleSound

var charge_state: ChargeState = ChargeState.CHARGING


func _ready() -> void:
	super._ready()
	$AnimationPlayer.animation_started.connect(_on_native_visual_action)
	_source_visual.animation_finished.connect(_on_source_visual_finished)


func ready_norm_signal_connect() -> void:
	super.ready_norm_signal_connect()
	attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
	attack_component.detect_component.signal_can_attack.connect(_on_charge_contact)
	hp_component.signal_hp_component_death.connect(_on_charge_death)
	signal_character_be_hypno.connect(_retire_charge)
	move_component.update_move_mode(MoveComponent.E_MoveMode.Speed)
	_set_motion(CHARGE_SPEED, 3.0)


func _on_charge_contact() -> void:
	if charge_state != ChargeState.CHARGING or is_death or is_hypno:
		return
	var target: Character000Base = attack_component.detect_component.enemy_can_be_attacked
	if target is Plant000Base and not target.is_death:
		_retire_charge()
		_source_visual.play(&"tackle")
		_tackle_sound.play()
		(target as Plant000Base).be_zombie_eat(TACKLE_DAMAGE, self)
	elif attack_component.detect_component.brain != null or attack_component.detect_component.pot != null:
		_retire_charge()


func _retire_charge() -> void:
	if charge_state != ChargeState.CHARGING:
		return
	charge_state = ChargeState.SPENT
	_set_motion(SPENT_SPEED, 1.0)
	attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)


func _on_charge_death() -> void:
	_retire_charge()
	_source_visual.play(&"death")


func _on_source_visual_finished() -> void:
	if _source_visual.animation == &"tackle":
		_source_visual.play(&"eat" if is_attack else &"run")


func _on_native_visual_action(animation_name: StringName) -> void:
	if is_death:
		if _source_visual.animation != &"death":
			_source_visual.play(&"death")
		return
	if charge_state == ChargeState.CHARGING:
		return
	if _source_visual.animation == &"tackle" and _source_visual.is_playing():
		return
	var action := String(animation_name)
	if action.ends_with("_eat"):
		_source_visual.play(&"eat")
	elif action.ends_with("_idle"):
		_source_visual.play(&"idle")
	elif action.ends_with("_walk"):
		_source_visual.play(&"run")


func _set_motion(speed_multiplier: float, native_animation_speed: float) -> void:
	move_component.update_only_move_speed(speed_multiplier)
	_source_visual.speed_scale = 2.0 if charge_state == ChargeState.CHARGING else 1.0
	anim_component.set_animation_origin_speed(native_animation_speed)
	anim_component.owner_update_speed(GlobalUtils.get_dic_product(influence_speed_factors))
