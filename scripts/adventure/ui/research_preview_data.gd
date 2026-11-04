## Static presentation contract. Replace this adapter when lab rules become authoritative.
## This module never reads or writes player progression.
extends RefCounted

const MODES := ["craft", "upgrade", "promotion"]
const TITLES := {"craft": "合成", "upgrade": "强化", "promotion": "转职"}
const ENTRIES := {
	"craft": [
		{"title": "坚果墙制作书", "type": CharacterRegistry.PlantType.P004WallNut,
			"materials": ["nut_fragments", "unsaturated_fat"]},
		{"title": "土豆雷制作书", "type": CharacterRegistry.PlantType.P005PotatoMine,
			"materials": ["explosive_seed", "plant_starch"]}
	],
	"upgrade": [
		{"title": "向日葵", "type": CharacterRegistry.PlantType.P002SunFlower},
		{"title": "豌豆射手", "type": CharacterRegistry.PlantType.P001PeaShooterSingle},
		{"title": "坚果墙", "type": CharacterRegistry.PlantType.P004WallNut}
	],
	"promotion": [
		{"title": "豌豆射手", "type": CharacterRegistry.PlantType.P001PeaShooterSingle},
		{"title": "向日葵", "type": CharacterRegistry.PlantType.P002SunFlower},
		{"title": "坚果墙", "type": CharacterRegistry.PlantType.P004WallNut}
	]
}
const MATERIAL_LABELS := {
	"nut_fragments": "坚果碎块", "unsaturated_fat": "不饱和脂肪",
	"explosive_seed": "爆炸种子", "plant_starch": "植物淀粉"
}
const ITEM_ROOT := "res://assets/adventure/ui/items/materials/"

static func records(mode: String) -> Array:
	return ENTRIES.get(mode, [])

static func title(mode: String) -> String:
	return TITLES.get(mode, "")
