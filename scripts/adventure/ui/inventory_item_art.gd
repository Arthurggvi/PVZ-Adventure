## Image composition catalog; the item manifest supplies art paths, never item ownership.
extends RefCounted
const ROOT := "res://assets/adventure/ui/items/"
## 配方书使用原卷轴；转职技能书通过 promotion_tiers 独立解析，不借用卷轴。
const SCROLL_PATH := "recipes/recipe_scroll.png"
## Visual paths are resolved from the item category; recipe identity is supplied by the data adapter.
const MANIFEST := ROOT + "item_icon_map.json"
## 所有配方中央植物图案统一放大两倍，卷轴与蜡封保持原尺寸。
const RECIPE_PORTRAIT_SCALE := 2.0
static var _loaded := false
static var _catalog: Dictionary = {}

static func manifest() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary and parsed.get("ids") is Dictionary and parsed.get("backgrounds") is Dictionary:
			_catalog = parsed
		else:
			push_error("InventoryItemArt: missing or invalid item art manifest.")
	return _catalog

static func entry(item_id: String) -> Dictionary:
	if not ItemRegistry.has_item(item_id):
		return {}
	var data: Dictionary = manifest().get("ids", {}).get(item_id, {})
	if data.is_empty():
		var category: String = str(ItemRegistry.get_item_definition(item_id).get("category", ""))
		if category == "recipe":
			return {"category": "recipe", "icon": SCROLL_PATH,
				"overlay": "decorations/recipe_wax_seal.png"}
		if category == "promotion_book":
			return {"category": "promotion_book"}
		return {}
	if str(data.get("category", "")) != str(ItemRegistry.get_item_definition(item_id).get("category", "")):
		return {}
	return data

## Tier icon paths are defined once in the art manifest; the item catalog supplies the tier.
static func promotion_tier_uri(tier: int) -> String:
	var file: String = str(manifest().get("promotion_tiers", {}).get(str(tier), ""))
	var uri: String = ROOT + file
	return uri if not file.is_empty() and ResourceLoader.exists(uri) else ""

static func icon_uri(item_id: String) -> String:
	var category: String = str(ItemRegistry.get_item_definition(item_id).get("category", ""))
	if category == "promotion_book":
		var tier: int = int(ItemRegistry.get_item_definition(item_id).get("promotion_tier", 0))
		return promotion_tier_uri(tier)
	var file: String = str(entry(item_id).get("icon", ""))
	var path := ROOT + file
	return path if not file.is_empty() and ResourceLoader.exists(path) else ""

static func backing_uri(item_id: String) -> String:
	var definition: Dictionary = entry(item_id)
	var category: String = str(definition.get("category", ""))
	var file: String = ""
	if category == "material":
		var group: String = str(definition.get("backing_group", ""))
		file = str(manifest().get("material_backings", {}).get(group, ""))
	else:
		file = str(manifest().get("backgrounds", {}).get(category, ""))
	var path: String = ROOT + file
	return path if not file.is_empty() and ResourceLoader.exists(path) else ""

static func recipe_overlay_uri(item_id: String) -> String:
	if str(entry(item_id).get("category", "")) != "recipe":
		return ""
	var file: String = str(entry(item_id).get("overlay", ""))
	var path := ROOT + file
	return path if not file.is_empty() and ResourceLoader.exists(path) else ""

## Art receives an already-resolved plant type from the inventory data adapter.
static func add_recipe_portrait(parent: Node, plant_type: int, center: Vector2,
		scale_value: float, promotion_tier: int = 0) -> Node2D:
	if plant_type <= 0:
		return null
	var ref := ResourceCardReference.create(ResourceCardReference.CardType.Plant, plant_type)
	var sprite: Node2D = AllCards.create_static_preview(ref, promotion_tier)
	if sprite == null:
		return null
	sprite.position = center
	sprite.scale = Vector2.ONE * scale_value * RECIPE_PORTRAIT_SCALE
	parent.add_child(sprite)
	return sprite
