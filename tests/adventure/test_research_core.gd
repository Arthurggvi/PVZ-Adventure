## Focused in-memory research acceptance, no user save writes or scene traversal.
extends SceneTree
const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")
const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
const Research = preload("res://scripts/adventure/research/research_service.gd")
var save_ok := true

func _initialize() -> void:
	create_timer(10.0, true, false, true).timeout.connect(func(): quit(1))
	_run.call_deferred()

func _persist() -> bool:
	return save_ok

func _run() -> void:
	assert(OS.get_user_data_dir().contains("research-core-test"))
	assert(Recipes.all_ids().size() == 49)
	for id: String in Recipes.all_ids():
		var recipe: Dictionary = Recipes.definition(id)
		assert(ItemRegistry.has_item(id))
		assert(recipe.materials.size() >= 2 and recipe.materials.size() <= 3)
		var unique: Dictionary = {}
		for material: String in recipe.materials:
			assert(ItemRegistry.get_item_definition(material).category == "material")
			assert(not unique.has(material))
			unique[material] = true
	var state := AdventureState.new()
	var inventory := AdventureInventoryService.new(state)
	var wallet := GlobalGameState.new()
	wallet.adventure_state = state
	wallet.coin_value = 30000
	var service: RefCounted = Research.new(state, inventory, wallet, Callable(self, "_persist"))
	assert(inventory.add_item("recipe_wall_nut", 1))
	assert(inventory.add_item("nut_fragments", 1))
	assert(inventory.add_item("unsaturated_fat", 1))
	var craft := {"recipe_id": "recipe_wall_nut"}
	assert(service.quote("craft", craft).ready)
	var crafted: Dictionary = service.execute("craft", craft)
	assert(crafted.ok)
	assert(inventory.get_card(crafted.uid).stars == 0)
	assert(inventory.get_item_count("recipe_wall_nut") == 0)
	assert(inventory.get_item_count("nut_fragments") == 0)
	assert(wallet.coin_value == 28000)
	assert(not service.execute("craft", craft).ok)
	var sunflower: String = inventory.add_card(2, 5)
	assert(inventory.add_item("promotion_sunflower_light_conversion", 1))
	var chosen := {"uid": sunflower, "book_id": "promotion_sunflower_light_conversion"}
	assert(service.quote("promotion", chosen).ready)
	var promoted: Dictionary = service.execute("promotion", chosen)
	assert(promoted.ok and wallet.coin_value == 23000)
	assert(state.cards[sunflower].stars == 5)
	assert(state.cards[sunflower].promotion_1 == chosen.book_id)
	assert(inventory.get_item_count(chosen.book_id) == 0)
	assert(not service.execute("promotion", chosen).ok)
	var effects: Dictionary = Promotions.effects(state.cards[sunflower]).stats
	assert(Promotions.resolve_stat(50.0, effects.sun_cost) == 25.0)
	assert(Promotions.resolve_stat(300.0, effects.max_health) == 450.0)
	state.cards[sunflower].stars = 7
	assert(inventory.add_item("promotion_sunflower_radiance", 1))
	var tier2 := {"uid": sunflower, "book_id": "promotion_sunflower_radiance"}
	assert(service.quote("promotion", tier2).ready)
	assert(service.execute("promotion", tier2).ok)
	assert(state.cards[sunflower].stars == 7 and state.cards[sunflower].promotion_2 == tier2.book_id)
	var failed_card: String = inventory.add_card(2, 5)
	assert(inventory.add_item("promotion_sunflower_photosynthesis", 1))
	var failed_choice := {"uid": failed_card, "book_id": "promotion_sunflower_photosynthesis"}
	var before: String = JSON.stringify(state.to_dict())
	var coins: int = wallet.coin_value
	save_ok = false
	assert(not service.execute("promotion", failed_choice).ok)
	assert(JSON.stringify(state.to_dict()) == before and wallet.coin_value == coins)
	save_ok = true
	assert(Enhancement.protection_count(4) == 1)
	assert(Enhancement.protection_count(5) == 2)
	assert(Enhancement.protection_count(6) == 4)
	assert(Enhancement.protection_count(7) == 8)
	assert(Enhancement.protection_count(10) == 64)
	assert(Enhancement.result_star(4, false, false) == 3)
	assert(Enhancement.result_star(4, false, true) == 4)
	var filler: String = inventory.add_card(1, 0)
	var invalid := {"uid": sunflower, "materials": [filler]}
	assert(not service.quote("upgrade", invalid).ready)
	var compatible: String = inventory.add_card(1, 5)
	var quote: Dictionary = service.quote("upgrade", {"uid": sunflower, "materials": [compatible]})
	assert(not quote.ready and str(quote.message).contains("概率算法未定义"))
	assert(state.to_dict() != {})
	var old: Dictionary = state.cards[sunflower].to_dict()
	old.erase("promotion_3")
	old.erase("promotion_4")
	assert(PlantCardInstance.from_dict(old).promotion_4.is_empty())
	# A known book in the wrong tier or a different plant must not be persisted or applied.
	state.cards[sunflower].promotion_3 = "promotion_sunflower_synergy"
	assert(state.to_dict().is_empty())
	assert(Promotions.effects(state.cards[sunflower]).stats.is_empty())
	state.cards[sunflower].promotion_3 = ""
	var retained: String = JSON.stringify(state.to_dict())
	wallet.adventure_state = AdventureState.new()
	assert(not service.execute("promotion", failed_choice).ok)
	assert(JSON.stringify(state.to_dict()) == retained)
	wallet.adventure_state = state
	print("RESEARCH_CORE_PASS 49 recipes, craft, irreversible promotion, rollback, upgrade contract")
	quit(0)
