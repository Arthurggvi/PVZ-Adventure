## Menu-only wind envelope shared by canopy and falling-leaf emitters.
## State transitions are time-based; no timers, no global singleton.
extends Node

signal gust_started(power: float)

@export var calm_seconds := Vector2(1.8, 3.5)
@export var breeze_seconds := Vector2(3.5, 5.5)
@export var gust_seconds := Vector2(1.5, 2.6)
@export var strength_speed := 1.9

var strength := 0.0
var state := &"breeze"
var active := false
var wind_time := 0.0
var _remaining := 0.0
var _target := 0.0
var _random := RandomNumberGenerator.new()

func _ready() -> void:
    _random.randomize()
    set_active(true)

func set_active(enabled: bool) -> void:
    active = enabled
    set_process(enabled)
    if not enabled:
        strength = 0.0
        _target = 0.0
    elif _remaining <= 0.0:
        _enter(&"breeze")

func _process(delta: float) -> void:
    wind_time += delta
    _remaining -= delta
    if _remaining <= 0.0:
        match state:
            &"calm":
                _enter(&"breeze")
            &"breeze":
                _enter(&"gust" if _random.randf() < 0.75 else &"calm")
            &"gust":
                _enter(&"calm")
    strength = move_toward(strength, _target, strength_speed * delta)

func _enter(next_state: StringName) -> void:
    state = next_state
    match state:
        &"calm":
            _target = 0.23
            _remaining = _random.randf_range(calm_seconds.x, calm_seconds.y)
        &"gust":
            _target = _random.randf_range(1.2, 1.5)
            _remaining = _random.randf_range(gust_seconds.x, gust_seconds.y)
            gust_started.emit(_target)
        _:
            _target = _random.randf_range(0.78, 1.05)
            _remaining = _random.randf_range(breeze_seconds.x, breeze_seconds.y)
