extends Node
class_name ItemRegistry

## 肥料级别从 1 开始，名称按此顺序生成。
const FERTILIZER_NAMES := ["一级", "二级", "三级", "四级", "五级"]
## 转职阶数从 1 开始，技能名称和阶数取自转职目录。
const PROMOTION_NAMES := ["一转", "二转", "三转", "四转"]
## 五档生长剂的稳定 ID，数组索引对应主卡零至四星；其他等级无保底道具。
const GROWTH_AGENT_IDS := ["growth_agent_lv1", "growth_agent_lv2", "growth_agent_lv3",
	"growth_agent_lv4", "growth_agent_lv5"]

## 基础物品定义，不持有玩家数量；技能书自动从转职目录汇总，无须在此重复登记。
const BASE_ITEMS: Dictionary = {
	"unsaturated_fat": {"name": "不饱和脂肪", "category": "material",
		"description": "从坚果中提取的油脂，常用来调和植物配方。"},
	"nut_fragments": {"name": "坚果碎块", "category": "material",
		"description": "从坚果外壳上脱落的碎块，小小一片也很结实。"},
	"explosive_seed": {"name": "爆炸种子", "category": "material",
		"description": "蕴含着不稳定能量的种子。"},
	"plant_starch": {"name": "植物淀粉", "category": "material",
		"description": "从植物根茎中提取的细粉，遇水后能把材料黏合起来。"},
	"rotten_wood_core": {"name": "腐朽木芯", "category": "material",
		"description": "腐木内部残留的木芯，还带着潮湿泥土的气味。"},
	"rusted_scrap": {"name": "锈蚀铁片", "category": "material",
		"description": "从旧铁器上掉下来的碎片，锈层底下仍有坚硬的铁。"},
	"grave_moss": {"name": "墓地苔藓", "category": "material",
		"description": "长在墓碑背阴处的苔藓，摘下来后仍带着潮气。"},
	"zombie_thread": {"name": "僵尸线头", "category": "material",
		"description": "从僵尸破衣上扯下的线头，看着松散，拉起来却很结实。"},
	"pea_stem": {"name": "豌豆茎", "category": "material",
		"description": "豌豆植株上富有韧性的嫩茎，卷曲的藤须仍能牢牢抓住周围的东西。"},
	"pea_pod": {"name": "豌豆荚", "category": "material",
		"description": "饱满的绿色豆荚，里面的豌豆圆润结实，适合培育射击植物。"},
	"sun_nectar": {"name": "日光花蜜", "category": "material",
		"description": "向阳花朵积攒的金黄蜜液，装在瓶中仍透出暖暖的光泽。"},
	"fungal_spores": {"name": "真菌孢子", "category": "material",
		"description": "从蘑菇菌褶间收集的细小孢子，稍有风吹便会四散飘落。"},
	"frost_crystal": {"name": "霜晶粉", "category": "material",
		"description": "由寒霜凝成的细碎晶粉，摸上去冰凉，能够让植物带上寒气。"},
	"ember_resin": {"name": "炽热树脂", "category": "material",
		"description": "从灼热树木上凝结的红色树脂，冷却后内部仍隐约闪着火光。"},
	"aquatic_fiber": {"name": "水生纤维", "category": "material",
		"description": "从水草和湿润茎叶中剥离的柔韧纤维，离开水面也不易断裂。"},
	"charge_crystal": {"name": "电荷晶核", "category": "material",
		"description": "积蓄着微弱电流的晶体，能让柔韧的植物茎叶导引闪电。"},
	"plant_fiber": {"name": "植物纤维", "category": "material",
		"description": "晒干后捆扎成束的植物纤维，轻巧结实，可用于固定植物的根茎。"},
	"thorn_spine": {"name": "棘刺", "category": "material",
		"description": "从多刺植物上采下的尖硬棘刺，末端锋利，收拾时可得小心。"},
	"flower_pollen": {"name": "花粉", "category": "material",
		"description": "从盛开的花朵间采集的金色细粉，散发着淡淡的花香。"},
	"fruit_pulp": {"name": "果肉精华", "category": "material",
		"description": "从成熟果实中榨取的浓稠果肉，保留了果实最充沛的养分。"},
	"launch_vine": {"name": "弹射藤", "category": "material",
		"description": "富有弹性的卷曲藤蔓，弯折后会迅速弹回原状。"},
	"leaf_membrane": {"name": "叶膜", "category": "material",
		"description": "从宽大的叶片上分离出的薄膜，柔软透光，又能挡住细雨。"},
	"recipe_wall_nut": {"subject": "坚果墙", "category": "recipe"},
	"recipe_potato_mine": {"subject": "土豆雷", "category": "recipe"},
	"recipe_p001": {"subject": "豌豆射手", "category": "recipe"},
	"recipe_p002": {"subject": "向日葵", "category": "recipe"},
	"recipe_p003": {"subject": "樱桃炸弹", "category": "recipe"},
	"recipe_p006": {"subject": "寒冰射手", "category": "recipe"},
	"recipe_p007": {"subject": "大嘴花", "category": "recipe"},
	"recipe_p008": {"subject": "双发射手", "category": "recipe"},
	"recipe_p009": {"subject": "小喷菇", "category": "recipe"},
	"recipe_p010": {"subject": "阳光菇", "category": "recipe"},
	"recipe_p011": {"subject": "大喷菇", "category": "recipe"},
	"recipe_p012": {"subject": "墓碑吞噬者", "category": "recipe"},
	"recipe_p013": {"subject": "魅惑菇", "category": "recipe"},
	"recipe_p014": {"subject": "胆小菇", "category": "recipe"},
	"recipe_p015": {"subject": "寒冰菇", "category": "recipe"},
	"recipe_p016": {"subject": "毁灭菇", "category": "recipe"},
	"recipe_p017": {"subject": "睡莲", "category": "recipe"},
	"recipe_p018": {"subject": "窝瓜", "category": "recipe"},
	"recipe_p019": {"subject": "三线射手", "category": "recipe"},
	"recipe_p020": {"subject": "缠绕水草", "category": "recipe"},
	"recipe_p021": {"subject": "火爆辣椒", "category": "recipe"},
	"recipe_p022": {"subject": "地刺", "category": "recipe"},
	"recipe_p023": {"subject": "火炬树桩", "category": "recipe"},
	"recipe_p024": {"subject": "高坚果", "category": "recipe"},
	"recipe_p025": {"subject": "海蘑菇", "category": "recipe"},
	"recipe_p026": {"subject": "路灯花", "category": "recipe"},
	"recipe_p027": {"subject": "仙人掌", "category": "recipe"},
	"recipe_p028": {"subject": "三叶草", "category": "recipe"},
	"recipe_p029": {"subject": "裂荚射手", "category": "recipe"},
	"recipe_p030": {"subject": "杨桃", "category": "recipe"},
	"recipe_p031": {"subject": "南瓜头", "category": "recipe"},
	"recipe_p032": {"subject": "磁力菇", "category": "recipe"},
	"recipe_p033": {"subject": "卷心菜投手", "category": "recipe"},
	"recipe_p034": {"subject": "花盆", "category": "recipe"},
	"recipe_p035": {"subject": "玉米投手", "category": "recipe"},
	"recipe_p036": {"subject": "咖啡豆", "category": "recipe"},
	"recipe_p037": {"subject": "大蒜", "category": "recipe"},
	"recipe_p038": {"subject": "叶子保护伞", "category": "recipe"},
	"recipe_p039": {"subject": "金盏花", "category": "recipe"},
	"recipe_p040": {"subject": "西瓜投手", "category": "recipe"},
	"recipe_p041": {"subject": "机枪射手", "category": "recipe"},
	"recipe_p042": {"subject": "双子向日葵", "category": "recipe"},
	"recipe_p043": {"subject": "忧郁菇", "category": "recipe"},
	"recipe_p044": {"subject": "香蒲", "category": "recipe"},
	"recipe_p045": {"subject": "冰西瓜", "category": "recipe"},
	"recipe_p046": {"subject": "吸金磁", "category": "recipe"},
	"recipe_p047": {"subject": "地刺王", "category": "recipe"},
	"recipe_p048": {"subject": "玉米加农炮", "category": "recipe"},
	"recipe_p049": {"subject": "反向双发射手", "category": "recipe"},
	"recipe_p050": {"subject": "闪电芦苇", "category": "recipe"},
	"recipe_p051": {"subject": "回旋镖射手", "category": "recipe"},
	"lawn_nightmare_key": {"subject": "草坪", "category": "key"},
	"zombie_island.fallen_camp.nightmare_key": {"subject": "没落营地", "category": "key"},
	"zombie_island.grave_upstream.nightmare_key": {"subject": "墓地上游", "category": "key"},
	"zombie_island.grave_downstream.nightmare_key": {"subject": "墓地下游", "category": "key"},
	"zombie_island.sewer.nightmare_key": {"subject": "下水道", "category": "key"},
	# 沿用旧钥匙的存档 ID，已有库存直接显示为上半把。
	"zombie_island.edgar_temple.nightmare_key": {"name": "埃德加钥匙（上）", "category": "key",
		"description": "击败没落营地的黑将军可获得。可以开启埃德加神殿的噩梦挑战。"},
	"zombie_island.edgar_temple.nightmare_key_lower": {"name": "埃德加钥匙（下）", "category": "key",
		"description": "埃德加钥匙的下半部分。击败墓地下游的白爵士可获得。"},
	"seedling_pot": {"name": "育苗花盆", "category": "consumable",
		"description": "在研究室强化时使用。强化失败后保留主卡原有星级。"},
	"growth_agent_lv1": {"growth_agent_level": 1, "category": "consumable"},
	"growth_agent_lv2": {"growth_agent_level": 2, "category": "consumable"},
	"growth_agent_lv3": {"growth_agent_level": 3, "category": "consumable"},
	"growth_agent_lv4": {"growth_agent_level": 4, "category": "consumable"},
	"growth_agent_lv5": {"growth_agent_level": 5, "category": "consumable"},
	"fertilizer_lv1": {"fertilizer_level": 1, "category": "consumable"},
	"fertilizer_lv2": {"fertilizer_level": 2, "category": "consumable"},
	"fertilizer_lv3": {"fertilizer_level": 3, "category": "consumable"},
	"fertilizer_lv4": {"fertilizer_level": 4, "category": "consumable"},
	"fertilizer_lv5": {"fertilizer_level": 5, "category": "consumable"},
}

## 基础物品与转职书共用同一物品目录；转职书自动取自权威技能目录。
static var ITEMS: Dictionary = _build_items()

## 返回含全部转职书的目录，后续新书不再重复手工登记。
static func _build_items() -> Dictionary:
	var items: Dictionary = BASE_ITEMS.duplicate(true) # 构造时复制，保留基础物品定义不变。
	for book_id: String in AdventurePromotionCatalog.BOOKS: # 技能书存在即能被背包、研究室和修改器识别。
		items[book_id] = {"category": "promotion_book"}
	return items

## 返回 [param item_id] 是否属于当前静态目录，不读取或创建库存。
static func has_item(item_id: String) -> bool:
	return ITEMS.has(item_id)

## 返回 [param item_id] 的定义副本，未知 ID 返回空字典。
static func get_item_definition(item_id: String) -> Dictionary:
	var definition: Dictionary = ITEMS.get(item_id, {}).duplicate(true) # 调用方可读写副本，不影响目录。
	match definition.get("category", ""):
		"recipe":
			definition["name"] = "配方-%s" % definition.subject
			definition["description"] = "记载着制作%s的方法。收集所需材料后，可以在研究室合成这张植物卡。" % definition.subject
		"key":
			if definition.has("subject"):
				definition["name"] = "钥匙-%s" % definition.subject
				definition["description"] = "可以打开%s深处的大门，开启精英挑战。" % definition.subject
		"promotion_book":
			var skill: Dictionary = AdventurePromotionCatalog.definition(item_id) # 技能标题与效果共用同一份定义。
			var tier: int = int(skill.get("tier", 0)) # 阶数同时用于命名和文字颜色。
			if tier >= 1 and tier <= PROMOTION_NAMES.size():
				definition["name"] = "%s技能书-%s" % [PROMOTION_NAMES[tier - 1], skill.title]
				definition["promotion_tier"] = tier
				definition["description"] = skill.summary
		"consumable":
			var level: int = int(definition.get("fertilizer_level", 0)) # 其他消耗品没有肥料级别。
			if level >= 1 and level <= FERTILIZER_NAMES.size():
				definition["name"] = "%s肥料" % FERTILIZER_NAMES[level - 1]
				definition["description"] = "供研究室强化植物卡时使用的%s肥料，可以提高强化成功的机会。" % FERTILIZER_NAMES[level - 1]
			var agent_level: int = int(definition.get("growth_agent_level", 0)) # 仅适用低一级的主卡星级。
			if agent_level >= 1 and agent_level <= GROWTH_AGENT_IDS.size():
				definition["name"] = "%s生长剂" % FERTILIZER_NAMES[agent_level - 1]
				definition["description"] = "研究室强化%d星主卡时使用，成功率直接变为100%%；仍需正常耗材卡及金币。" % (agent_level - 1)
	return definition
