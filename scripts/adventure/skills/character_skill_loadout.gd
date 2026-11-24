## 为已载入档案解析时装或初始人物的主动技能；不改变装备状态或玩家存档。
extends RefCounted
class_name CharacterSkillLoadout

## 未装配有效时装时使用的初始人物技能。
const DEFAULT_SKILL_ID: StringName = &"default_farmer_refresh"

## [param equipment] 是已载入档案的装备状态；有有效时装时使用它的技能配置。
## 没有有效时装时，角色与档案界面一样回到初始园丁。
static func active_skill_id(equipment: PlayerEquipmentState) -> StringName:
	if equipment == null:
		return DEFAULT_SKILL_ID
	var uid: String = str(equipment.equipped.get("outfit", "")) # 只读取时装槽对应的持有实例。
	if uid.is_empty() or not equipment.owned.has(uid) \
			or equipment.is_expired(uid, int(Time.get_unix_time_from_system())):
		return DEFAULT_SKILL_ID
	var item_id: StringName = StringName(str(equipment.owned[uid])) # 档案只存装备内容 ID，不保存路径。
	var item: EquipmentDefinition = EquipmentCatalog.definition(item_id) # 按需读取已有合法时装资源。
	return item.active_skill_id if item != null and item.slot == EquipmentDefinition.Slot.OUTFIT else DEFAULT_SKILL_ID
