extends "res://scripts/character/zombie/zombie_008_football.gd"
class_name Zombie026AllStar

## One charge per life. Regular football health, armor, death and bite systems
## remain authoritative; only movement and the first plant impact differ.
enum ChargeState { CHARGING, SPENT }

const CHARGE_SPEED := 4.5
const SPENT_SPEED := 0.7
const TACKLE_DAMAGE := 1000000
const CHARGE_ANIMATION_SPEED := 3.0
const SPENT_ANIMATION_SPEED := 1.0

var charge_state: ChargeState = ChargeState.CHARGING

func _enter_tree() -> void:
	# Outfit, helmet damage frames and animation keys use the same art pipeline.
	AdventureZombieTierArt.apply_appearance(self, &"all_star")

func _ready() -> void:
	super._ready()
	# A football rank flag must never appear on this distinct species.
	$Body/BodyCorrect/Zombie_football_upperbody/AdventureTierFlag.visible = false

func ready_norm_signal_connect() -> void:
	super.ready_norm_signal_connect()
	attack_component.update_is_attack_factors(
		false, AttackComponentBase.E_IsAttackFactors.Character)
	attack_component.detect_component.signal_can_attack.connect(_on_contact)
	hp_component.signal_hp_component_death.connect(_retire_charge)
	signal_character_be_hypno.connect(_retire_charge)
	move_component.update_move_mode(MoveComponent.E_MoveMode.Speed)
	_set_motion(CHARGE_SPEED, CHARGE_ANIMATION_SPEED)

func _on_contact() -> void:
	if charge_state != ChargeState.CHARGING or is_death or is_hypno:
		return
	var target: Character000Base = attack_component.detect_component.enemy_can_be_attacked
	if target is Plant000Base and not target.is_death:
		_retire_charge()
		(target as Plant000Base).be_zombie_eat(TACKLE_DAMAGE, self)
	elif attack_component.detect_component.brain != null or attack_component.detect_component.pot != null:
		# Brain and vase levels still need the inherited normal attack.
		_retire_charge()

func _retire_charge() -> void:
	if charge_state != ChargeState.CHARGING:
		return
	charge_state = ChargeState.SPENT
	_set_motion(SPENT_SPEED, SPENT_ANIMATION_SPEED)
	attack_component.update_is_attack_factors(
		true, AttackComponentBase.E_IsAttackFactors.Character)

func _set_motion(speed_multiplier: float, animation_speed: float) -> void:
	# Speed mode respects existing slowing/freezing and move blockers.
	move_component.update_only_move_speed(speed_multiplier)
	anim_component.set_animation_origin_speed(animation_speed)
	anim_component.owner_update_speed(GlobalUtils.get_dic_product(influence_speed_factors))
