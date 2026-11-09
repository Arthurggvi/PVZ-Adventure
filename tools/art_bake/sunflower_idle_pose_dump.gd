## Exact source-only sampler for PVZ-Adventure's original SunFlower_idle.tres.
## Extracts the Animation resource's value-track interpolation without rendering
## and without replacing the original scene or animation.
extends SceneTree

const SCENE := "res://scenes/character/plant/plant_002_sun_flower.tscn"
const ANIM := "res://animation/character/plant/002_sun_flower/SunFlower_idle.tres"
const DEST := "C:/Dev/PvZ/_review/sunflower_promotions/idle_source_poses.json"
const ANIM_FPS := 12.0
const ANIM_SPEED := 1.2
const FRAME_COUNT := 24

func _v(v: Variant) -> Variant:
	if v is Vector2:
		return [v.x, v.y]
	if v is Color:
		return [v.r, v.g, v.b, v.a]
	if v is Texture2D:
		return v.resource_path
	if v is float or v is int or v is bool or v is String:
		return v
	return null

func _initialize() -> void:
	print("SOURCE_POSE_DUMP_START")
	_run.call_deferred()

func _run() -> void:
	var scene_pack: PackedScene = load(SCENE)
	var animation: Animation = load(ANIM)
	if scene_pack == null or animation == null:
		push_error("Cannot load authoritative scene/animation")
		quit(1)
		return
	var plant: Node = scene_pack.instantiate()
	var body: Node2D = plant.get_node("Body")
	var body_correct: Node2D = plant.get_node("Body/BodyCorrect")
	var parts: Array[Dictionary] = []
	for node: Node in body_correct.get_children():
		if node is Sprite2D:
			var s: Sprite2D = node
			parts.append({
				"name":s.name,
				"position":_v(s.position),
				"rotation":s.rotation,
				"scale":_v(s.scale),
				"skew":s.skew,
				"visible":s.visible,
				"texture":_v(s.texture),
				"centered":s.centered,
				"offset":_v(s.offset),
				"size":_v(s.texture.get_size()) if s.texture != null else [0,0]
			})
	var tracks: Array[Dictionary] = []
	for index: int in range(animation.get_track_count()):
		if animation.track_get_type(index) != Animation.TYPE_VALUE:
			continue
		if not animation.track_is_enabled(index):
			continue
		var path: String = str(animation.track_get_path(index))
		if not path.begins_with("Body/BodyCorrect/"):
			continue
		var colon := path.rfind(":")
		if colon < 0:
			continue
		var name: String = path.substr(17,colon-17)
		var attr: String = path.substr(colon+1)
		if not attr in ["position","rotation","scale","skew","visible","texture","offset"]:
			continue
		tracks.append({"index":index,"name":name,"attr":attr})
	var frames: Array[Dictionary] = []
	for i: int in range(FRAME_COUNT):
		var t := float(i) / ANIM_FPS
		var poses := {}
		for tr: Dictionary in tracks:
			var value: Variant = animation.value_track_interpolate(int(tr.index),t)
			if not poses.has(tr.name):
				poses[tr.name] = {}
			poses[tr.name][tr.attr] = _v(value)
		frames.append({"animation_time":t,"poses":poses})
	var payload: Dictionary = {
		"scene":SCENE,"animation":ANIM,
		"length":animation.length,"step":animation.step,
		"speed":ANIM_SPEED,"frame_count":FRAME_COUNT,
		"frame_duration_ms":int(round(1000.0/(ANIM_FPS*ANIM_SPEED))),
		"body":{"position":_v(body.position),"rotation":body.rotation,"scale":_v(body.scale)},
		"body_correct":{"position":_v(body_correct.position),"rotation":body_correct.rotation,"scale":_v(body_correct.scale)},
		"parts":parts,"frames":frames
	}
	var f: FileAccess = FileAccess.open(DEST,FileAccess.WRITE)
	if f == null:
		push_error("Output path is not writable: "+DEST)
		quit(1)
		return
	f.store_string(JSON.stringify(payload))
	f.close()
	print("SOURCE_POSES_OK parts=",parts.size()," tracks=",tracks.size()," frames=",frames.size()," file=",DEST)
	plant.free()
	quit(0)
