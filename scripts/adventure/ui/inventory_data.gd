## Adapter over existing UID card instances and ItemRegistry: no parallel inventory data.
extends RefCounted
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
const Recipes = preload("res://scripts/adventure/research/research_recipe_catalog.gd")
## 肥料说明使用强化成功率计算中的倍率。
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
## 图鉴尚无条目的特殊植物中文名；不改变注册表使用的稳定索引。
const SPECIAL_PLANT_NAMES: Dictionary[int, String] = {
	CharacterRegistry.PlantType.P049PeaShooterDoubleReverse: "反向双发射手",
	CharacterRegistry.PlantType.P999Imitater: "模仿者",
	CharacterRegistry.PlantType.P1000Sprout: "幼苗",
	CharacterRegistry.PlantType.P1001WallNutBowling: "保龄球坚果",
	CharacterRegistry.PlantType.P1002WallNutBowlingBomb: "爆炸坚果",
	CharacterRegistry.PlantType.P1003WallNutBowlingBig: "巨型坚果",
}
## 植物展示共用的简明能力描述；新增未填写植物保持空白。
const PLANT_DESCRIPTIONS: Dictionary[int, String] = {
	CharacterRegistry.PlantType.P001PeaShooterSingle: "发射豌豆攻击前方的僵尸",
	CharacterRegistry.PlantType.P002SunFlower: "定期生产阳光，为种植其他植物提供资源",
	CharacterRegistry.PlantType.P003CherryBomb: "短暂引爆后炸伤周围一片区域内的僵尸",
	CharacterRegistry.PlantType.P004WallNut: "用坚硬的外壳阻挡僵尸，保护后方植物",
	CharacterRegistry.PlantType.P005PotatoMine: "埋入地下准备就绪后，在僵尸踩到时爆炸",
	CharacterRegistry.PlantType.P006SnowPea: "发射寒冰豌豆，攻击并减速前方的僵尸",
	CharacterRegistry.PlantType.P007Chomper: "吞下靠近的僵尸，消化期间无法继续吞食",
	CharacterRegistry.PlantType.P008PeaShooterDouble: "每次连续发射两颗豌豆攻击前方的僵尸",
	CharacterRegistry.PlantType.P009PuffShroom: "向前方喷射孢子，攻击近距离的僵尸",
	CharacterRegistry.PlantType.P010SunShroom: "定期生产阳光，长大后每次产出更多阳光",
	CharacterRegistry.PlantType.P011FumeShroom: "向前喷出烟雾，穿透僵尸的盾牌并攻击一排敌人",
	CharacterRegistry.PlantType.P012GraveBuster: "吞噬墓碑，清除被墓碑占据的种植位置",
	CharacterRegistry.PlantType.P013HypnoShroom: "被僵尸吃下后将其催眠，使其转身攻击其他僵尸",
	CharacterRegistry.PlantType.P014ScaredyShroom: "远距离发射孢子，僵尸靠近时躲起来停止攻击",
	CharacterRegistry.PlantType.P015IceShroom: "释放寒气，短暂冻结场上的僵尸",
	CharacterRegistry.PlantType.P016DoomShroom: "引发大范围爆炸，并留下暂时无法种植的弹坑",
	CharacterRegistry.PlantType.P017LilyPad: "漂浮在水面，为其他植物提供种植位置",
	CharacterRegistry.PlantType.P018Squash: "发现靠近的僵尸后跃起，将其压扁",
	CharacterRegistry.PlantType.P019ThreePeater: "同时向前方三条路线发射豌豆",
	CharacterRegistry.PlantType.P020TangleKelp: "缠住靠近的水中僵尸，将其拖入水底",
	CharacterRegistry.PlantType.P021Jalapeno: "沿所在路线释放火焰，焚烧整行僵尸",
	CharacterRegistry.PlantType.P022Caltrop: "扎伤踩过的僵尸，并刺破车辆的轮胎",
	CharacterRegistry.PlantType.P023TorchWood: "点燃穿过自身的普通豌豆，提高豌豆的攻击伤害",
	CharacterRegistry.PlantType.P024TallNut: "用高大坚固的身躯阻挡僵尸，并拦截跳跃越过的敌人",
	CharacterRegistry.PlantType.P025SeaShroom: "生长在水面，向前方近距离的僵尸喷射孢子",
	CharacterRegistry.PlantType.P026Plantern: "照亮周围区域，驱散附近的迷雾",
	CharacterRegistry.PlantType.P027Cactus: "发射尖刺，攻击地面僵尸和空中的气球僵尸",
	CharacterRegistry.PlantType.P028Blover: "吹走气球僵尸，并暂时驱散迷雾",
	CharacterRegistry.PlantType.P029SplitPea: "向前后两个方向发射豌豆，后方使用双发攻击",
	CharacterRegistry.PlantType.P030StarFruit: "向五个方向发射星星，攻击不同方向的僵尸",
	CharacterRegistry.PlantType.P031Pumpkin: "套在其他植物外侧，为其提供额外保护",
	CharacterRegistry.PlantType.P032MagnetShroom: "吸走附近僵尸携带的铁制装备，削弱其防护或能力",
	CharacterRegistry.PlantType.P033CabbagePult: "抛出卷心菜，越过障碍攻击前方的僵尸",
	CharacterRegistry.PlantType.P034FlowerPot: "为屋顶等无法直接种植的地面提供种植位置",
	CharacterRegistry.PlantType.P035CornPult: "投掷玉米粒攻击僵尸，偶尔投出黄油将其定住",
	CharacterRegistry.PlantType.P036CoffeeBean: "唤醒白天沉睡的蘑菇，使其恢复行动",
	CharacterRegistry.PlantType.P037Garlic: "被僵尸啃咬后，迫使其转向相邻路线",
	CharacterRegistry.PlantType.P038UmbrellaLeaf: "保护附近的植物，拦截蹦极僵尸和空中投掷物",
	CharacterRegistry.PlantType.P039MariGold: "定期生产钱币，为你积累财富",
	CharacterRegistry.PlantType.P040MelonPult: "投掷西瓜，对命中的僵尸及附近敌人造成范围伤害",
	CharacterRegistry.PlantType.P041GatlingPea: "每次连续发射四颗豌豆，密集攻击前方的僵尸",
	CharacterRegistry.PlantType.P042TwinSunFlower: "定期生产双份阳光，提供更多种植资源",
	CharacterRegistry.PlantType.P043GloomShroom: "向周围持续喷射烟雾，同时攻击多个方向的僵尸",
	CharacterRegistry.PlantType.P044Cattail: "发射追踪尖刺，攻击场上不同路线的僵尸和气球僵尸",
	CharacterRegistry.PlantType.P045WinterMelon: "投掷冰西瓜，对一片僵尸造成范围伤害并减速",
	CharacterRegistry.PlantType.P046GoldMagnet: "自动吸引附近的钱币和钻石，帮助收集掉落财富",
	CharacterRegistry.PlantType.P047SpikeRock: "用坚硬尖刺持续扎伤踩过的僵尸，并抵御车辆碾压",
	CharacterRegistry.PlantType.P048CobCannon: "点击选定目标区域，发射玉米炮弹造成大范围爆炸",
	CharacterRegistry.PlantType.P049PeaShooterDoubleReverse: "每次向后方连续发射两颗豌豆，攻击身后的僵尸",
	CharacterRegistry.PlantType.P999Imitater: "种下后变成选定的植物，模仿其能力",
	CharacterRegistry.PlantType.P1000Sprout: "尚未长成的幼苗，可在花园中继续培育",
	CharacterRegistry.PlantType.P1001WallNutBowling: "沿路线滚动撞击僵尸，碰撞后弹向其他路线",
	CharacterRegistry.PlantType.P1002WallNutBowlingBomb: "滚向僵尸并在碰撞时爆炸，攻击附近的敌人",
	CharacterRegistry.PlantType.P1003WallNutBowlingBig: "以巨大的身躯向前滚动，碾过沿途的僵尸",
}

static func rows(category: String, search: String, order_mode: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if Global.adventure_inventory == null:
		return result
	if category == "plants":
		for card: Dictionary in Global.adventure_inventory.list_cards():
			result.append(plant_row(card))
	else:
		var counts: Dictionary = Global.adventure_inventory.get_items()
		for id: String in counts:
			var definition: Dictionary = ItemRegistry.get_item_definition(id)
			var group: String = str(definition.get("category", ""))
			if category == "recipes" and group != "recipe":
				continue
			if category == "materials" and group != "material":
				continue
			if category == "items" and group != "key" and group != "consumable" and group != "promotion_book":
				continue
			result.append(item_row(id, int(counts[id]), definition))
	if not search.strip_edges().is_empty():
		var needle := search.strip_edges().to_lower()
		var filtered: Array[Dictionary] = []
		for row: Dictionary in result:
			var hay := (str(row.get("title", "")) + " " + str(row.get("uid", row.get("id", "")))).to_lower()
			if hay.contains(needle):
				filtered.append(row)
		result = filtered
	if order_mode == 1:
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["title"]) < str(b["title"]))
	elif order_mode == 2 and category == "plants":
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["stars"]) > int(b["stars"]))
	return result

## 把 [param card] 转成背包格可读的展示行，保留卡片独立 UID 和转职数据。
static func plant_row(card: Dictionary) -> Dictionary:
	if card.is_empty():
		return {}
	var row: Dictionary = card.duplicate(true) # 展示层持有副本，不修改库存快照。
	var plant_type: int = int(row["plant_type"]) # 中文名称和描述均按物种查询。
	row["kind"] = "plant"
	row["title"] = plant_name(plant_type)
	row["description"] = plant_description(plant_type)
	return row

## 把 [param id] 和展示数量 [param quantity] 转成背包格展示行。[param definition] 可传入已查到的目录项。
static func item_row(id: String, quantity: int, definition: Dictionary = {}) -> Dictionary:
	var item: Dictionary = ItemRegistry.get_item_definition(id) if definition.is_empty() else definition # 目录提供美术分类与名称。
	if item.is_empty():
		return {}
	var category: String = str(item.get("category", "")) # 与背包共用配方、材料及道具样式。
	var row := {"kind": "item", "id": id, "title": str(item.get("name", id)),
		"qty": quantity, "category": category, "description": str(item.get("description", ""))} # 一次展示所需的字段。
	if category == "recipe":
		var recipe: Dictionary = Recipes.definition(id) # 预览物种和所需材料读取同一个合成定义。
		row["plant_type"] = int(recipe.get("plant_type", 0))
		var material_names := PackedStringArray() # 按配方顺序列出中文材料名。
		for material_id: String in recipe.get("materials", []): # 材料数量由合成规则处理。
			material_names.append(str(ItemRegistry.get_item_definition(material_id).get("name", material_id)))
		if not material_names.is_empty():
			row["description"] = "所需材料：%s" % "、".join(material_names)
	elif item.has("fertilizer_level"):
		var multiplier: float = Enhancement.fertilizer_multiplier(id) # 与研究室使用肥料时的计算一致。
		row["description"] = "强化时使用，本次成功率变为原来的 %.1f 倍，最高为 100%%。" % multiplier
	return row

## 返回 [param type_id] 的中文显示名；图鉴内部英文键只用于查询，不用于 UI。
static func plant_name(type_id: int) -> String:
	if SPECIAL_PLANT_NAMES.has(type_id):
		return SPECIAL_PLANT_NAMES[type_id]
	if Global.character_registry == null or Global.global_read_data == null:
		return "植物 #%d" % type_id
	Global.global_read_data.ensure_almanac_loaded()
	var key: String = str(Global.character_registry.get_plant_info(type_id as CharacterRegistry.PlantType,
		CharacterRegistry.PlantInfoAttribute.PlantName)) # 保留注册表中的图鉴索引。
	var entry: Dictionary = Global.global_read_data.data_almanac.get("Plant", {}).get(key, {}) # 复用现有中文名称。
	return str(entry.get("名字", "植物 #%d" % type_id))

## 返回 [param type_id] 对应的植物描述；未填写的物种返回空字符串。
static func plant_description(type_id: int) -> String:
	return PLANT_DESCRIPTIONS.get(type_id, "")

## ItemRegistry validates ownership; the art manifest decides only visual resources.
static func item_icon(row: Dictionary) -> String:
	return ItemArt.icon_uri(str(row.get("id", "")))

static func item_backing(row: Dictionary) -> String:
	return ItemArt.backing_uri(str(row.get("id", "")))
