## Adapter over existing UID card instances and ItemRegistry: no parallel inventory data.
extends RefCounted

static func rows(category: String, search: String, order_mode: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if Global.adventure_inventory == null:
		return result
	if category == "plants":
		for card: Dictionary in Global.adventure_inventory.list_cards():
			var row := card.duplicate(true)
			row["kind"] = "plant"
			row["title"] = plant_name(int(row["plant_type"]))
			result.append(row)
	else:
		var counts: Dictionary = Global.adventure_inventory.get_items()
		for id: String in counts:
			var definition: Dictionary = ItemRegistry.get_item_definition(id)
			var group: String = str(definition.get("category", ""))
			if category == "recipes" and group != "recipe":
				continue
			if category == "materials" and group != "material":
				continue
			if category == "items" and group != "key" and group != "consumable":
				continue
			result.append({"kind": "item", "id": id, "title": str(definition.get("name", id)), "qty": int(counts[id]), "category": group})
	if not search.strip_edges().is_empty():
		var needle := search.strip_edges().to_lower()
		var filtered: Array[Dictionary] = []
		for row: Dictionary in result:
			var hay := (str(row.get("title", "")) + " " + str(row.get("uid", row.get("id", "")))).to_lower()
			if hay.contains(needle):
				filtered.append(row)
		result = filtered
	if order_mode == 1:
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["title"]) < str(b["title"]))
	elif order_mode == 2 and category == "plants":
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["stars"]) > int(b["stars"]))
	return result

static func plant_name(type_id: int) -> String:
	if Global.character_registry == null:
		return "植物 #%d" % type_id
	return str(Global.character_registry.get_plant_info(type_id as CharacterRegistry.PlantType,
		CharacterRegistry.PlantInfoAttribute.PlantName))

static func item_icon(row: Dictionary) -> String:
	match str(row.get("category", "")):
		"recipe": return "icons/category_recipes.png"
		"material": return "icons/category_materials.png"
		_: return "icons/category_items.png"
