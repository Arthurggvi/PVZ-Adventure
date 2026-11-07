## 明确列出可用装备；资源仅由目录持有，对外返回副本，避免共享配置被运行态修改。
extends RefCounted
class_name EquipmentCatalog

## 槽位显示名，与 EquipmentDefinition.Slot 对齐。
const SLOT_NAMES: PackedStringArray = ["时装", "经验卡", "掉落卡", "徽章", "阳光收集器", "掉落收集器"]
## 静态资源列表；新增装备只需增加定义和目录项。
const DEFINITIONS: Array[Resource] = [
	preload("res://resources/adventure/equipment/deepseek_whale.tres"),
	preload("res://resources/adventure/equipment/sunflower_girl.tres"),
	preload("res://resources/adventure/equipment/spring_cattail.tres"),
	preload("res://resources/adventure/equipment/double_experience.tres"),
	preload("res://resources/adventure/equipment/double_loot.tres"),
	preload("res://resources/adventure/equipment/adventurer_badge.tres"),
	preload("res://resources/adventure/equipment/lucky_badge.tres"),
	preload("res://resources/adventure/equipment/coin_badge.tres"),
	preload("res://resources/adventure/equipment/sun_collector.tres"),
	preload("res://resources/adventure/equipment/drop_collector.tres"),
]

## 按 [param id] 返回独立定义；未知或非法定义返回 null。
static func definition(id: StringName) -> EquipmentDefinition:
	for entry: EquipmentDefinition in DEFINITIONS: # 内容目录规模小，保持确定性顺序。
		if entry.id == id and entry.is_valid():
			return entry.duplicate() as EquipmentDefinition
	return null

## 返回全部有效内容副本，供获取来源选择装备；不暴露共享资源。
static func definitions() -> Array[EquipmentDefinition]:
	var result: Array[EquipmentDefinition] = [] # 保持目录顺序。
	for entry: EquipmentDefinition in DEFINITIONS: # 每个调用方持有独立定义副本。
		if entry.is_valid():
			result.append(entry.duplicate() as EquipmentDefinition)
	return result

## 返回 [param slot] 的稳定存档键；非法槽位返回空字符串。
static func slot_key(slot: int) -> String:
	return ["outfit", "experience", "loot", "badge", "sun_collector", "drop_collector"][slot] \
		if slot >= 0 and slot < SLOT_NAMES.size() else ""
