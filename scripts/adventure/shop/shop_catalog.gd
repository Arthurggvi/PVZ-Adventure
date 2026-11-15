## 商店唯一商品目录；价格、发货类型与分类不由界面或存档指定。
extends RefCounted

## 初始可携带卡槽；旧档未购买时沿用六槽。
const BASE_SLOTS := 6
## 商店最多出售五次扩容。
const MAX_SLOTS := 11
## 固定分类顺序，界面按此生成页签。
const CATEGORIES: Array[String] = ["daily", "permanent", "special"]
## 分类中文名。
const CATEGORY_NAMES: Dictionary = {"daily": "每日商品", "permanent": "常驻商品", "special": "特殊商品"}
## 商品配置：item 发普通背包，equipment 发角色装备，slots 扩容，glove 解锁战斗工具。
const PRODUCTS: Array[Dictionary] = [
	{"id": "seedling_pot", "category": "daily", "kind": "item", "asset": "seedling_pot", "title": "保育花盆", "price": 5000, "daily_limit": 2,
		"tag": "强化保护", "description": "强化失败时，保留主卡原有星级。", "speech": "强化失败不掉星，稳当！"},
	{"id": "growth_agent_lv5", "category": "daily", "kind": "item", "asset": "growth_agent_lv5", "title": "5级生长剂", "price": 100000, "daily_limit": 1,
		"tag": "必成强化", "description": "4星主卡强化至5星时，成功率直接变为100%；仍需正常耗材与金币。", "speech": "四星升五星，一瓶稳成！"},
	{"id": "fertilizer_lv5", "category": "daily", "kind": "item", "asset": "fertilizer_lv5", "title": "5级肥料", "price": 100000, "daily_limit": 1,
		"tag": "强化助力", "description": "研究室强化时，本次成功率变为原来的1.5倍，最高100%。", "speech": "强化成功率，变成1.5倍！"},
	{"id": "drop_collector", "category": "permanent", "kind": "equipment", "asset": "drop_collector", "title": "物品自动收集器", "price": 5000,
		"tag": "7天有效", "description": "装备后在冒险战斗中自动收集掉落物品。", "speech": "地上的宝贝，它替你捡。"},
	{"id": "sun_collector", "category": "permanent", "kind": "equipment", "asset": "sun_collector", "title": "阳光自动收集器", "price": 5000,
		"tag": "7天有效", "description": "装备后在冒险战斗中自动收集阳光。", "speech": "阳光自己进兜，多省心！"},
	{"id": "double_experience", "category": "permanent", "kind": "equipment", "asset": "double_experience", "title": "双倍经验卡", "price": 5000,
		"tag": "7天有效", "description": "装备后获得的经验变为2倍。", "speech": "一趟冒险，双倍经验！"},
	{"id": "double_loot", "category": "permanent", "kind": "equipment", "asset": "double_loot", "title": "双倍掉落卡", "price": 5000,
		"tag": "7天有效", "description": "冒险随机材料和消耗品的掉落数量变为2倍，不影响首通、保底和任务物品。", "speech": "随机掉落，一份变两份！"},
	{"id": "spring_cattail", "category": "special", "kind": "equipment", "asset": "spring_cattail", "title": "小璐", "price": 50000, "unique": true,
		"tag": "永久时装", "description": "解锁新春小璐时装；在角色页装备，切换角色立绘。", "speech": "小璐的新春装，喜庆！"},
	{"id": "sunflower_girl", "category": "special", "kind": "equipment", "asset": "sunflower_girl", "title": "向日葵娘", "price": 50000, "unique": true,
		"tag": "永久时装", "description": "解锁向日葵娘时装；在角色页装备，切换角色立绘。", "speech": "换上向日葵娘，满身阳光！"},
	{"id": "card_slot", "category": "special", "kind": "slots", "asset": "", "title": "可携带卡槽 +1", "price": 3000,
		"tag": "永久升级", "description": "永久增加一个冒险可携带卡槽，上限11槽。每次购买后价格翻倍。", "speech": "永久多带一张卡！"},
	{"id": "glove", "category": "special", "kind": "glove", "asset": "", "title": "手套", "price": 20000,
		"description": "在冒险战斗中移动植物。", "speech": "先选植物，再选落点。"},
]

## 返回 [param id] 的独立商品定义；未知 ID 返回空字典。
static func product(id: String) -> Dictionary:
	for entry: Dictionary in PRODUCTS: # 目录顺序也决定货架顺序。
		if entry.id == id:
			return entry.duplicate(true)
	return {}

## 返回 [param category] 的稳定商品 ID 列表。
static func ids(category: String) -> Array[String]:
	var result: Array[String] = [] # 不向表现层暴露可变静态目录。
	for entry: Dictionary in PRODUCTS: # 新增同类商品自动出现在货架。
		if entry.category == category:
			result.append(str(entry.id))
	return result

## 返回当前 [param slots] 的扩容价格；满槽或非法容量返回零。
static func slot_price(slots: int) -> int:
	return 3000 * (1 << (slots - BASE_SLOTS)) if slots >= BASE_SLOTS and slots < MAX_SLOTS else 0
