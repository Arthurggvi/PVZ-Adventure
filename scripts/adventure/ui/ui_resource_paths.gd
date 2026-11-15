## 窗口准备协议的纯路径工具；不加载资源、不保存缓存，不拥有玩家状态。
extends RefCounted

## 现有皮肤资源的唯一相对路径基准。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 物品美术目录提供底图、卷轴和技能书路径。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 星级角标的路径解析，不创建星章控件或读取纹理。
const StarArt = preload("res://scripts/adventure/ui/star_badge_art.gd")

## 返回 [param files] 与 [param buttons] 的有效皮肤路径；按钮只展开现有状态。
static func skin(files: PackedStringArray, buttons: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var result := PackedStringArray() # 只返回调用窗口明确声明的资源。
	for file: String in files: # 绝对资源路径保持原样，相对路径沿用皮肤目录。
		append(result, file if file.begins_with("res://") else Art.ROOT + file)
	for button: String in buttons: # 控件可切换的状态在首屏一并准备，避免首次悬停读盘。
		for state: String in ["normal", "hover", "pressed", "disabled", "selected"]:
			append(result, Art.ROOT + button + "_" + state + ".png")
	return result

## 同类窗口共享的基础边框，不包含业务图标或角色资源。
static func frame() -> PackedStringArray:
	return skin(PackedStringArray(["panels/wood_ninepatch.png", "panels/outer_frame_ninepatch.png",
		"panels/parchment_ninepatch.png"]), PackedStringArray(["controls/close"]))

## 将 [param path] 去重追加到 [param target]，不存在的可选美术不制造失败请求。
static func append(target: PackedStringArray, path: String) -> void:
	if not path.is_empty() and not target.has(path) and ResourceLoader.exists(path):
		target.append(path)

## 将 [param rows] 实际展示的物品或卡牌依赖追加到 [param target]。
static func inventory_rows(target: PackedStringArray, rows: Array[Dictionary]) -> void:
	var references: Array[ResourceCardReference] = [] # 仅为当前页持有的物种请求卡面。
	for row: Dictionary in rows:
		var plant_type: int = int(row.get("plant_type", 0)) # 配方及植物格共用物种字段。
		var item_id: String = str(row.get("id", "")) # 空 ID 表示实际 UID 卡。
		var promotion_rank := 0 # 卡片用最高已完成转职；技能书改用书目定义的转职次数。
		if not item_id.is_empty():
			append(target, ItemArt.icon_uri(item_id))
			append(target, ItemArt.backing_uri(item_id))
			append(target, ItemArt.recipe_overlay_uri(item_id))
			if str(row.get("category", "")) == "promotion_book":
				var book: Dictionary = AdventurePromotionCatalog.definition(item_id) # 与 PromotionVisual.draw 使用相同权威字段。
				plant_type = int(book.get("plant_type", 0))
				promotion_rank = int(book.get("tier", 0))
		else:
			for rank: int in range(4, 0, -1): # 与 PlantSpawnProfile.promotion_tier 的冻结快照解释一致。
				if not str(row.get("promotion_%d" % rank, "")).is_empty():
					promotion_rank = rank
					break
			for path: String in StarArt.resource_paths(int(row.get("stars", 0))): # 只准备本卡实际可见星章。
				append(target, path)
		if plant_type > 0:
			references.append(ResourceCardReference.create(ResourceCardReference.CardType.Plant, plant_type))
			_plant_art(target, plant_type, promotion_rank)
	for path: String in AllCards.get_resource_paths(references):
		append(target, path)

## 将 [param plant_type] 的 [param promotion_rank] 转动态贴图加入 [param target]，其余物种仍沿用场景静态依赖。
static func _plant_art(target: PackedStringArray, plant_type: int, promotion_rank: int) -> void:
	if plant_type == AdventureSunflowerPromotionArt.SUNFLOWER_TYPE:
		for path: String in AdventureSunflowerPromotionArt.resource_paths(promotion_rank): # 分件、星芒和额外表情属于同一外观。
			append(target, path)

## 返回指定 [param kind]、[param type_id]、[param tier]（1～5）的预览依赖，不实例化整套角色目录。
static func character(kind: String, type_id: int, tier: int = 1) -> PackedStringArray:
	var result := PackedStringArray() # 卡面和待机详情共享同一物种的资源准备。
	var registry: Dictionary = CharacterRegistry.PlantInfo if kind == "plant" else CharacterRegistry.ZombieInfo
	var attribute: int = int(CharacterRegistry.PlantInfoAttribute.PlantScenes) if kind == "plant" else int(CharacterRegistry.ZombieInfoAttribute.ZombieScenes)
	append(result, str(registry.get(type_id, {}).get(attribute, "")))
	var reference: ResourceCardReference = ResourceCardReference.create(ResourceCardReference.CardType.Plant if kind == "plant" else ResourceCardReference.CardType.Zombie, type_id)
	for path: String in AllCards.get_resource_paths([reference]):
		append(result, path)
	if kind == "plant":
		_plant_art(result, type_id, clampi(tier, 1, 5) - 1)
	else:
		var tiers: Array[StringName] = AdventureZombieTierCatalog.tier_ids() # 与图鉴和实战共用等阶顺序。
		var tier_id: StringName = tiers[clampi(tier - 1, 0, tiers.size() - 1)] # 一阶只准备原版形象。
		for path: String in AdventureZombieTierArtCatalog.resource_paths(type_id, tier_id): # 只展开实际所选阶级的替代纹理。
			append(result, path)
	return result
