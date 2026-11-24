## 装备的只读内容定义；不保存玩家持有、装配或战斗运行状态。
extends Resource
class_name EquipmentDefinition

## 六种专用槽位；数值顺序也是角色面板的展示顺序。
enum Slot { OUTFIT, EXPERIENCE, LOOT, BADGE, SUN_COLLECTOR, DROP_COLLECTOR }
## 有效期按每 24 小时为一天计算。
const SECONDS_PER_DAY: int = 86400
## 跨版本稳定的内容标识。
@export var id: StringName
## 玩家可见名称。
@export var display_name: String
## 效果及使用范围说明。
@export_multiline var description: String
## 唯一可装配槽位。
@export var slot: Slot = Slot.OUTFIT
## 背包与装备槽使用的图标；时装也用它展示档案头像和预览。
@export var icon: Texture2D
## 时装全身立绘；非时装不设置。
@export var portrait: Texture2D
## 可选的角色主动技能 ID；留空表示此时装暂未设计技能，不预加载技能或修改玩家存档。
@export var active_skill_id: StringName = &""
## 新获得的装备有效天数，0 表示永久；已有期限的实例保留原到期时间。
@export_range(0, 365) var lifetime_days: int = 0
## 已发行的收藏编号与对应铭文；保留旧编号以支持读档，空字典表示普通装备。
@export var edition_inscriptions: Dictionary[int, String] = {}
## 经验奖励倍率，1 表示不改变。
@export_range(1.0, 10.0) var experience_multiplier: float = 1.0
## 随机材料/消耗品数量倍率；不作用于首通、保底补发或任务物品。
@export_range(1, 10) var loot_multiplier: int = 1
## 随机材料/消耗品概率的相对倍率；最终概率限制到 1。
@export_range(1.0, 10.0) var drop_chance_multiplier: float = 1.0
## 随机材料概率的额外相对倍率；固定奖励与保底不受影响。
@export_range(1.0, 11.0) var material_drop_chance_multiplier: float = 1.0
## 冒险战斗中击杀掉落钱币的相对概率倍率；最终概率限制到 1。
@export_range(1.0, 11.0) var coin_drop_chance_multiplier: float = 1.0
## 战场金币价值倍率；不影响任务、退款和首通金币。
@export_range(1.0, 10.0) var coin_multiplier: float = 1.0

## 返回配置是否完整；时装须提供头像和全身立绘。
func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and Slot.values().has(slot) \
		and icon != null and (slot != Slot.OUTFIT or portrait != null) \
		and (slot == Slot.OUTFIT or active_skill_id.is_empty()) and str(active_skill_id).length() <= 128 \
		and lifetime_days >= 0 and lifetime_days <= 365 \
		and (lifetime_days == 0 or supports_lifetime()) \
		and (edition_inscriptions.is_empty() or (slot == Slot.BADGE and lifetime_days == 0)) \
		and is_finite(experience_multiplier) and experience_multiplier >= 1.0 and experience_multiplier <= 10.0 \
		and loot_multiplier >= 1 and loot_multiplier <= 10 \
		and is_finite(drop_chance_multiplier) and drop_chance_multiplier >= 1.0 and drop_chance_multiplier <= 10.0 \
		and is_finite(material_drop_chance_multiplier) and material_drop_chance_multiplier >= 1.0 and material_drop_chance_multiplier <= 11.0 \
		and is_finite(coin_drop_chance_multiplier) and coin_drop_chance_multiplier >= 1.0 and coin_drop_chance_multiplier <= 11.0 \
		and is_finite(coin_multiplier) and coin_multiplier >= 1.0 and coin_multiplier <= 10.0

## 这些槽位支持有期限的实例，已有实例期限与当前配置天数独立。
func supports_lifetime() -> bool:
	return slot in [Slot.EXPERIENCE, Slot.LOOT, Slot.SUN_COLLECTOR, Slot.DROP_COLLECTOR]
