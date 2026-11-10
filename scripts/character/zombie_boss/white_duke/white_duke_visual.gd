extends Node2D
class_name WhiteDukeVisual
## Visual adapter: the 21 native Jackson Sprite2D nodes and six original .tres animations
## live in white_duke_visual.tscn. No parallel skeleton or keyframe authoring.
const ART := "res://assets/adventure/zombies/white_duke/"
const ACCESSORY := ART + "accessories/"
@onready var player: AnimationPlayer = $AnimationPlayer
@onready var _parts: Node2D = $Body/BodyCorrect
var _records: Dictionary = {}
var _coat: Dictionary = {}
var _hand_tracks: Array[Dictionary] = []
var _hand_cache: Dictionary = {}
var _hat: Sprite2D
var _glasses: Sprite2D

func _ready() -> void:
	var file := FileAccess.open(ART + "coat_binding.json", FileAccess.READ)
	assert(file != null, "Missing White Duke coat bindings")
	var config: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	for entry: Dictionary in config["phase_slots"]:
		var key := String(entry["name"])
		if not _records.has(key):
			_records[key] = {}
		_records[key][int(entry["phase"])] = entry
	_install_coat()
	_install_accessories()
	_prepare_animations()
	set_phase2(false)
	play_idle()

func _install_coat() -> void:
	var torso: Sprite2D = _parts.get_node("Zombie_Jackson_body1")
	var basis := torso.global_transform * Transform2D(0.0, Vector2(-7, 8))
	for key: String in _records:
		var rec: Dictionary = _records[key][1]
		var anchor: Sprite2D = _parts.get_node(String(rec["anchor"]))
		var sprite := Sprite2D.new()
		sprite.name = "WhiteDuke_" + key
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.texture = load(String(rec["resource"]))
		sprite.z_as_relative = false
		sprite.z_index = int(rec["z"])
		anchor.add_child(sprite)
		var point: Array = rec["origin"]
		var offset := Transform2D(0.0, Vector2(float(point[0]), float(point[1])))
		offset = offset.scaled_local(Vector2.ONE * float(rec["scale"]))
		sprite.transform = anchor.global_transform.affine_inverse() * basis * offset
		_coat[key] = sprite

func _install_accessories() -> void:
	_glasses = Sprite2D.new()
	_glasses.name = "WhiteDuke_Glasses"
	_glasses.centered = false
	_glasses.position = Vector2(-4, 21)
	_glasses.scale = Vector2.ONE * 0.44
	_glasses.z_index = 2
	_parts.get_node("Anim_head1").add_child(_glasses)
	var tex: Texture2D = load(ACCESSORY + "fedora_white.png")
	_hat = Sprite2D.new()
	_hat.name = "WhiteDuke_Fedora"
	_hat.texture = tex
	_hat.centered = true
	_hat.position = Vector2(-8, -11) + Vector2(tex.get_size()) * 0.29
	_hat.scale = Vector2.ONE * 0.58
	_hat.rotation_degrees = -15.0
	_hat.z_index = 2
	_parts.get_node("Anim_hair").add_child(_hat)

func _prepare_animations() -> void:
	# Clone the original AnimationLibrary once, disabling only nonvisual method
	# callbacks. All original Sprite2D transforms, timing and keys remain intact.
	var library := AnimationLibrary.new()
	for name: StringName in player.get_animation_list():
		var clip: Animation = player.get_animation(name).duplicate(true)
		for i in range(clip.get_track_count()):
			if clip.track_get_type(i) == Animation.TYPE_METHOD:
				clip.track_set_enabled(i, false)
			if String(clip.track_get_path(i)).contains("Zombie_Jackson_innerarm_hand:texture"):
				for j in range(clip.track_get_key_count(i)):
					var texture = clip.track_get_key_value(i, j)
					if texture is Texture2D:
						_hand_tracks.append({"clip":clip,"track":i,"key":j,"source":texture})
		library.add_animation(name, clip)
	player.remove_animation_library(&"")
	player.add_animation_library(&"", library)
	player.get_animation(&"moonwalk").loop_mode = Animation.LOOP_LINEAR

func _hand_texture(source: Texture2D, p2: bool) -> Texture2D:
	var key := str(source.get_instance_id()) + ("2" if p2 else "1")
	if _hand_cache.has(key):
		return _hand_cache[key]
	var image := source.get_image()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x,y)
			var v := maxf(c.r,maxf(c.g,c.b))
			if c.a < .06 or v <= .18:
				continue
			if p2:
				c = Color(.42+.52*v,.035+.15*v,.045+.13*v,c.a)
			elif c.g >= c.r*.90 and c.g > c.b*1.02:
				c = Color(.54+.42*v,.54+.40*v,.52+.39*v,c.a)
			image.set_pixel(x,y,c)
	var recolored := ImageTexture.create_from_image(image)
	_hand_cache[key] = recolored
	return recolored

func set_phase2(enabled: bool) -> void:
	var phase := 2 if enabled else 1
	for key: String in _records:
		(_coat[key] as Sprite2D).texture = load(String(_records[key][phase]["resource"]))
	for part: Node in _parts.get_children():
		if not part is Sprite2D:
			continue
		var path := ART + "native/phase_" + str(phase) + "/" + part.name + ".png"
		# Unchanged garments share the phase-one source rather than duplicating PNGs.
		if not ResourceLoader.exists(path):
			path = ART + "native/phase_1/" + part.name + ".png"
		if ResourceLoader.exists(path):
			(part as Sprite2D).texture = load(path)
	_glasses.texture = load(ACCESSORY + "glasses_p" + str(phase) + ".png")
	_hat.visible = not enabled
	for binding: Dictionary in _hand_tracks:
		var clip: Animation = binding["clip"]
		clip.track_set_key_value(int(binding["track"]),int(binding["key"]),_hand_texture(binding["source"],enabled))

func play_idle() -> void:
	# Actual Jackson show-state looping animation (no native "idle" clip exists).
	player.play(&"moonwalk")

func get_idle_duration() -> float:
	return player.get_animation(&"moonwalk").length / player.speed_scale
