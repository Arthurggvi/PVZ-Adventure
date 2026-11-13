## Global adventure toolbar metadata; no parallel player progress or saved UI flags.
extends RefCounted
class_name AdventureToolbarFeatures

const ENTRIES: Array[Dictionary] = [
	{"id": "player", "label": "玩家", "asset": "icon_player.png"},
	{"id": "map", "label": "地图", "asset": "icon_map.png"},
	{"id": "inventory", "label": "背包", "asset": "icon_inventory.png"},
	{"id": "quests", "label": "任务", "asset": "icon_quests.png"},
	{"id": "research", "label": "研究室", "asset": "icon_research.png"},
	{"id": "almanac", "label": "图鉴", "asset": "icon_deck.png"},
	{"id": "settings", "label": "设置", "asset": "icon_settings.png"},
]

## 只由场景建筑提供的入口，参与同一权限门面但不重复占用底部工具栏。
const SCENE_FEATURES: Array[String] = ["library"]

## Only existing, selected user profiles may open the canonical adventure entrance.
static func can_open_map() -> bool:
	if Global.user_manager == null or Global.global_game_state == null:
		return false
	var name: String = Global.user_manager.curr_user_name
	return not name.is_empty() and Global.user_manager.all_user_name.has(name) \
		and Global.global_game_state.adventure_state != null

## 查询 [param feature_id] 是否为工具栏或建筑支持的功能。
static func is_known(feature_id: String) -> bool:
	if feature_id in SCENE_FEATURES:
		return true
	for entry: Dictionary in ENTRIES:
		if entry.id == feature_id:
			return true
	return false
