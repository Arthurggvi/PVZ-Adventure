## One recipe per registered regular plant; each consumes one scroll and 2-3 distinct units.
## IDs are stable save keys. This table determines ingredients, not stage drops.
extends RefCounted
class_name AdventureRecipeCatalog

const COST := 2000
const INGREDIENTS: Dictionary = {
	1: ["explosive_seed", "plant_starch"],
	2: ["unsaturated_fat", "plant_starch"],
	3: ["explosive_seed", "rotten_wood_core", "plant_starch"],
	4: ["nut_fragments", "unsaturated_fat"],
	5: ["explosive_seed", "plant_starch"],
	6: ["explosive_seed", "grave_moss"],
	7: ["plant_starch", "zombie_thread"],
	8: ["explosive_seed", "plant_starch", "zombie_thread"],
	9: ["rotten_wood_core", "grave_moss"],
	10: ["rotten_wood_core", "unsaturated_fat"],
	11: ["rotten_wood_core", "zombie_thread"],
	12: ["grave_moss", "zombie_thread"],
	13: ["grave_moss", "unsaturated_fat"],
	14: ["grave_moss", "rotten_wood_core", "zombie_thread"],
	15: ["grave_moss", "unsaturated_fat", "plant_starch"],
	16: ["explosive_seed", "grave_moss", "rotten_wood_core"],
	17: ["plant_starch", "unsaturated_fat"],
	18: ["nut_fragments", "plant_starch"],
	19: ["explosive_seed", "plant_starch", "unsaturated_fat"],
	20: ["grave_moss", "zombie_thread", "plant_starch"],
	21: ["explosive_seed", "rotten_wood_core"],
	22: ["rusted_scrap", "nut_fragments"],
	23: ["rotten_wood_core", "unsaturated_fat", "explosive_seed"],
	24: ["nut_fragments", "rusted_scrap", "plant_starch"],
	25: ["grave_moss", "plant_starch"],
	26: ["rotten_wood_core", "grave_moss", "unsaturated_fat"],
	27: ["plant_starch", "rusted_scrap"],
	28: ["zombie_thread", "unsaturated_fat"],
	29: ["explosive_seed", "zombie_thread"],
	30: ["plant_starch", "unsaturated_fat", "rusted_scrap"],
	31: ["nut_fragments", "plant_starch", "zombie_thread"],
	32: ["rusted_scrap", "grave_moss"],
	33: ["plant_starch", "rotten_wood_core"],
	34: ["rotten_wood_core", "nut_fragments"],
	35: ["plant_starch", "rotten_wood_core", "unsaturated_fat"],
	36: ["rotten_wood_core", "grave_moss", "plant_starch"],
	37: ["plant_starch", "zombie_thread", "unsaturated_fat"],
	38: ["nut_fragments", "zombie_thread", "plant_starch"],
	39: ["unsaturated_fat", "rusted_scrap"],
	40: ["plant_starch", "unsaturated_fat", "nut_fragments"],
	41: ["explosive_seed", "rusted_scrap", "plant_starch"],
	42: ["unsaturated_fat", "plant_starch", "zombie_thread"],
	43: ["grave_moss", "rotten_wood_core", "rusted_scrap"],
	44: ["grave_moss", "unsaturated_fat", "rusted_scrap"],
	45: ["plant_starch", "grave_moss", "nut_fragments"],
	46: ["rusted_scrap", "unsaturated_fat", "zombie_thread"],
	47: ["nut_fragments", "rusted_scrap", "zombie_thread"],
	48: ["explosive_seed", "rusted_scrap", "rotten_wood_core"],
	49: ["explosive_seed", "plant_starch", "grave_moss"],
}

static func recipe_id(plant_type: int) -> String:
	if not INGREDIENTS.has(plant_type):
		return ""
	match plant_type:
		4: return "recipe_wall_nut"
		5: return "recipe_potato_mine"
	return "recipe_p%03d" % plant_type

static func definition(id: String) -> Dictionary:
	for plant_type: int in INGREDIENTS:
		if recipe_id(plant_type) == id:
			return {"id": id, "plant_type": plant_type,
				"materials": INGREDIENTS[plant_type].duplicate(), "coin": COST}
	return {}

static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for plant_type: int in INGREDIENTS:
		ids.append(recipe_id(plant_type))
	return ids
