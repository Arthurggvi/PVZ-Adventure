## 装备权威注册表：只保存资源路径，按实际使用的 ID 惰性加载定义与贴图。
extends RefCounted
class_name EquipmentCatalog

## 槽位顺序与 EquipmentDefinition.Slot 的枚举值一致。
const SLOT_NAMES: PackedStringArray = ["时装", "经验卡", "掉落卡", "徽章", "阳光收集器", "掉落收集器"]
## 唯一内容注册表：顺序决定定义枚举顺序；注册并不代表商店上架或自动发放。
const DEFINITION_PATHS: Dictionary = {
	&"deepseek_whale": "res://resources/adventure/equipment/deepseek_whale.tres",
	&"sunflower_girl": "res://resources/adventure/equipment/sunflower_girl.tres",
	&"spring_cattail": "res://resources/adventure/equipment/spring_cattail.tres",
	&"rainy_postman_miro": "res://resources/adventure/equipment/rainy_postman_miro.tres",
	&"midnight_clockmaker_koro": "res://resources/adventure/equipment/midnight_clockmaker_koro.tres",
	&"unemployed_reaper_moi": "res://resources/adventure/equipment/unemployed_reaper_moi.tres",
	&"glass_sea_diver_bubble": "res://resources/adventure/equipment/glass_sea_diver_bubble.tres",
	&"snow_train_conductor_eve": "res://resources/adventure/equipment/snow_train_conductor_eve.tres",
	&"don_quixote_lancer": "res://resources/adventure/equipment/don_quixote_lancer.tres",
	&"tiramisu_flower_crown": "res://resources/adventure/equipment/tiramisu_flower_crown.tres",
	&"double_experience": "res://resources/adventure/equipment/double_experience.tres",
	&"double_loot": "res://resources/adventure/equipment/double_loot.tres",
	&"adventurer_badge": "res://resources/adventure/equipment/adventurer_badge.tres",
	&"lucky_badge": "res://resources/adventure/equipment/lucky_badge.tres",
	&"coin_badge": "res://resources/adventure/equipment/coin_badge.tres",
	&"valhalla_temple_light": "res://resources/adventure/equipment/valhalla_temple_light.tres",
	&"beloved_badge": "res://resources/adventure/equipment/beloved_badge.tres",
	&"sun_collector": "res://resources/adventure/equipment/sun_collector.tres",
	&"drop_collector": "res://resources/adventure/equipment/drop_collector.tres",
}

## 按 [param id] 惰性获取并复制有效装备；未知 ID 不加载文件，返回 null。
static func definition(id: StringName) -> EquipmentDefinition:
	if not DEFINITION_PATHS.has(id):
		return null
	var path: String = DEFINITION_PATHS[id] # 只从注册表取路径，不接受玩家存档注入任意资源路径。
	var entry: EquipmentDefinition = load(path) as EquipmentDefinition # 由 Godot 的资源缓存复用已经加载的配置。
	if entry == null or entry.id != id or not entry.is_valid():
		return null
	var copy: EquipmentDefinition = entry.duplicate() as EquipmentDefinition # 图标等资源继续使用 Godot 缓存。
	if not entry.edition_inscriptions.is_empty():
		copy.edition_inscriptions = entry.edition_inscriptions.duplicate()
	return copy

## 遍历全部有效装备内容副本；此操作显式请求完整目录，可能加载全部时装贴图。
static func definitions() -> Array[EquipmentDefinition]:
	var result: Array[EquipmentDefinition] = [] # 遵循注册表的稳定显示顺序。
	for id: StringName in DEFINITION_PATHS: # 定义顺序与原资源列表一致。
		var item: EquipmentDefinition = definition(id) # 单独返回副本，不暴露共享资源。
		if item != null:
			result.append(item)
	return result

## 返回 [param slot] 的稳定存档键；非法槽位返回空字符串。
static func slot_key(slot: int) -> String:
	return ["outfit", "experience", "loot", "badge", "sun_collector", "drop_collector"][slot] \
		if slot >= 0 and slot < SLOT_NAMES.size() else ""
