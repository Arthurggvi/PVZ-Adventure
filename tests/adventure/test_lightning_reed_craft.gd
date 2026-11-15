## Focused end-to-end Lightning Reed item/crafting acceptance, isolated user profile.
extends Node
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const InventoryTile = preload("res://scripts/adventure/ui/inventory_tile.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var recipe: Dictionary = AdventureRecipeCatalog.definition("recipe_p050")
	assert(recipe.plant_type == CharacterRegistry.PlantType.P050LightningReed)
	assert(recipe.materials == ["aquatic_fiber", "charge_crystal"])
	assert(recipe.coin == 2000)
	assert(ItemRegistry.get_item_definition("recipe_p050").category == "recipe")
	assert(ItemRegistry.get_item_definition("charge_crystal").category == "material")
	assert(not ItemArt.icon_uri("charge_crystal").is_empty())
	assert(ItemArt.backing_uri("charge_crystal") == ItemArt.backing_uri("frost_crystal"))
	assert(ItemArt.icon_uri("recipe_p050") == ItemArt.icon_uri("recipe_wall_nut"))

	var card_tile: Control = InventoryTile.new()
	add_child(card_tile)
	card_tile.setup({"kind": "item", "id": "recipe_p050", "category": "recipe",
		"plant_type": 50, "qty": 1}, 0, false, false)
	assert(card_tile.get_child_count() >= 4)
	assert(card_tile.get_child(2) is Node2D)
	card_tile.queue_free()

	var state := AdventureState.new()
	AdventureQuestService.record_event(state, "stage_cleared", "zombie_island.lawn/normal", "2026-11-11")
	state.quests.records["first_expedition"].status = "claimed"
	var inventory := AdventureInventoryService.new(state)
	var wallet := GlobalGameState.new()
	wallet.adventure_state = state
	wallet.coin_value = 3000
	var service := AdventureResearchService.new(state, inventory, wallet, func() -> bool: return true)
	assert(inventory.add_item("recipe_p050", 1))
	assert(inventory.add_item("aquatic_fiber", 1))
	assert(inventory.add_item("charge_crystal", 1))
	var order := {"recipe_id": "recipe_p050"}
	var quote: Dictionary = service.quote("craft", order)
	assert(quote.ready and quote.fee == 2000 and quote.slots.size() == 2)
	var outcome: Dictionary = service.execute("craft", order)
	assert(outcome.ok)
	var card: Dictionary = inventory.get_card(outcome.uid)
	assert(card.plant_type == 50 and card.stars == 0)
	assert(wallet.coin_value == 1000)
	for consumed: String in ["recipe_p050", "aquatic_fiber", "charge_crystal"]:
		assert(inventory.get_item_count(consumed) == 0)
	assert(not service.execute("craft", order).ok)
	print("LIGHTNING_REED_CRAFT_PASS: art + recipe + transaction + zero-star card")
	get_tree().quit(0)
