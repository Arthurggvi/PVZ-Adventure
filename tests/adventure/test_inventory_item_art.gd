## Focused checks for 23 ID mappings, immutable slot anchoring and reusable recipes.
extends Node
const Asset = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const Tile = preload("res://scripts/adventure/ui/inventory_tile.gd")
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var m: Dictionary = Asset.manifest()
	assert(m.has("ids") and (m["ids"] as Dictionary).size() == 23)
	assert(m.has("backgrounds"))
	for id: String in ItemRegistry.ITEMS:
		assert(not Asset.entry(id).is_empty(), "Missing item art mapping: " + id)
		assert(not Asset.icon_uri(id).is_empty(), "Missing item icon: " + id)
		assert(load(Asset.icon_uri(id)) is Texture2D)
	assert(Asset.entry("invalid_item").is_empty())
	assert(Asset.icon_uri("invalid_item").is_empty())
	for category: String in ["material", "key", "consumable"]:
		var backing: String = str(m.backgrounds[category])
		assert(ResourceLoader.exists(Asset.ROOT + backing))
	assert(str(m.backgrounds["recipe"]) == "<null>" or m.backgrounds["recipe"] == null)
	assert(Asset.icon_uri("recipe_wall_nut") == Asset.icon_uri("recipe_potato_mine"))
	assert(not Asset.recipe_overlay_uri("recipe_wall_nut").is_empty())
	assert(Asset.recipe_overlay_uri("recipe_wall_nut") == Asset.recipe_overlay_uri("recipe_potato_mine"))
	assert(Asset.recipe_plant_type("recipe_wall_nut") == CharacterRegistry.PlantType.P004WallNut)
	assert(Asset.recipe_plant_type("recipe_potato_mine") == CharacterRegistry.PlantType.P005PotatoMine)
	var variants: Array[Dictionary] = [
		{"id":"unsaturated_fat","category":"material"},
		{"id":"lawn_nightmare_key","category":"key"},
		{"id":"growth_agent","category":"consumable"}]
	var anchor := Vector2(9, 3)
	for entry: Dictionary in variants:
		var tile: Control = Tile.new()
		add_child(tile)
		tile.setup({"kind":"item", "id":entry.id, "category":entry.category, "qty":3}, 0, false, false)
		assert(tile.get_child_count() >= 4)
		var slot: TextureRect = tile.get_child(0) as TextureRect
		var backing: TextureRect = tile.get_child(1) as TextureRect
		var icon: TextureRect = tile.get_child(2) as TextureRect
		assert(slot != null and backing != null and icon != null)
		print("LAYER_DEBUG ", str(entry.id), " backing=", backing.position, " size=", backing.size, " icon=", icon.position, " icon_size=", icon.size)
		assert(backing.position == anchor and backing.size == Vector2(68,68))
		assert(icon.position == Vector2(14,8) and icon.size == Vector2(58,58))
		assert(backing.position + backing.size * 0.5 == icon.position + icon.size * 0.5)
		assert(backing.texture.resource_path == Asset.backing_uri(str(entry.id)))
		assert(icon.texture.resource_path == Asset.icon_uri(str(entry.id)))
		tile.set_active(true)
		var frame: TextureRect = tile.get_child(tile.get_child_count() - 1) as TextureRect
		assert(frame != null and frame.visible)
		assert(frame.texture.resource_path.ends_with("item_slot_selected_frame.png"))
		assert(backing.position == anchor and icon.position == Vector2(14,8))
		tile.queue_free()
	var empty: Control = Tile.new()
	add_child(empty)
	empty.setup({}, 0, false, false)
	assert(empty.get_child_count() == 1, "Non-plant empty slot may not show a sprout")
	empty.queue_free()
	var recipe: Control = Tile.new()
	add_child(recipe)
	recipe.setup({"kind":"item","id":"recipe_wall_nut","category":"recipe","qty":1}, 1, false, false)
	assert(recipe.get_child_count() >= 4)
	assert(recipe.get_child(1) is TextureRect and recipe.get_child(2) is Node2D)
	assert((recipe.get_child(1) as TextureRect).texture.resource_path == Asset.icon_uri("recipe_wall_nut"))
	var recipe_wax: TextureRect = recipe.get_child(3) as TextureRect
	assert(recipe_wax != null and recipe_wax.texture.resource_path == Asset.recipe_overlay_uri("recipe_wall_nut"))
	recipe.queue_free()
	print("INVENTORY_ITEM_ART_PASS 23 IDs 27 PNGs slot-anchoring recipe-reuse")
	get_tree().quit(0)
