## 商店唯一商品目录；价格、发货类型与分类不由界面或存档指定。
extends RefCounted

## 初始可携带卡槽；旧档未购买时沿用六槽。
const BASE_SLOTS := 6
## 商店最多出售五次扩容。
const MAX_SLOTS := 11
## 每日时装展区的稳定分类键。
const OUTFIT_CATEGORY := "outfit"
## 固定分类顺序，界面按此生成页签。
const CATEGORIES: Array[String] = ["daily", "permanent", "special", OUTFIT_CATEGORY]
## 分类中文名。
const CATEGORY_NAMES: Dictionary = {
	"daily": "每日商品", "permanent": "常驻商品", "special": "特殊商品", OUTFIT_CATEGORY: "每日时装",
}
## 每天抽取的时装数量。
const OUTFIT_COUNT := 3
## 永久时装沿用原商店定价，单位为金币。
const OUTFIT_PRICE := 50000
## 商店轮换时装的稳定装备 ID；任务专属奖励不进入商品池。保持顺序以固定同日抽签结果。
const OUTFIT_POOL: Array[String] = [
	"spring_cattail", "sunflower_girl", "rainy_postman_miro", "midnight_clockmaker_koro",
	"unemployed_reaper_moi", "glass_sea_diver_bubble", "snow_train_conductor_eve",
	"don_quixote_lancer", "tiramisu_flower_crown",
]
## 时装、收集器和双倍卡成交后，戴夫用这句台词提示装备入口。
const EQUIP_PURCHASE_SPEECH := "去你的角色页面装备"
## 商品配置：item 发普通背包，equipment 发角色装备，slots 扩容，glove 解锁战斗工具。
const PRODUCTS: Array[Dictionary] = [
	{"id": "seedling_pot", "category": "daily", "kind": "item", "asset": "seedling_pot", "title": "保育花盆", "price": 5000, "daily_limit": 2,
		"tag": "强化保护", "description": "使用后，强化失败时保留主卡星级和耗材卡。", "speech": "强化失败，星级和耗材卡都保住！"},
	{"id": "growth_agent_lv5", "category": "daily", "kind": "item", "asset": "growth_agent_lv5", "title": "5级生长剂", "price": 100000, "daily_limit": 1,
		"tag": "必成强化", "description": "4星主卡强化至5星时，成功率直接变为100%；仍需正常耗材与金币。", "speech": "四星升五星，一瓶稳成！"},
	{"id": "fertilizer_lv5", "category": "daily", "kind": "item", "asset": "fertilizer_lv5", "title": "5级肥料", "price": 100000, "daily_limit": 1,
		"tag": "强化助力", "description": "研究室强化时，本次成功率变为原来的1.5倍，最高100%。", "speech": "强化成功率，变成1.5倍！"},
	{"id": "drop_collector", "category": "permanent", "kind": "equipment", "asset": "drop_collector", "title": "物品自动收集器", "price": 5000,
		"tag": "7天有效", "description": "装备后在冒险战斗中自动收集掉落物品。", "speech": "地上的宝贝，它替你捡。",
		"purchase_speech": EQUIP_PURCHASE_SPEECH},
	{"id": "sun_collector", "category": "permanent", "kind": "equipment", "asset": "sun_collector", "title": "阳光自动收集器", "price": 5000,
		"tag": "7天有效", "description": "装备后在冒险战斗中自动收集阳光。", "speech": "阳光自己进兜，多省心！",
		"purchase_speech": EQUIP_PURCHASE_SPEECH},
	{"id": "double_experience", "category": "permanent", "kind": "equipment", "asset": "double_experience", "title": "双倍经验卡", "price": 5000,
		"tag": "7天有效", "description": "装备后获得的经验变为2倍。", "speech": "一趟冒险，双倍经验！",
		"purchase_speech": EQUIP_PURCHASE_SPEECH},
	{"id": "double_loot", "category": "permanent", "kind": "equipment", "asset": "double_loot", "title": "双倍掉落卡", "price": 5000,
		"tag": "7天有效", "description": "冒险随机材料和消耗品的掉落数量变为2倍，不影响首通、保底和任务物品。", "speech": "随机掉落，一份变两份！",
		"purchase_speech": EQUIP_PURCHASE_SPEECH},
	{"id": "card_slot", "category": "special", "kind": "slots", "asset": "", "title": "可携带卡槽 +1", "price": 3000,
		"tag": "永久升级", "description": "永久增加一个冒险可携带卡槽，上限11槽。每次购买后价格翻倍。", "speech": "永久多带一张卡！"},
	{"id": "glove", "category": "special", "kind": "glove", "asset": "", "title": "手套", "price": 20000,
		"description": "在冒险战斗中移动植物。", "speech": "先选植物，再选落点。"},
]

## 返回 [param id] 的独立商品定义；未知 ID 返回空字典。
static func product(id: String) -> Dictionary:
	if id in OUTFIT_POOL:
		var outfit: EquipmentDefinition = EquipmentCatalog.definition(StringName(id)) # 沿用角色页名称和说明，只加载实际请求的时装。
		if outfit == null or outfit.slot != EquipmentDefinition.Slot.OUTFIT:
			return {}
		return {"id": id, "category": OUTFIT_CATEGORY, "kind": "equipment", "asset": id,
			"title": outfit.display_name, "price": OUTFIT_PRICE, "unique": true,
			"description": outfit.description + "\n可在角色页预览和装备。",
			"speech": outfit.description, "purchase_speech": EQUIP_PURCHASE_SPEECH}
	for entry: Dictionary in PRODUCTS: # 目录顺序也决定货架顺序。
		if entry.id == id:
			return entry.duplicate(true)
	return {}

## 返回 [param category] 的商品 ID；每日时装按已校验的自然日 [param day] 无放回抽取。
static func ids(category: String, day: String = "") -> Array[String]:
	var result: Array[String] = [] # 不向表现层暴露可变静态目录。
	if category == OUTFIT_CATEGORY:
		if day.is_empty():
			return result
		var pool: Array[String] = OUTFIT_POOL.duplicate() # 只抽 ID，不预加载未上架时装的贴图。
		var rng := RandomNumberGenerator.new() # 日期散列保证同日重开结果一致，不影响游戏的全局随机状态。
		rng.seed = day.sha256_text().left(15).hex_to_int()
		for _slot: int in mini(OUTFIT_COUNT, pool.size()): # 每次划掉已选项，最多填满三个展示位。
			result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		return result
	for entry: Dictionary in PRODUCTS: # 新增同类商品自动出现在货架。
		if entry.category == category:
			result.append(str(entry.id))
	return result

## 返回 [param id] 的每日限购数量。无额度或未知 ID 返回 0，存档校验只读取目录中的数值。
static func daily_limit(id: String) -> int:
	for entry: Dictionary in PRODUCTS: # 每日限购商品来自固定目录，每日时装无此字段。
		if entry.id == id:
			return int(entry.get("daily_limit", 0))
	return 0

## 返回当前 [param slots] 的扩容价格；满槽或非法容量返回零。
static func slot_price(slots: int) -> int:
	return 3000 * (1 << (slots - BASE_SLOTS)) if slots >= BASE_SLOTS and slots < MAX_SLOTS else 0
