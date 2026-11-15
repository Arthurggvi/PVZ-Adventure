## 冒险战场首屏的动态依赖清单；从现有注册表读取路径，不拥有第二份资源缓存。
extends RefCounted

## 只复用库存快照的纯路径查询，不依赖任何窗口或预览实例。
const ResourcePaths = preload("res://scripts/adventure/ui/ui_resource_paths.gd")

## 汇总 [param level] 进入选卡及僵尸预览所需资源；本函数只查询元数据。
static func paths(level: ResourceLevelData) -> PackedStringArray:
	var result := PackedStringArray([
		"res://scenes/card_slot/card_slot_norm.tscn",
		"res://assets/audio/BGM/choose_card.mp3",
	]) # 当前冒险适配器使用普通选卡；其它模式仍由各自入口声明。
	result.append(SceneRegistry.PATHS[&"CARD_CANDIDATE_CONTAINER"])
	result.append(ConstLevelData.GameBGMMap[level.game_BGM])
	result.append(ConstLevelData.GameBGMMap[ConstLevelData.GameBGM.Boss])
	var cards: Array[Dictionary] = Global.adventure_inventory.list_cards() # 同一快照覆盖卡面、星章和最高转职外观。
	ResourcePaths.inventory_rows(result, cards)
	for card: Dictionary in cards: # 费用条件与动态外观采用同一批库存快照。
		var plant_type: int = int(card["plant_type"]) # 卡实例身份对应的植物元数据。
		var info: Dictionary = Global.character_registry.PlantInfo.get(plant_type, {}) # 费用读取不需要角色场景。
		_append_path(result, info.get(CharacterRegistry.PlantInfoAttribute.PlantConditionResource, ""))
	for zombie_type: int in level.zombie_refresh_types: # 只准备当前阶段实际展示的物种。
		var info: Dictionary = Global.character_registry.ZombieInfo.get(zombie_type, {}) # 原注册表仍是唯一身份权威。
		_append_path(result, info.get(CharacterRegistry.ZombieInfoAttribute.ZombieScenes, ""))
	return result

## 将 [param value] 的有效非空资源路径追加到 [param target]，不触发资源解析。
static func _append_path(target: PackedStringArray, value: Variant) -> void:
	if value is String and not value.is_empty() and not target.has(value):
		target.append(value)
