## Adventure-only sunflower promotion artwork.
## Uses the ORIGINAL SunFlower_idle.tres animation tracks as the sole motion source.
## Adds cutout sprites as children of the original animated pivots.
extends RefCounted
class_name AdventureSunflowerPromotionArt

const ASSET_DIR := "res://assets/adventure/plants/sunflower/"
const MANIFEST := ASSET_DIR + "manifest.json"
const IDLE := "res://animation/character/plant/002_sun_flower/SunFlower_idle.tres"
const PIVOTS: Array[String] = ["Anim_idle", "SunFlower_toppetals", "Frontleaf"]

static var _manifest: Dictionary = {}
static var _original_rest: Dictionary = {}

static func _load_manifest() -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest

static func _load_original_rest() -> Dictionary:
	if not _original_rest.is_empty():
		return _original_rest
	var idle: Animation = load(IDLE)
	if idle == null:
		return {}
	var attrs: Dictionary = {}
	for pivot: String in PIVOTS:
		attrs[pivot] = {
			"position": Vector2.ZERO, "rotation": 0.0,
			"scale": Vector2.ONE, "skew": 0.0
		}
	for index: int in range(idle.get_track_count()):
		if idle.track_get_type(index) != Animation.TYPE_VALUE or not idle.track_is_enabled(index):
			continue
		var path: String = str(idle.track_get_path(index))
		var divider: int = path.rfind(":")
		if divider < 0:
			continue
		var attr: String = path.substr(divider + 1)
		if attr not in ["position", "rotation", "scale", "skew"]:
			continue
		for pivot: String in PIVOTS:
			if path.begins_with("Body/BodyCorrect/%s:" % pivot):
				attrs[pivot][attr] = idle.value_track_interpolate(index, 0.0)
	for pivot: String in PIVOTS:
		var values: Dictionary = attrs[pivot]
		_original_rest[pivot] = Transform2D(
			float(values.rotation), values.scale, float(values.skew), values.position)
	return _original_rest

static func apply(plant: Plant000Base) -> void:
	if plant == null or plant.plant_spawn_profile == null or int(plant.plant_type) != 2:
		return
	var snapshot: Dictionary = plant.plant_spawn_profile.snapshot()
	var tier := 0
	for level in range(1, 5):
		if str(snapshot.get("promotion_%d" % level, "")) != "":
			tier = level
	if tier == 0:
		return
	var manifest: Dictionary = _load_manifest()
	var poses: Dictionary = _load_original_rest()
	if manifest.is_empty() or poses.is_empty():
		push_error("Sunflower promotion art manifest or canonical idle animation missing")
		return
	var tiles: Dictionary = manifest.get("tiers", {})
	var specs: Array = tiles.get(str(tier), [])
	if specs.is_empty():
		push_error("Sunflower promotion art missing tier %d" % tier)
		return
	var mapping: Dictionary = manifest.get("mapping", {})
	var source_scale := float(mapping.get("scale", 0.0))
	var art_center: Array = mapping.get("image_center", [])
	var body_center: Array = mapping.get("body_center", [])
	if source_scale <= 0.0 or art_center.size() != 2 or body_center.size() != 2:
		push_error("Invalid sunflower promotion art coordinate mapping")
		return
	var pixel_origin := Vector2(
		float(body_center[0]) - source_scale * float(art_center[0]),
		float(body_center[1]) - source_scale * float(art_center[1]))
	var body: Node2D = plant.get_node_or_null("Body/BodyCorrect")
	if body == null:
		return
	# Resolve everything before hiding a single original sprite.
	var prepared: Array[Dictionary] = []
	for spec: Variant in specs:
		var entry: Dictionary = spec
		var anchor_name: String = str(entry.get("anchor", ""))
		var anchor: Sprite2D = body.get_node_or_null(anchor_name) as Sprite2D
		var ref_transform: Transform2D = poses.get(anchor_name, Transform2D.IDENTITY)
		var texture: Texture2D = load(ASSET_DIR + str(entry.get("file", ""))) as Texture2D
		var crop: Array = entry.get("crop", [])
		if anchor == null or texture == null or crop.size() != 4 or not poses.has(anchor_name):
			push_error("Incomplete sunflower promotion asset %s" % str(entry))
			return
		var cropped_origin := pixel_origin + source_scale * Vector2(
			float(crop[0]), float(crop[1]))
		var art_transform := Transform2D(
			Vector2(source_scale, 0.0), Vector2(0.0, source_scale), cropped_origin)
		prepared.append({
			"anchor": anchor, "texture": texture, "transform":
			ref_transform.affine_inverse() * art_transform
		})
	for child in body.get_children():
		if child is Sprite2D and child.name not in ["Stalk_bottom", "Stalk_top"]:
			(child as Sprite2D).self_modulate.a = 0.0
	for spec: Dictionary in prepared:
		var layer := Sprite2D.new()
		layer.name = "PromotionArt"
		layer.texture = spec.texture
		layer.centered = false
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		layer.transform = spec.transform
		(spec.anchor as Sprite2D).add_child(layer)
