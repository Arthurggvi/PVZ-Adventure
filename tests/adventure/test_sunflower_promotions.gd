## Focused catalog and capped production growth checks. No save or combat scene writes.
extends SceneTree

const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")

func _initialize() -> void:
	create_timer(15.0, true, false, true).timeout.connect(func(): quit(1))
	_run.call_deferred()

func _run() -> void:
	var sunflower := PlantCardInstance.new()
	sunflower.plant_type = 2
	sunflower.stars = 10
	sunflower.promotion_1 = "promotion_sunflower_light_conversion"
	sunflower.promotion_2 = "promotion_sunflower_radiance"
	var tier3: Array[Dictionary] = Promotions.options(sunflower)
	assert(tier3.size() == 2)
	assert(tier3.any(func(book: Dictionary) -> bool: return book.id == "promotion_sunflower_stellar"))
	assert(tier3.any(func(book: Dictionary) -> bool: return book.id == "promotion_sunflower_resonance"))
	for book: Dictionary in tier3:
		assert(ItemRegistry.has_item(book.id) and int(book.tier) == 3)
	sunflower.promotion_3 = "promotion_sunflower_stellar"
	assert(Promotions.is_valid_chain(sunflower))
	var tier4: Array[Dictionary] = Promotions.options(sunflower)
	assert(tier4.size() == 2)
	assert(tier4.any(func(book: Dictionary) -> bool: return book.id == "promotion_sunflower_holy_war"))
	assert(tier4.any(func(book: Dictionary) -> bool: return book.id == "promotion_sunflower_flower_field"))
	for book: Dictionary in tier4:
		assert(ItemRegistry.has_item(book.id) and int(book.tier) == 4)
	sunflower.promotion_4 = "promotion_sunflower_flower_field"
	assert(Promotions.next_tier(sunflower) == 0)
	var kinds: Array = Promotions.effects(sunflower).events.map(
		func(event: Dictionary): return event.kind)
	assert(kinds.has("sun_growth") and kinds.has("deck_cost_discount"))
	sunflower.promotion_3 = "promotion_sunflower_resonance"
	sunflower.promotion_4 = "promotion_sunflower_holy_war"
	kinds = Promotions.effects(sunflower).events.map(
		func(event: Dictionary): return event.kind)
	assert(kinds.has("card_resonance") and kinds.has("adjacent_aura"))
	print("SUNFLOWER_PROMOTIONS_CATALOG_PASS (four books and both tier branches)")
	quit(0)
