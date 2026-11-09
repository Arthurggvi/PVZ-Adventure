## A single composition boundary for four-tier promotion books.
## The existing skill catalog supplies tier and plant identity. This module only draws art.
extends RefCounted

const InventorySkin = preload("res://scripts/adventure/ui/inventory_skin.gd")
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")

## The cover medallion is slightly above and left of the texture canvas center.
const MEDALLION_CENTER := Vector2(0.475, 0.445)
const PORTRAIT_SCALE_PER_PIXEL := 0.00335

static func draw(parent: Node, item_id: String, bounds: Rect2) -> bool:
	var definition: Dictionary = AdventurePromotionCatalog.definition(item_id)
	var tier: int = int(definition.get("tier", 0))
	if tier < 1 or tier > 4:
		return false
	var background: String = ItemArt.backing_uri(item_id)
	var cover: String = ItemArt.promotion_tier_uri(tier)
	if background.is_empty() or cover.is_empty():
		push_error("Promotion book art missing for tier %d" % tier)
		return false
	InventorySkin.image(parent, background, bounds.position, bounds.size)
	InventorySkin.image(parent, cover, bounds.position, bounds.size)
	var plant_type: int = int(definition.get("plant_type", 0))
	if plant_type > 0:
		var position: Vector2 = bounds.position + bounds.size * MEDALLION_CENTER
		var portrait_scale: float = bounds.size.x * PORTRAIT_SCALE_PER_PIXEL
		ItemArt.add_recipe_portrait(parent, plant_type, position, portrait_scale, tier)
	return true
