extends Node
class_name ItemRegistry

## 第一阶段静态道具目录；稳定 ID 不随显示名称改变，不持有玩家数量。
const ITEMS: Dictionary = {
	"unsaturated_fat": {"name": "不饱和脂肪", "category": "material"},
	"nut_fragments": {"name": "坚果碎块", "category": "material"},
	"explosive_seed": {"name": "爆炸种子", "category": "material"},
	"plant_starch": {"name": "植物淀粉", "category": "material"},
	"rotten_wood_core": {"name": "腐朽木芯", "category": "material"},
	"rusted_scrap": {"name": "锈蚀铁片", "category": "material"},
	"grave_moss": {"name": "墓地苔藓", "category": "material"},
	"zombie_thread": {"name": "僵尸线头", "category": "material"},
	"recipe_wall_nut": {"name": "坚果墙一次性制作书", "category": "recipe"},
	"recipe_potato_mine": {"name": "土豆雷一次性制作书", "category": "recipe"},
	"lawn_nightmare_key": {"name": "草坪噩梦挑战钥匙", "category": "key"},
	"zombie_island.fallen_camp.nightmare_key": {"name": "没落营地噩梦挑战钥匙", "category": "key"},
	"zombie_island.grave_upstream.nightmare_key": {"name": "墓地上游噩梦挑战钥匙", "category": "key"},
	"zombie_island.grave_downstream.nightmare_key": {"name": "墓地下游噩梦挑战钥匙", "category": "key"},
	"zombie_island.sewer.nightmare_key": {"name": "下水道噩梦挑战钥匙", "category": "key"},
	"zombie_island.edgar_temple.nightmare_key": {"name": "埃德加神殿噩梦挑战钥匙", "category": "key"},
	"seedling_pot": {"name": "育苗花盆", "category": "consumable"},
	"growth_agent": {"name": "生长剂", "category": "consumable"},
	"fertilizer_lv1": {"name": "一级肥料", "category": "consumable"},
	"fertilizer_lv2": {"name": "二级肥料", "category": "consumable"},
	"fertilizer_lv3": {"name": "三级肥料", "category": "consumable"},
	"fertilizer_lv4": {"name": "四级肥料", "category": "consumable"},
	"fertilizer_lv5": {"name": "五级肥料", "category": "consumable"},
}

## 返回 [param item_id] 是否属于当前静态目录，不读取或创建库存。
static func has_item(item_id: String) -> bool:
	return ITEMS.has(item_id)

## 返回 [param item_id] 的定义副本，未知 ID 返回空字典。
static func get_item_definition(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {}).duplicate(true)
