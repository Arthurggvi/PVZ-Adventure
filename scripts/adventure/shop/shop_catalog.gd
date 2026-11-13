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
## 商品配置：item 发普通背包，equipment 发角色装备，slots 扩容；daily_limit 缺省为不限量。
const PRODUCTS: Array[Dictionary] = [
	{"id": "seedling_pot", "category": "daily", "kind": "item", "asset": "seedling_pot", "title": "保育花盆", "price": 5000, "daily_limit": 2,
		"tag": "强化保护", "description": "强化失败时，保留主卡原有星级。", "speech": "给你的宝贝植物套上它！强化失败也能保住原来的星级。每天只有两个，别拿去炖汤！"},
	{"id": "growth_agent_lv5", "category": "daily", "kind": "item", "asset": "growth_agent_lv5", "title": "5级生长剂", "price": 100000, "daily_limit": 1,
		"tag": "必成强化", "description": "4星主卡强化至5星时，成功率直接变为100%；仍需正常耗材与金币。", "speech": "四星长五星？这瓶五级生长剂让成功率直接到百分之百！耗材和金币可还得准备好。"},
	{"id": "fertilizer_lv5", "category": "daily", "kind": "item", "asset": "fertilizer_lv5", "title": "5级肥料", "price": 100000, "daily_limit": 1,
		"tag": "强化助力", "description": "研究室强化时，本次成功率变为原来的1.5倍，最高100%。", "speech": "这可是五级肥料！本次强化成功率变成原来的1.5倍，最高百分之百。闻起来……很有力量！"},
	{"id": "drop_collector", "category": "permanent", "kind": "equipment", "asset": "drop_collector", "title": "物品自动收集器", "price": 5000,
		"tag": "7天有效", "description": "装备后在冒险战斗中自动收集掉落物品。", "speech": "散落的宝贝交给它！装备后自动收集冒险战场的掉落物，购买起七天有效，记得去角色页装备！"},
	{"id": "sun_collector", "category": "permanent", "kind": "equipment", "asset": "sun_collector", "title": "阳光自动收集器", "price": 5000,
		"tag": "7天有效", "description": "装备后在冒险战斗中自动收集阳光。", "speech": "太阳落下来也不用忙着点啦！装备后自动收集冒险战场的阳光，购买起七天有效。"},
	{"id": "double_experience", "category": "permanent", "kind": "equipment", "asset": "double_experience", "title": "双倍经验卡", "price": 5000,
		"tag": "7天有效", "description": "装备后获得的经验变为2倍。", "speech": "同样的冒险，双倍的经验！购买起七天有效，去角色页装备，然后让等级蹭蹭往上长！"},
	{"id": "double_loot", "category": "permanent", "kind": "equipment", "asset": "double_loot", "title": "双倍掉落卡", "price": 5000,
		"tag": "7天有效", "description": "冒险随机材料和消耗品的掉落数量变为2倍，不影响首通、保底和任务物品。", "speech": "一份随机材料变两份！装备后冒险随机材料和消耗品数量翻倍，购买起七天有效。任务奖励可不算哦！"},
	{"id": "spring_cattail", "category": "special", "kind": "equipment", "asset": "spring_cattail", "title": "小璐", "price": 50000, "unique": true,
		"tag": "永久时装", "description": "解锁新春小璐时装；在角色页装备，切换角色立绘。", "speech": "红白新春裙装，小璐来啦！永久拥有，在角色页换上就能看到新立绘。我也想试试……"},
	{"id": "sunflower_girl", "category": "special", "kind": "equipment", "asset": "sunflower_girl", "title": "向日葵娘", "price": 50000, "unique": true,
		"tag": "永久时装", "description": "解锁向日葵娘时装；在角色页装备，切换角色立绘。", "speech": "把阳光穿在身上！向日葵娘时装永久拥有，在角色页装备就能换上。比我的平底锅还耀眼！"},
	{"id": "card_slot", "category": "special", "kind": "slots", "asset": "", "title": "可携带卡槽 +1", "price": 3000,
		"tag": "永久升级", "description": "永久增加一个冒险可携带卡槽，上限11槽。每次购买后价格翻倍。", "speech": "多带一张植物卡，多一份底气！永久增加一个可携带卡槽，最多十一槽。下一次的价钱可要翻倍啦！"},
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
