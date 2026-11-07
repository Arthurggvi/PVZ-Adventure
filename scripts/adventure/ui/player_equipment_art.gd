## 角色装备外观唯一映射：仅根据现有装备槽位返回通用底图，业务层不依赖材质。
extends RefCounted

const ROOT := "res://assets/adventure/ui/player/backings/"
const BACKINGS: Dictionary = {
	0: "outfit_backing.png",
	1: "experience_card_backing.png",
	2: "item_card_backing.png",
	3: "item_card_backing.png", # 徽章共用道具卡底图。
	4: "collector_backing.png",
	5: "collector_backing.png",
}

static func backing_uri(slot: int) -> String:
	var filename: String = str(BACKINGS.get(slot, ""))
	return ROOT + filename if not filename.is_empty() else ""
