## Animated greenhouse, independent of research UI and gameplay rules.
## Layer positions and pivots are on the 1920x1080 art canvas.
extends Node2D

const ROOT := "res://assets/adventure/research_lab_bg/"
const CANVAS_SIZE := Vector2(1920, 1080)
var fx_enabled := true
var _elapsed := 0.0
var _layers: Dictionary = {}

func _ready() -> void:
	_add("room", "research_bg_base.png", Vector2.ZERO, 0)
	_add("window", "research_window_leaf_shadow.png",
		Vector2(620, 180), 1, Vector2(100, 0))
	_add("cone", "research_lamp_lightcone.png",
		Vector2(650, 215), 2, Vector2(310, 0))
	_add("glow", "research_lamp_glow.png",
		Vector2(700, 75), 3, Vector2(250, 140))
	_add("vine_l", "research_vine_left.png",
		Vector2(155, 5), 4, Vector2(60, 0))
	_add("vine_r", "research_vine_right.png",
		Vector2(1360, 0), 4, Vector2(270, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5184
	for i in 11:
		var mote := _add("dust_%d" % i, "research_dust_mote.png",
			Vector2(520 + i * 85, 230 + (i * 59) % 370), 6)
		mote.set_meta("phase", rng.randf_range(0, TAU))

func _add(id: String, file: String, origin: Vector2, depth: int,
		pivot: Vector2 = Vector2.ZERO) -> Node2D:
	var anchor := Node2D.new()
	anchor.name = id
	anchor.position = origin + pivot
	anchor.z_index = depth
	add_child(anchor)
	var sprite := Sprite2D.new()
	sprite.name = "Art"
	sprite.centered = false
	sprite.position = -pivot
	sprite.texture = load(ROOT + file)
	anchor.add_child(sprite)
	_layers[id] = anchor
	return anchor

func _process(delta: float) -> void:
	if not fx_enabled:
		return
	_elapsed += delta
	(_layers["window"] as Node2D).position.x = 720.0 + 7.0 * sin(_elapsed * TAU / 7.5)
	(_layers["cone"] as Node2D).modulate.a = 0.65 + 0.20 * sin(_elapsed * TAU / 4.8)
	(_layers["glow"] as Node2D).modulate.a = 0.80 + 0.20 * sin(_elapsed * TAU / 3.8)
	(_layers["vine_l"] as Node2D).rotation_degrees = 2.2 * sin(_elapsed * TAU / 5.4)
	(_layers["vine_r"] as Node2D).rotation_degrees = 1.8 * sin(_elapsed * TAU / 6.3 + 1.0)
	for i in 11:
		var mote: Node2D = _layers["dust_%d" % i]
		var shifted := _elapsed + i * 1.7
		mote.position.x = 520.0 + i * 85.0 + 12.0 * sin(_elapsed * 0.7 + i)
		mote.position.y = 230.0 + float((i * 59) % 370) - fmod(shifted * 10.0, 80.0)
		mote.modulate.a = 0.25 + 0.17 * sin(shifted * 1.5)

func set_fx_enabled(active: bool) -> void:
	fx_enabled = active
	set_process(active)
	for id: String in _layers:
		(_layers[id] as Node2D).visible = active or id == "room"
