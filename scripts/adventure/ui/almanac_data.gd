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

## 将 [param kind]、[param type_id] 在 [param tier] 的说明、数值和效果分开供详情面板排版。
static func detail(kind: String, type_id: int, tier: int) -> Dictionary:
	var data: Dictionary = entry(kind, type_id) # 基础说明和战斗阶级说明分开读取。
	var summary: String = str(data.get("描述", "")) # 缺资料时优先复用背包已有植物说明。
	if summary.is_empty() and kind == "plant":
		summary = InventoryData.plant_description(type_id)
	var stats: Dictionary = {} # 数值名称与显示值分别绘制。
	var effects: Array[Dictionary] = [] # 分组保留各转职阶的效果，按当前阶到低阶排序。
	if kind == "plant":
		var info: Dictionary = CharacterRegistry.PlantInfo.get(type_id, {}) # 转职变化显示在独立效果组。
		stats = {
			"基础阳光": str(info.get(CharacterRegistry.PlantInfoAttribute.SunCost, "—")),
			"基础冷却": "%s 秒" % info.get(CharacterRegistry.PlantInfoAttribute.CoolTime, "—"),
		}
		for rank: int in range(tier - 1, 0, -1): # 一转对应二阶，优先显示当前阶。
			var options: Dictionary = {} # 分支名和效果分别显示。
			for book_id: String in Promotions.BOOKS: # 新技能沿用玩法目录。
				var book: Dictionary = Promotions.BOOKS[book_id] # 只读取当前书目字段。
				if int(book.get("plant_type", 0)) == type_id and int(book.get("tier", 0)) == rank:
					var description: String = str(book.get("summary", "")).strip_edges() # 空效果统一显示“无”。
					options[str(book.get("title", book_id))] = description if not description.is_empty() else "无"
			if rank == tier - 1 or not options.is_empty():
				effects.append({"title": "%d 阶" % (rank + 1), "options": options})
	else:
		var id: StringName = tier_id(tier) # 当前阶实际战斗所用配置。
		var values: Dictionary = Tiers.get_tier(id) # 实战使用的本体、防具和啃咬倍率。
		stats = {
			"本体生命": "×%s" % values.get("hp", 1),
			"防具生命": "×%s" % values.get("armor", 1),
			"普通啃咬": "×%s" % values.get("attack", 1),
		}
		var ability: String = AdventureZombieTierTraits.description_for(type_id, id) # 和战斗特性系统共享现有说明接口。
		if not ability.is_empty():
			effects.append({"title": "", "options": {"": ability}})
	return {
		"summary": summary if not summary.is_empty() else "无",
		"stats": stats,
		"effects": effects,
		"traits": data.get("参数", {}),
	}
