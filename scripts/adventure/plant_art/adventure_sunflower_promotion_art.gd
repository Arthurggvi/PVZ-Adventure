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
## 把阳光原贴图的亮度映射为各转职的外观色。
const SUN_PALETTE_SHADER = preload("res://shaders/adventure/sun_palette.gdshader")
static var _manifest: Dictionary = {}
static var _texture_cache: Dictionary = {}
## 同一转职的阳光共用只读材质，每次产出只绑定已有实例。
static var _sun_materials: Dictionary[int, ShaderMaterial] = {}

static func _catalog() -> Dictionary:
	if _manifest.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary and data.has("parts") and data.has("tiers"):
			_manifest = data
		else:
			push_error("Sunflower promotion art manifest missing or invalid")
	return _manifest

## 返回 [param tier] 对应的外观配置。未转职时返回空字典。
static func _tier_config(tier: int) -> Dictionary:
	return _catalog().get("tiers", {}).get(str(tier), {}) if tier > 0 else {}

## 返回 [param tier] 对应的阳光材质，零转或未配置时使用阳光场景原色。
static func sun_material_for_tier(tier: int) -> ShaderMaterial:
	if _sun_materials.has(tier):
		return _sun_materials[tier]
	# 阳光配色和本体分件由同一条转职外观记录提供。
	var palette: Dictionary = _tier_config(tier).get("sun_palette", {})
	if palette.is_empty():
		return null
	var material := ShaderMaterial.new() # 每阶只创建一次，之后由阳光精灵继承。
	material.shader = SUN_PALETTE_SHADER
	material.set_shader_parameter(&"edge_color", Color.html(palette.edge))
	material.set_shader_parameter(&"main_color", Color.html(palette.main))
	material.set_shader_parameter(&"highlight_color", Color.html(palette.highlight))
	_sun_materials[tier] = material
	return material

static func _asset_set(tier: int) -> Dictionary:
	if _texture_cache.has(tier):
		return _texture_cache[tier]
	var info: Dictionary = _catalog()
	var subdir: String = str(_tier_config(tier).get("folder", "")) # 本转职的分件目录。
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

## 从 [param plant] 的冻结出战快照应用本体外观，返回实际应用的转职次数。
## 返回 0 时使用原始形象和阳光色。
static func apply(plant: Plant000Base) -> int:
	if plant == null or int(plant.plant_type) != SUNFLOWER_TYPE or plant.plant_spawn_profile == null:
		return 0
	# 使用卡面和出战共用的转职次数，星级变化不影响外观。
	var tier: int = plant.plant_spawn_profile.promotion_tier()
	if tier == 0:
		return 0
	var body := plant.get_node_or_null(^"Body/BodyCorrect") as Node2D # 原待机动画的部件容器。
	if not apply_to_body(body, tier):
		push_error("无法应用向日葵的出战转职外观")
		return 0
	return tier

## The catalog card and promotion book share this exact static tree adaptation.
static func apply_to_preview(preview: Node2D, tier: int) -> bool:
	if preview == null:
		return false
	var body := preview.get_node_or_null("Plant002SunFlower/Body/BodyCorrect") as Node2D
	return apply_to_body(body, tier)
