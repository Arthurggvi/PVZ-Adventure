## Inventory item art contracts: complete mappings, key icons, backing reuse and slot anchoring.
extends Node
const Asset = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const Tile = preload("res://scripts/adventure/ui/inventory_tile.gd")
const WONDERLAND_SLUGS: Array[String] = [
	"psychedelic_current", "zombie_church", "john_furnace", "snow_mountains",
	"garden_airship", "edgar_mountain", "mushroom_forest", "resting_plain",
	"frozen_tundra", "badlands", "abandoned_school"
]
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var m: Dictionary = Asset.manifest()
	assert(m.has("ids") and (m["ids"] as Dictionary).size() == 54)
	assert(m.has("backgrounds"))
	# 奇境大陆所有地区的噩梦钥匙必须通过同一物品注册表与背包美术清单。
	var wonderland_paths: Dictionary = {}
	for slug: String in WONDERLAND_SLUGS:
		var key_id: String = "wonderland.%s.nightmare_key" % slug
		var definition: Dictionary = ItemRegistry.get_item_definition(key_id)
		assert(definition.get("category", "") == "key", key_id)
		assert(not str(definition.get("name", "")).is_empty(), key_id)
		assert(m["ids"].has(key_id), key_id)
		assert(Asset.backing_uri(key_id) == Asset.backing_uri("lawn_nightmare_key"), key_id)
		var icon_path: String = Asset.icon_uri(key_id)
		assert(icon_path.ends_with("keys/wonderland_%s_nightmare_key.png" % slug), key_id)
		assert(not wonderland_paths.has(icon_path), "Duplicate wonderland key art: " + key_id)
		wonderland_paths[icon_path] = true
		var icon_texture: Texture2D = load(icon_path) as Texture2D
		assert(icon_texture != null and icon_texture.get_size() == Vector2(256, 256), key_id)
		var pixel_data: Image = icon_texture.get_image()
		assert(pixel_data != null and pixel_data.get_pixel(0, 0).a < 0.05, key_id)
	assert(Asset.icon_uri("wonderland.psychedelic_current.terminal_key") ==
		Asset.icon_uri("wonderland.psychedelic_current.nightmare_key"))
	assert(ItemRegistry.get_item_definition("wonderland.psychedelic_current.nightmare_key").description ==
		"致幻洋流普通阶段通关获得，消耗一把进入本局噩梦阶段。")
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
	assert((m["material_backings"] as Dictionary).size() == 7)
	var materials: Array[String] = []
	for id: String in ItemRegistry.ITEMS:
		if ItemRegistry.get_item_definition(id).get("category", "") != "material":
			continue
		materials.append(id)
		assert(not str(ItemRegistry.get_item_definition(id).get("description", "")).is_empty())
		assert(m["ids"].has(id))
		assert(not str(m["ids"][id].get("backing_group", "")).is_empty())
		assert(not Asset.backing_uri(id).is_empty())
		assert(load(Asset.backing_uri(id)) is Texture2D)
	assert(materials.size() == 22)
	assert(Asset.backing_uri("pea_stem") == Asset.backing_uri("plant_fiber"))
	assert(Asset.backing_uri("fungal_spores") != Asset.backing_uri("grave_moss"))
	assert(Asset.backing_uri("ember_resin") == Asset.backing_uri("frost_crystal"))
	assert(Asset.icon_uri("recipe_wall_nut") == Asset.icon_uri("recipe_potato_mine"))
	assert(Asset.icon_uri("recipe_p050") == Asset.icon_uri("recipe_wall_nut"))
	assert(not Asset.icon_uri("charge_crystal").is_empty())
	assert(Asset.backing_uri("charge_crystal") == Asset.backing_uri("frost_crystal"))
	assert(not Asset.recipe_overlay_uri("recipe_wall_nut").is_empty())
	assert(Asset.recipe_overlay_uri("recipe_wall_nut") == Asset.recipe_overlay_uri("recipe_potato_mine"))
	assert(AdventureRecipeCatalog.definition("recipe_wall_nut").plant_type == CharacterRegistry.PlantType.P004WallNut)
	assert(AdventureRecipeCatalog.definition("recipe_potato_mine").plant_type == CharacterRegistry.PlantType.P005PotatoMine)
	var variants: Array[Dictionary] = [
		{"id":"unsaturated_fat","category":"material"},
		{"id":"fungal_spores","category":"material"},
		{"id":"aquatic_fiber","category":"material"},
		{"id":"lawn_nightmare_key","category":"key"},
		{"id":"wonderland.resting_plain.nightmare_key","category":"key"},
		{"id":"growth_agent_lv1","category":"consumable"}]
	var anchor := Vector2(-5, 0) # 道具底图按格子高度填充后的居中位置。
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
		assert(not slot.visible) # 仅替换底层填色，默认边框由独立上层节点绘制。
		assert(backing.position == anchor and backing.size == Tile.BACKING_SIZE)
		assert(icon.position == Tile.ICON_POSITION and icon.size == Tile.ICON_SIZE)
		assert(backing.position + backing.size * 0.5 == icon.position + icon.size * 0.5)
		assert(backing.texture.resource_path == Asset.backing_uri(str(entry.id)))
		assert(icon.texture.resource_path == Asset.icon_uri(str(entry.id)))
		tile.set_active(true)
		var frame: TextureRect = tile.get_child(tile.get_child_count() - 1) as TextureRect
		assert(frame != null and frame.visible)
		assert(frame.texture.resource_path.ends_with("item_slot_selected_frame.png"))
		assert(backing.position == anchor and icon.position == Tile.ICON_POSITION)
		tile.queue_free()
	var empty: Control = Tile.new()
	add_child(empty)
	empty.setup({}, 0, false, false)
	assert(empty.get_child_count() == 1, "Non-plant empty slot may not show a sprout")
	empty.queue_free()
	var recipe: Control = Tile.new()
	add_child(recipe)
	recipe.setup({"kind":"item","id":"recipe_wall_nut","category":"recipe","plant_type":4,"qty":1}, 1, false, false)
	assert(recipe.get_child_count() >= 4)
	assert(recipe.get_child(1) is TextureRect and recipe.get_child(2) is Node2D)
	assert((recipe.get_child(1) as TextureRect).texture.resource_path == Asset.icon_uri("recipe_wall_nut"))
	assert(not (recipe.get_child(0) as TextureRect).visible) # 卷轴作为底图，默认边框独立叠加。
	assert((recipe.get_child(1) as TextureRect).position == Tile.BACKING_POSITION)
	assert((recipe.get_child(1) as TextureRect).size == Tile.BACKING_SIZE)
	var recipe_wax: TextureRect = recipe.get_child(3) as TextureRect
	assert(recipe_wax != null and recipe_wax.texture.resource_path == Asset.recipe_overlay_uri("recipe_wall_nut"))
	recipe.queue_free()
	print("INVENTORY_ITEM_ART_PASS %d mapped IDs %d materials 7 backings" % [m["ids"].size(), materials.size()])
	get_tree().quit(0)
