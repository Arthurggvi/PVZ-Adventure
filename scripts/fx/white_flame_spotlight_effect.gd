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
@onready var _beam: Sprite2D = $SpotlightBeam
@onready var _pool: Sprite2D = $SpotlightFloor
@onready var _burst: Sprite2D = $SpotlightBurst
## 二阶段换色时从落光中心向外扩散的加色泛光。
@onready var _pulse: Sprite2D = $SpotlightPulse

## 泛光从透明升至峰值的时间，单位为秒。
const PULSE_ATTACK_TIME := 0.10
## 泛光从峰值扩散至完全消失的时间，单位为秒。
const PULSE_DECAY_TIME := 0.54

const SUMMON_COLORS: Array[Color] = [
	Color(0.57, 0.77, 1.00), Color(1.00, 0.54, 0.86),
	Color(0.53, 1.00, 0.86), Color(1.00, 0.84, 0.46),
	Color(0.78, 0.68, 1.00)
]
var _cue: Tween
var _last_hue := -1

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
	if _cue and _cue.is_running():
		_cue.kill()
	_end_spotlight_cue()
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

## 播放召唤聚光灯并返回本次光色。[br]
## [param phase_two] 为真时切换到与上次不同的颜色，同时触发一次心跳式泛光。
func summon_spotlight(phase_two: bool) -> Color:
	if _cue and _cue.is_running():
		_cue.kill()
	var shade := Color.WHITE
	if phase_two:
		var selection := randi_range(0, SUMMON_COLORS.size()-1 if _last_hue < 0 else SUMMON_COLORS.size()-2)
		if _last_hue >= 0 and selection >= _last_hue:
			selection += 1
		_last_hue = selection
		shade = SUMMON_COLORS[selection]
	visible = true
	_beam.visible = true
	_pool.visible = true
	_burst.visible = true
	_pulse.visible = phase_two
	_beam.modulate = Color(shade.r, shade.g, shade.b, 1.0 if phase_two else .0)
	_pool.modulate = Color(shade.r, shade.g, shade.b, 1)
	_burst.modulate = Color(shade.r, shade.g, shade.b, .67 if phase_two else .32)
	_burst.scale = _beam.scale * Vector2(1.08, 1.04)
	_cue = create_tween()
	_cue.set_parallel(true)
	_cue.tween_property(_burst, "modulate:a", 0.0, .62)
	if phase_two:
		_cue.tween_property(_beam, "modulate", Color.WHITE, 1.20)
		_cue.tween_property(_pool, "modulate", Color.WHITE, 1.20)
		_cue.tween_property(_burst, "scale", _beam.scale * Vector2(1.25, 1.06), .62)
		# 光斑先快速亮起，随即向四周铺开并衰减。
		_pulse.scale = _pool.scale * .72
		_pulse.modulate = Color(shade.r, shade.g, shade.b, 0.0)
		_cue.tween_property(_pulse, "modulate:a", .92, PULSE_ATTACK_TIME)
		_cue.tween_property(_pulse, "modulate:a", 0.0, PULSE_DECAY_TIME).set_delay(PULSE_ATTACK_TIME)
		_cue.tween_property(
			_pulse, "scale", _pool.scale * Vector2(2.2, 1.85), PULSE_ATTACK_TIME + PULSE_DECAY_TIME
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_cue.tween_property(_beam, "modulate:a", 1.0, .12)
		_cue.tween_property(_beam, "modulate:a", 0.0, .32).set_delay(.90)
		_cue.tween_property(_pool, "modulate:a", 0.0, .32).set_delay(.90)
	_cue.chain().tween_callback(_end_spotlight_cue)
	return shade

## 清除召唤泛光，并按当前阶段恢复常驻白光或隐藏聚光灯。
func _end_spotlight_cue() -> void:
	_burst.visible = false
	_pulse.visible = false
	_beam.modulate = Color.WHITE
	_pool.modulate = Color.WHITE
	_beam.visible = _active
	_pool.visible = _active
	visible = _active

## Cancel a summon pulse before a teleport interruption, preserving phase gating.
func suspend_for_teleport() -> void:
	if _cue and _cue.is_running():
		_cue.kill()
	_end_spotlight_cue()
