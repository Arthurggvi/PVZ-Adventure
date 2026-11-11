## 冒险图鉴只读投影：物种、阶级和技能均读取玩法目录，不维护第二份内容清单。
extends RefCounted

## 植物中文名和缺省能力说明复用背包入口。
const InventoryData = preload("res://scripts/adventure/ui/inventory_data.gd")
## 植物转职分支的权威定义。
const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
## 僵尸基础倍率及阶级顺序。
const Tiers = preload("res://scripts/adventure/adventure_zombie_tier_catalog.gd")

## 返回 [param state] 已发现的 [param kind] 物种；[param search] 按中文名过滤，顺序跟随注册表。
static func rows(state: AdventureState, kind: String, search: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 只返回视图数据，不向界面暴露可写存档引用。
	if state == null:
		return result
	var registry: Dictionary = CharacterRegistry.PlantInfo if kind == "plant" else CharacterRegistry.ZombieInfo # 新增物种自动进入候选目录。
	var needle: String = search.strip_edges().to_lower() # 搜索不区分大小写。
	for type_id: int in registry: # 只展示真正发现的物种，不通过预览或关卡表解锁。
		if not state.almanac_discoveries.get("%s:%d" % [kind, type_id], false):
			continue
		var title: String = character_name(kind, type_id) # 中文名同样来自现有目录。
		if needle.is_empty() or title.to_lower().contains(needle):
			result.append({"kind": kind, "type_id": type_id, "title": title})
	return result

## 返回 [param kind]、[param type_id] 的原版基础资料；缺失条目时返回空字典。
static func entry(kind: String, type_id: int) -> Dictionary:
	Global.global_read_data.ensure_almanac_loaded()
	var registry: Dictionary = CharacterRegistry.PlantInfo if kind == "plant" else CharacterRegistry.ZombieInfo # 使用角色注册表中的稳定英文键。
	var info: Dictionary = registry.get(type_id, {}) # 防御更新后已移除的角色。
	var attribute: int = CharacterRegistry.PlantInfoAttribute.PlantName if kind == "plant" else CharacterRegistry.ZombieInfoAttribute.ZombieName # 两类角色各自的名称字段。
	return Global.global_read_data.data_almanac.get("Plant" if kind == "plant" else "Zombie", {}).get(str(info.get(attribute, "")), {})

## 返回 [param kind]、[param type_id] 的中文名称；尚无翻译时显示明确编号。
static func character_name(kind: String, type_id: int) -> String:
	if kind == "plant":
		return InventoryData.plant_name(type_id)
	return str(entry(kind, type_id).get("名字", "僵尸 #%d" % type_id))

## 返回 [param kind]、[param type_id] 的展示身份，与卡牌工厂共用编号。
static func card_reference(kind: String, type_id: int) -> ResourceCardReference:
	return ResourceCardReference.create(ResourceCardReference.CardType.Plant if kind == "plant" else ResourceCardReference.CardType.Zombie, type_id)

## 返回 [param tier]（1–5）对应的僵尸阶级 ID，顺序读取玩法目录。
static func tier_id(tier: int) -> StringName:
	var ids: Array[StringName] = Tiers.tier_ids() # 与实战阶级共享顺序和稳定标识。
	return ids[clampi(tier - 1, 0, ids.size() - 1)]

## 返回 [param kind]、[param type_id] 的注册场景；只用于读取参数或生成展示副本。
static func scene_for(kind: String, type_id: int) -> PackedScene:
	if kind == "plant":
		return Global.character_registry.get_plant_scene(type_id)
	return CharacterRegistry.ZombieInfo.get(type_id, {}).get(CharacterRegistry.ZombieInfoAttribute.ZombieScenes) as PackedScene

## 生成 [param kind]、[param type_id] 在 [param tier] 的文字；分支保持互斥，不伪造唯一累计数值。
static func description(kind: String, type_id: int, tier: int) -> String:
	var data: Dictionary = entry(kind, type_id) # 基础说明和战斗阶级说明分开读取。
	var lines := PackedStringArray() # 使用普通文本，避免配置中的括号被当作富文本标签。
	var summary: String = str(data.get("描述", "")) # 缺资料时优先复用背包已有植物说明。
	if summary.is_empty() and kind == "plant":
		summary = InventoryData.plant_description(type_id)
	lines.append(summary if not summary.is_empty() else "基础能力说明暂未配置。")
	lines.append("")
	if kind == "plant":
		var info: Dictionary = CharacterRegistry.PlantInfo.get(type_id, {}) # 这里显示基准值，分支的变化在下方逐项列出。
		lines.append("基础阳光：%s    基础冷却：%s 秒" % [info.get(CharacterRegistry.PlantInfoAttribute.SunCost, "—"), info.get(CharacterRegistry.PlantInfoAttribute.CoolTime, "—")])
		lines.append("阶级按转职展示，不计卡片强化星级或玩家装备加成。")
		if tier == 1:
			lines.append("\n1 阶 · 初始形态\n尚未转职，使用基础能力。")
		else:
			lines.append("\n%d 阶 · 转职能力\n每阶分支择一生效；高阶保留此前所选分支。" % tier)
			for rank: int in range(1, tier): # 动态遍历每阶技能书，不把向日葵或任何技能写死在图鉴。
				var options: PackedStringArray = [] # 同阶所有可选效果一并供玩家查阅。
				for book_id: String in Promotions.BOOKS: # 新增技能书无需再修改图鉴。
					var book: Dictionary = Promotions.definition(book_id) # 目录副本只用于展示。
					if int(book.get("plant_type", 0)) == type_id and int(book.get("tier", 0)) == rank:
						options.append("• %s：%s" % [book.get("title", book_id), book.get("summary", "效果说明暂未配置。")])
				lines.append("\n%d 阶%s" % [rank + 1, "（当前查看）" if rank + 1 == tier else "（此前可选）"])
				lines.append("\n".join(options) if not options.is_empty() else "暂无该阶专属效果，沿用已有形象与基础能力。")
	else:
		var id: StringName = tier_id(tier) # 当前阶实际战斗所用配置。
		var values: Dictionary = Tiers.get_tier(id) # 本体、防具、普通啃咬分别应用自己的倍率。
		lines.append("%d 阶属性\n本体生命 ×%s    防具生命 ×%s\n普通啃咬伤害 ×%s" % [tier, values.get("hp", 1), values.get("armor", 1), values.get("attack", 1)])
		lines.append("倍率以 1 阶为基准；特殊攻击按技能规则生效。")
		var ability: String = AdventureZombieTierTraits.description_for(type_id, id) # 和战斗特性系统共享现有说明接口。
		lines.append("\n阶级效果\n" + (ability if not ability.is_empty() else "本阶无额外专属技能，保留基础能力。"))
	var parameters: Dictionary = data.get("参数", {}) # 基础韧性、伤害类型等描述不冒充高阶实际数值。
	if not parameters.is_empty():
		lines.append("\n基础特性")
		for key: String in parameters: # 原版文字只作为基础参考保留。
			lines.append("%s：%s" % [key, str(parameters[key])])
	return "\n".join(lines)
