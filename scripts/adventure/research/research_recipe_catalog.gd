## One recipe per registered regular plant; each consumes one scroll and 2-3 distinct units.
## IDs are stable save keys. This table determines ingredients, not stage drops.
extends RefCounted
class_name AdventureRecipeCatalog

const COST := 2000
const INGREDIENTS: Dictionary = {
	1: ["pea_stem", "pea_pod"],
	2: ["sun_nectar", "flower_pollen"],
	3: ["explosive_seed", "ember_resin", "fruit_pulp"],
	4: ["nut_fragments", "unsaturated_fat"],
	5: ["explosive_seed", "plant_starch", "plant_fiber"],
	6: ["pea_stem", "pea_pod", "frost_crystal"],
	7: ["plant_fiber", "nut_fragments"],
	8: ["pea_stem", "pea_pod", "plant_starch"],
	9: ["fungal_spores", "rotten_wood_core"],
	10: ["fungal_spores", "sun_nectar"],
	11: ["fungal_spores", "grave_moss"],
	12: ["rotten_wood_core", "grave_moss"],
	13: ["fungal_spores", "grave_moss", "zombie_thread"],
	14: ["fungal_spores", "zombie_thread"],
	15: ["fungal_spores", "frost_crystal", "grave_moss"],
	16: ["fungal_spores", "explosive_seed", "ember_resin"],
	17: ["aquatic_fiber", "plant_fiber"],
	18: ["fruit_pulp", "plant_starch"],
	19: ["pea_stem", "pea_pod", "plant_fiber"],
	20: ["aquatic_fiber", "plant_fiber", "zombie_thread"],
	21: ["explosive_seed", "ember_resin", "plant_starch"],
	22: ["thorn_spine", "rusted_scrap"],
	23: ["rotten_wood_core", "ember_resin", "plant_fiber"],
	24: ["nut_fragments", "unsaturated_fat", "plant_fiber"],
	25: ["fungal_spores", "aquatic_fiber"],
	26: ["sun_nectar", "leaf_membrane"],
	27: ["thorn_spine", "plant_starch"],
	28: ["leaf_membrane", "plant_fiber", "flower_pollen"],
	29: ["pea_stem", "plant_fiber"],
	30: ["fruit_pulp", "flower_pollen"],
	31: ["fruit_pulp", "nut_fragments"],
	32: ["fungal_spores", "rusted_scrap"],
	33: ["launch_vine", "plant_fiber"],
	34: ["rotten_wood_core", "rusted_scrap"],
	35: ["launch_vine", "unsaturated_fat"],
	36: ["plant_starch", "sun_nectar"],
	37: ["plant_starch", "plant_fiber"],
	38: ["leaf_membrane", "plant_fiber"],
	39: ["flower_pollen", "plant_starch"],
	40: ["launch_vine", "fruit_pulp", "plant_fiber"],
	41: ["explosive_seed", "rusted_scrap", "plant_starch"],
	42: ["unsaturated_fat", "plant_starch", "zombie_thread"],
	43: ["grave_moss", "rotten_wood_core", "rusted_scrap"],
	44: ["grave_moss", "unsaturated_fat", "rusted_scrap"],
	45: ["plant_starch", "grave_moss", "nut_fragments"],
	46: ["rusted_scrap", "unsaturated_fat", "zombie_thread"],
	47: ["nut_fragments", "rusted_scrap", "zombie_thread"],
	48: ["explosive_seed", "rusted_scrap", "rotten_wood_core"],
	49: ["pea_stem", "pea_pod", "leaf_membrane"],
	50: ["aquatic_fiber", "charge_crystal"],
	51: ["plant_fiber", "flower_pollen"],
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
