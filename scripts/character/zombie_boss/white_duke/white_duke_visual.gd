extends Node2D
class_name WhiteDukeVisual
## Visual adapter: the 21 native Jackson Sprite2D nodes and six original .tres animations
## live in white_duke_visual.tscn. No parallel skeleton or keyframe authoring.
const ART := "res://assets/adventure/zombies/white_duke/"
const ACCESSORY := ART + "accessories/"
@onready var player: AnimationPlayer = $AnimationPlayer
@onready var _parts: Node2D = $Body/BodyCorrect
@onready var _phase_fx: WhiteFlameSpotlightEffect = $Phase2FX
@onready var _teleport: BossTeleportEffect = $TeleportFX
var _records: Dictionary = {}
var _coat: Dictionary = {}
var _hand_tracks: Array[Dictionary] = []
var _hand_cache: Dictionary = {}
var _hat: Sprite2D
var _glasses: Sprite2D
var _phase_two := false

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
	player.animation_finished.connect(_on_action_finished)
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
		# 绑定表以躯干为层级基准，扣除锚点偏移后仍随白爵士所在行绘制。
		sprite.z_index = int(rec["z"]) - anchor.z_index
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
	for clip_name: StringName in player.get_animation_list():
		var clip: Animation = player.get_animation(clip_name).duplicate(true)
		for i in range(clip.get_track_count()):
			if clip.track_get_type(i) == Animation.TYPE_METHOD:
				clip.track_set_enabled(i, false)
			if String(clip.track_get_path(i)).contains("Zombie_Jackson_innerarm_hand:texture"):
				for j in range(clip.track_get_key_count(i)):
					var texture = clip.track_get_key_value(i, j)
					if texture is Texture2D:
						_hand_tracks.append({"clip":clip,"track":i,"key":j,"source":texture})
		library.add_animation(clip_name, clip)
	player.remove_animation_library(&"")
	player.add_animation_library(&"", library)
	player.get_animation(&"moonwalk").loop_mode = Animation.LOOP_LINEAR
	player.get_animation(&"walk").loop_mode = Animation.LOOP_LINEAR
	library.add_animation(&"teleport_in", BossTeleportAnimationFactory.build(true))
	library.add_animation(&"teleport_out", BossTeleportAnimationFactory.build(false))

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
	_phase_two = enabled
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
	_phase_fx.set_active(enabled)
	for binding: Dictionary in _hand_tracks:
		var clip: Animation = binding["clip"]
		clip.track_set_key_value(int(binding["track"]),int(binding["key"]),_hand_texture(binding["source"],enabled))

func play_idle() -> void:
	# Actual Jackson show-state looping animation (no native "idle" clip exists).
	player.play(&"moonwalk")

func get_idle_duration() -> float:
	return player.get_animation(&"moonwalk").length / player.speed_scale

## The native Jackson point clip is the summon-with-raised-finger animation.
## No skeleton or pose interpolation is reauthored.
func play_summon() -> Color:
	var chosen := _phase_fx.summon_spotlight(_phase_two)
	player.play(&"point")
	return chosen

func play_teleport_in() -> void:
	_set_boss_shadow_visible(false)
	_phase_fx.suspend_for_teleport()
	$Body.visible = true
	$Body.modulate.a = 0.0
	_phase_fx.visible = _phase_two
	_phase_fx.modulate.a = 0.0
	_teleport.begin(true)
	player.play(&"teleport_in")

func play_teleport_out() -> void:
	_phase_fx.suspend_for_teleport()
	$Body.visible = true
	$Body.modulate.a = 1.0
	_phase_fx.modulate.a = 1.0
	_teleport.begin(false)
	player.play(&"teleport_out")

func _on_action_finished(action: StringName) -> void:
	match action:
		&"point":
			play_idle()
		&"teleport_in":
			_teleport.finish()
			$Body.modulate.a = 1.0
			_phase_fx.modulate.a = 1.0
			_set_boss_shadow_visible(true)
			play_idle()
		&"teleport_out":
			_teleport.finish()
			$Body.visible = false
			_phase_fx.visible = false
			_set_boss_shadow_visible(false)

func _set_boss_shadow_visible(enabled: bool) -> void:
	var boss: Node = get_parent().get_parent()
	var shadow: CanvasItem = boss.get_node_or_null("Shadow") as CanvasItem
	if shadow != null:
		shadow.visible = enabled
