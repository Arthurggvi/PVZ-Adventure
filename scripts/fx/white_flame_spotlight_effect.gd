extends Node2D
class_name WhiteFlameSpotlightEffect
## Reusable layered white flame aura + theatrical cone, only shown when active.
## White flame textures preserve original PvZ hand-drawn fire silhouettes.
## Movement uses the engine's CPUParticles2D and AnimatedSprite2D.
## No custom skeleton, manual frame playback, or duplicate character animation.

@onready var _back: CPUParticles2D = $FlamesBehind
@onready var _left: CPUParticles2D = $FlamesFrontLeft
@onready var _right: CPUParticles2D = $FlamesFrontRight
@onready var _wisps: CPUParticles2D = $WhiteFireWisps
@onready var _tips_left: CPUParticles2D = $FlameTipsLeft
@onready var _tips_right: CPUParticles2D = $FlameTipsRight
@onready var _mantle: AnimatedSprite2D = $WhiteFlameMantle

var _active := false

func _ready() -> void:
	_prepare_mantle()
	# Narrow, low-opacity tongues rather than a ring of stamped flame icons.
	_configure(_back, 15, Vector2(29, 44), 1.04, 10, 19, .23, .37, .58)
	_configure(_left, 9, Vector2(3, 42), .96, 11, 24, .45, .77, .42)
	_configure(_right, 9, Vector2(3, 44), .99, 12, 25, .44, .74, .40)
	_configure(_wisps, 17, Vector2(32, 52), 1.05, 15, 28, .56, .91, .37)
	_configure(_tips_left, 8, Vector2(4, 37), .87, 11, 20, .23, .39, .72)
	_configure(_tips_right, 8, Vector2(4, 37), .90, 11, 20, .23, .39, .70)
	set_active(false)

func _prepare_mantle() -> void:
	var sequence := SpriteFrames.new()
	sequence.remove_animation(&"default")
	sequence.add_animation(&"rise")
	sequence.set_animation_loop(&"rise", true)
	sequence.set_animation_speed(&"rise", 4.8)
	for i in 8:
		var filename := "res://assets/adventure/zombies/white_duke/fx/white_flame_mantle_%02d.png" % i
		sequence.add_frame(&"rise", load(filename))
	_mantle.sprite_frames = sequence

func _configure(
	emitter: CPUParticles2D,
	count: int,
	span: Vector2,
	life: float,
	speed_low: float,
	speed_high: float,
	scale_low: float,
	scale_high: float,
	alpha: float
) -> void:
	emitter.amount = count
	emitter.lifetime = life
	emitter.preprocess = life * .95
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emitter.emission_rect_extents = span
	emitter.direction = Vector2(0, -1)
	emitter.spread = 22
	emitter.initial_velocity_min = speed_low
	emitter.initial_velocity_max = speed_high
	emitter.gravity = Vector2(0, -2)
	emitter.scale_amount_min = scale_low
	emitter.scale_amount_max = scale_high
	emitter.angle_min = -12
	emitter.angle_max = 12
	emitter.local_coords = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(.16, Color(1, 1, 1, alpha))
	gradient.add_point(.63, Color(1, 1, 1, alpha * .79))
	gradient.add_point(.86, Color(1, 1, 1, alpha * .31))
	emitter.color_ramp = gradient

func set_active(enabled: bool) -> void:
	if _active == enabled:
		return
	_active = enabled
	visible = enabled
	_mantle.visible = enabled
	_back.emitting = enabled
	_left.emitting = enabled
	_right.emitting = enabled
	_wisps.emitting = enabled
	_tips_left.emitting = enabled
	_tips_right.emitting = enabled
	if enabled:
		_mantle.play(&"rise")
		_back.restart()
		_left.restart()
		_right.restart()
		_wisps.restart()
		_tips_left.restart()
		_tips_right.restart()
	else:
		_mantle.stop()

func is_active() -> bool:
	return _active
