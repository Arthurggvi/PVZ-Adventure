extends Node2D
class_name BossTeleportEffect
## Original Black General vortex SpriteFrames, with native particle smoke occlusion.
## The caller reuses BlackGeneral teleport animation's FX tracks and owns actor visibility.

@onready var smoke: CPUParticles2D = $SmokeCover
@onready var blink: AnimatedSprite2D = $TeleportBlink
@onready var ripple: AnimatedSprite2D = $TeleportRipple
var _dissolve: Tween

func _ready() -> void:
	smoke.amount = 146
	smoke.lifetime = .70
	smoke.one_shot = true
	smoke.explosiveness = .34
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	smoke.emission_rect_extents = Vector2(29, 58)
	smoke.direction = Vector2(0, -1)
	smoke.spread = 105.0
	smoke.initial_velocity_min = 7.0
	smoke.initial_velocity_max = 23.0
	smoke.gravity = Vector2(0, -3)
	smoke.scale_amount_min = .70
	smoke.scale_amount_max = 1.42
	smoke.local_coords = true
	smoke.preprocess = .06
	smoke.emitting = false
	visible = false

func begin(arrival: bool) -> void:
	if _dissolve and _dissolve.is_running():
		_dissolve.kill()
	visible = true
	blink.animation = &"arrive" if arrival else &"depart"
	ripple.animation = blink.animation
	blink.frame = 0
	ripple.frame = 0
	blink.visible = true
	ripple.visible = true
	smoke.modulate.a = 1.0
	smoke.restart()
	smoke.emitting = true

func finish() -> void:
	smoke.emitting = false
	blink.visible = false
	ripple.visible = false
	# Residual smoke dissipates after the actor has vanished.
	_dissolve = create_tween()
	_dissolve.tween_property(smoke, "modulate:a", 0.0, .23)
	_dissolve.tween_callback(func() -> void:
		visible = false
		smoke.modulate.a = 1.0
	)
