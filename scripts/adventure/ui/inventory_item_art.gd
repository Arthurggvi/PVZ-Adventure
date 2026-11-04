## Image composition catalog; the item manifest supplies art paths, never item ownership.
extends RefCounted
const ROOT := "res://assets/adventure/ui/items/"
const MANIFEST := ROOT + "item_icon_map.json"
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
		return {}
	if str(data.get("category", "")) != str(ItemRegistry.get_item_definition(item_id).get("category", "")):
		return {}
	return data

static func icon_uri(item_id: String) -> String:
	var file: String = str(entry(item_id).get("icon", ""))
	var path := ROOT + file
	return path if not file.is_empty() and ResourceLoader.exists(path) else ""

static func backing_uri(item_id: String) -> String:
	var category: String = str(entry(item_id).get("category", ""))
	var file: String = str(manifest().get("backgrounds", {}).get(category, ""))
	var path := ROOT + file
	return path if not file.is_empty() and ResourceLoader.exists(path) else ""

static func recipe_overlay_uri(item_id: String) -> String:
	if str(entry(item_id).get("category", "")) != "recipe":
		return ""
	var file: String = str(entry(item_id).get("overlay", ""))
	var path := ROOT + file
	return path if not file.is_empty() and ResourceLoader.exists(path) else ""

static func recipe_plant_type(item_id: String) -> int:
	var name: String = str(entry(item_id).get("portrait_from_plant_type", ""))
	return int(CharacterRegistry.PlantType.get(name, 0)) if not name.is_empty() else 0

## Place only the original registered character artwork over the reusable scroll.
static func add_recipe_portrait(parent: Node, item_id: String, center: Vector2, scale_value: float) -> Node2D:
	var plant: int = recipe_plant_type(item_id)
	if plant <= 0:
		return null
	var ref := ResourceCardReference.create(ResourceCardReference.CardType.Plant, plant)
	var sprite: Node2D = AllCards.create_static_preview(ref)
	if sprite == null:
		return null
	sprite.position = center
	sprite.scale = Vector2.ONE * scale_value
	parent.add_child(sprite)
	return sprite
