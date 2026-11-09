## One authoritative, source-pivot-based sunflower promotion appearance for battle, cards and books.
## Never edits the canonical Idle animation or the original sprite assets.
extends RefCounted
class_name AdventureSunflowerPromotionArt

const ASSET_DIR := "res://assets/adventure/plants/sunflower/"
const MANIFEST := ASSET_DIR + "manifest.json"
const ORIGINAL_DIR := "res://assets/reanim/"
const SUNFLOWER_TYPE := 2
const PETAL_LAYER := "PromotionPetal"
const HEAD_LAYER := "PromotionFace"
const STAR_LAYER := "PromotionStar"
static var _manifest: Dictionary = {}
static var _texture_cache: Dictionary = {}

static func _catalog() -> Dictionary:
	if _manifest.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary and data.has("parts") and data.has("tiers"):
			_manifest = data
		else:
			push_error("Sunflower promotion art manifest missing or invalid")
	return _manifest

## Promotion choices are authoritative, irrespective of current stars.
static func tier_from_snapshot(snapshot: Dictionary) -> int:
	var tier := 0
	for index: int in range(1, 5):
		if not str(snapshot.get("promotion_%d" % index, "")).is_empty():
			tier = index
	return tier

static func tier_from_profile(profile: PlantSpawnProfile) -> int:
	return tier_from_snapshot(profile.snapshot()) if profile != null else 0

static func _asset_set(tier: int) -> Dictionary:
	if _texture_cache.has(tier):
		return _texture_cache[tier]
	var info: Dictionary = _catalog()
	var subdir: String = str(info.get("tiers", {}).get(str(tier), ""))
	if subdir.is_empty():
		return {}
	var assets: Dictionary = {}
	for part_name: Variant in info["parts"]:
		var part: String = str(part_name)
		var path := ASSET_DIR + subdir + "/" + part + ".png"
		var texture := load(path) as Texture2D
		if texture == null:
			push_error("Sunflower promotion texture missing: " + path)
			return {}
		assets[part] = texture
	var star_path := ASSET_DIR + subdir + "/SunFlower_promotion_starburst.png"
	var star := load(star_path) as Texture2D
	if star == null:
		push_error("Sunflower promotion star missing: " + star_path)
		return {}
	assets[STAR_LAYER] = star
	if tier == int(info.get("wink_tier", 0)):
		var wink := load(ORIGINAL_DIR + "SunFlower_head_wink.png") as Texture2D
		if wink == null:
			return {}
		assets[HEAD_LAYER] = wink
	_texture_cache[tier] = assets
	return assets

static func _ensure_layer(anchor: Sprite2D, layer_name: String) -> Sprite2D:
	var layer := anchor.get_node_or_null(layer_name) as Sprite2D
	if layer == null:
		layer = Sprite2D.new()
		layer.name = layer_name
		layer.centered = anchor.centered
		layer.offset = anchor.offset
		layer.texture_filter = anchor.texture_filter
		anchor.add_child(layer)
	return layer

static func _remove_layer(anchor: Sprite2D, layer_name: String) -> void:
	var layer: Node = anchor.get_node_or_null(layer_name)
	if layer != null:
		anchor.remove_child(layer)
		layer.free()

## Uses the exact original animated Sprite2D pivots. Animated :texture tracks
## still write to original nodes, so the replacement is drawn on a child layer.
## self_modulate only hides the original sprite, never its replacement child.
static func apply_to_body(body: Node2D, tier: int) -> bool:
	if body == null or tier < 0 or tier > 4:
		return false
	var info: Dictionary = _catalog()
	if info.is_empty():
		return false
	var prepared: Dictionary = _asset_set(tier) if tier > 0 else {}
	if tier > 0 and prepared.is_empty():
		return false
	var anchors: Array[Sprite2D] = []
	for part_name: Variant in info["parts"]:
		var anchor := body.get_node_or_null(str(part_name)) as Sprite2D
		if anchor == null:
			push_error("Missing sunflower source pivot: " + str(part_name))
			return false
		anchors.append(anchor)
	var head := body.get_node_or_null("Anim_idle") as Sprite2D
	if head == null:
		return false
	for anchor: Sprite2D in anchors:
		if tier == 0:
			_remove_layer(anchor, PETAL_LAYER)
			anchor.self_modulate.a = 1.0
		else:
			var layer := _ensure_layer(anchor, PETAL_LAYER)
			layer.texture = prepared[anchor.name]
			anchor.self_modulate.a = 0.0
	if tier == 0 or not prepared.has(HEAD_LAYER):
		_remove_layer(head, HEAD_LAYER)
		head.self_modulate.a = 1.0
	else:
		var face := _ensure_layer(head, HEAD_LAYER)
		face.texture = prepared[HEAD_LAYER]
		head.self_modulate.a = 0.0
	if tier == 0:
		_remove_layer(head, STAR_LAYER)
	else:
		var star := _ensure_layer(head, STAR_LAYER)
		star.texture = prepared[STAR_LAYER]
		star.centered = false
		var star_pos: Array = info.get("star_offset", [18.5, -13.0])
		star.position = Vector2(float(star_pos[0]), float(star_pos[1]))
	return true

## All battle sunflower instances consume the same frozen profile as their cards.
static func apply(plant: Plant000Base) -> void:
	if plant == null or int(plant.plant_type) != SUNFLOWER_TYPE:
		return
	var body: Node2D = plant.get_node_or_null("Body/BodyCorrect")
	if body == null:
		return
	var tier: int = tier_from_profile(plant.plant_spawn_profile)
	if tier > 0 and not apply_to_body(body, tier):
		push_error("Cannot apply sunflower promotion art to battle plant")

## The catalog card and promotion book share this exact static tree adaptation.
static func apply_to_preview(preview: Node2D, tier: int) -> bool:
	if preview == null:
		return false
	var body := preview.get_node_or_null("Plant002SunFlower/Body/BodyCorrect") as Node2D
	return apply_to_body(body, tier)
