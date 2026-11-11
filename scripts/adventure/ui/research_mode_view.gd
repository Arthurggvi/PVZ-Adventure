## Work-area widgets for upgrade and promotion; selection only, no business mutations.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 转职技能标题与背包名称共用文字配色。
const ItemName = preload("res://scripts/adventure/ui/item_name_style.gd")
## 信息区文字与三个面板使用同一套边界。
const Layout = preload("res://scripts/adventure/ui/research_panel_skin.gd")
## 槽位组件负责复用背包格并派发点击。
const Slots = preload("res://scripts/adventure/ui/research_slot_view.gd")
## 槽位类型与当前选择状态。
const Picker = preload("res://scripts/adventure/ui/research_slot_picker.gd")
## 耗材槽数量与强化规则一致。
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
## 战斗与强化预览共用的星级加成。
const Growth = preload("res://scripts/adventure/adventure_plant_growth_catalog.gd")
## 这些植物通过爆炸组件或炮弹使用战斗伤害倍率；寒冰菇的冻结不消耗该倍率。
const BLAST_PLANTS := [CharacterRegistry.PlantType.P003CherryBomb, CharacterRegistry.PlantType.P005PotatoMine,
	CharacterRegistry.PlantType.P016DoomShroom, CharacterRegistry.PlantType.P021Jalapeno, CharacterRegistry.PlantType.P048CobCannon]
## 直接在植物脚本调用战斗伤害结算、不经通用攻击组件的植物。
const DIRECT_DAMAGE_PLANTS := [CharacterRegistry.PlantType.P007Chomper, CharacterRegistry.PlantType.P018Squash,
	CharacterRegistry.PlantType.P020TangleKelp, CharacterRegistry.PlantType.P022Caltrop, CharacterRegistry.PlantType.P047SpikeRock]

## 转职工作槽按原始宽高的 60% 绘制。
const PROMOTION_SLOT_SCALE: float = 0.60

static func plant(parent: Control, type_id: int, pos: Vector2, dimensions: Vector2) -> void:
	Art.image(parent, "slots/plant_slot_normal.png", pos, dimensions)
	if not PlantCardInstance.is_plant_type(type_id):
		Art.image(parent, "slots/empty_plant_symbol.png",
			pos + dimensions * 0.22, dimensions * 0.55)
		return
	var ref := ResourceCardReference.create(ResourceCardReference.CardType.Plant, type_id)
	var card: Card = AllCards.create_card(ref, Card.CardContext.Catalog)
	if card == null:
		return
	parent.add_child(card)
	card.visible = true
	card.size = card.get_combined_minimum_size()
	var factor := minf(dimensions.x / card.size.x, dimensions.y / card.size.y) * 0.88
	card.scale = Vector2.ONE * factor
	card.position = pos + (dimensions - card.size * factor) * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.button.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 用 [param preview] 绘制强化信息，在 [param parent] 以 [param picker] 和 [param inventory] 展示可选工作槽。
## [param owner] 接收主卡、耗材、花盆、肥料和生长剂的槽位交互；[param coin_balance] 用于价格提示。
static func upgrade(owner: Control, parent: Control, preview: Dictionary,
		picker: Picker, inventory: AdventureInventoryService, coin_balance: int) -> void:
	var pot_required: int = int(preview.get("pot_required", 0)) # 报价按目标星级给出的保护用量。
	# 上排四槽按宽度缩放到与下排三张耗材卡接近的显示尺寸。
	var tool_scale: float = 0.92
	Slots.work(owner, parent, "upgrade", picker, inventory, Picker.Slot.POT,
		Slots.work_cell(4, 2, 0, tool_scale), 0, pot_required)
	Slots.work(owner, parent, "upgrade", picker, inventory, Picker.Slot.MAIN_CARD,
		Slots.work_cell(4, 2, 1, tool_scale))
	Slots.work(owner, parent, "upgrade", picker, inventory, Picker.Slot.FERTILIZER,
		Slots.work_cell(4, 2, 2, tool_scale))
	Slots.work(owner, parent, "upgrade", picker, inventory, Picker.Slot.GROWTH_AGENT,
		Slots.work_cell(4, 2, 3, tool_scale))
	for index: int in range(Enhancement.MAX_MATERIAL_CARDS):
		Slots.work(owner, parent, "upgrade", picker, inventory, Picker.Slot.MATERIAL_CARD,
			Slots.work_cell(3, 2, index + 3, Slots.COMPACT_SLOT_SCALE), index)
	var bounds: Rect2 = Layout.INFO_REGION.grow(-42.0) # 概率、效果和价格沿同一内边距对齐。
	var chance: Variant = preview.get("chance") # 缺少有效材料时没有概率报价。
	var probability_text := "概率：—" # 未知时显示占位，不显示虚构的零概率。
	var probability_color := Color("382719") # 未知概率沿用普通文字色。
	if chance != null:
		var rate: float = float(chance) # 服务返回 0 到 1，颜色按概率阈值判断。
		if not str(preview.get("growth_agent", "")).is_empty():
			probability_text = "概率：100%（生长剂保底）"
		else:
			probability_text = "概率：%.2f%%" % (rate * 100.0)
		if rate < 0.30:
			probability_color = Color("a32824")
		elif rate < 0.60:
			probability_color = Color("965900")
		else:
			probability_color = Color("286838")
	Art.label(parent, probability_text, bounds.position, Vector2(bounds.size.x, 52), 32, probability_color)
	_divider(parent, bounds.position + Vector2(0, 72), bounds.size.x)
	var plant_type: int = int(preview.get("type", 0)) # 没有主卡时不显示星级效果。
	if PlantCardInstance.is_plant_type(plant_type):
		var stars: int = int(preview.stars) # 当前主卡的实际星级，包括零星。
		var next_star: int = int(preview.target_star) # 已封顶时等于当前星级。
		var stats: Dictionary[String, String] = _star_stat_labels(plant_type) # 两个星级使用相同的植物属性范围。
		_star_effect(parent, stars, stats, bounds.position + Vector2(0, 105), bounds.size.x, Color("382719"))
		if next_star > stars:
			_star_effect(parent, next_star, stats, bounds.position + Vector2(0, 245), bounds.size.x, Color("24558c"))
	price(parent, bounds, int(preview.get("fee", Enhancement.COST)), coin_balance)

## 按 [param plant_type] 读取战斗场景的能力，返回实际使用的星级加成及其名称。
static func _star_stat_labels(plant_type: int) -> Dictionary[String, String]:
	var labels: Dictionary[String, String] = {} # 按伤害、生命、产阳光频率的顺序展示。
	var scene: PackedScene = Global.character_registry.get_plant_scene(plant_type) # 只读场景结构，不实例化植物。
	var scene_state: SceneState = scene.get_state() # 反向双发等植物可能从父场景继承攻击组件。
	var has_attack := false # 通用攻击组件会把倍率传给子弹，部分组件则由植物脚本执行攻击。
	var produces_sun := false # 与战斗代码检测同名产阳光组件。
	while scene_state != null:
		for index: int in range(scene_state.get_node_count()): # 检查当前场景或继承层的组件。
			match scene_state.get_node_name(index):
				&"AttackComponent": has_attack = true
				&"CreateSunComponent": produces_sun = true
		scene_state = scene_state.get_base_scene_state()
	if plant_type in BLAST_PLANTS:
		labels["damage"] = "爆炸伤害"
	elif has_attack or plant_type in DIRECT_DAMAGE_PLANTS:
		labels["damage"] = "伤害"
	labels["max_health"] = "生命"
	if produces_sun:
		labels["sun_production_rate"] = "后续产阳光频率"
	return labels

## 在 [param parent] 的 [param pos] 展示 [param stars] 对应的 [param stats]，按 [param width] 换行并使用 [param color]。
static func _star_effect(parent: Control, stars: int, stats: Dictionary[String, String], pos: Vector2, width: float, color: Color) -> void:
	var modifiers: Dictionary = Growth.modifiers(stars) # 与战斗读取同一套成长数据。
	var summary: String = "%d星效果：基础属性" % stars # 零星没有星级加成。
	if not modifiers.is_empty():
		var effects := PackedStringArray() # 只列出当前植物实际用到的加成。
		for stat: String in stats: # 使用同一成长表中的百分比。
			effects.append("%s +%.2f%%" % [stats[stat], float(modifiers[stat].percent) * 100.0])
		summary = "%d星效果：%s" % [stars, "、".join(effects)]
	var label: Label = Art.label(parent, summary, pos, Vector2(width, 120), 25, color) # 长百分比也可换行显示。
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

## 在 [param parent] 的 [param bounds] 底部显示报价 [param fee]，仅当 [param coin_balance] 不足时标红。
static func price(parent: Control, bounds: Rect2, fee: int, coin_balance: int) -> void:
	var color: Color = Color("a32824") if coin_balance < fee else Color("382719") # 材料不足不影响价格颜色。
	Art.label(parent, "$%d" % fee, Vector2(bounds.position.x, bounds.end.y - 52), Vector2(bounds.size.x, 52), 32, color)

## 在 [param parent] 的 [param pos] 绘制宽 [param width] 像素的面板分割线。
static func _divider(parent: Control, pos: Vector2, width: float) -> void:
	var line := ColorRect.new() # 羊皮纸信息区共用的细线。
	line.position = pos
	line.size = Vector2(width, 2)
	line.color = Color("997749")
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

## 根据 [param preview] 展示下一阶转职，在 [param parent] 放置 [param picker] 与 [param inventory] 对应的主卡和书槽。
## [param owner] 接收槽位交互，分支由左侧选择区填入；[param coin_balance] 用于显示价格颜色。
static func promotion(owner: Control, parent: Control, preview: Dictionary,
		picker: Picker, inventory: AdventureInventoryService, coin_balance: int) -> void:
	Slots.work(owner, parent, "promotion", picker, inventory, Picker.Slot.MAIN_CARD,
		Slots.work_cell(2, 1, 0, PROMOTION_SLOT_SCALE))
	Slots.work(owner, parent, "promotion", picker, inventory, Picker.Slot.PROMOTION_BOOK,
		Slots.work_cell(2, 1, 1, PROMOTION_SLOT_SCALE))
	var current: String = picker.key_for(Picker.Slot.PROMOTION_BOOK) # 与当前报价的转职分支匹配。
	var skill_name := "—" # 未放入转职书时不展示具体技能。
	var effect_text := "" # 复用转职目录的技能描述。
	for branch: Dictionary in preview.get("branches", []):
		if str(branch.id) == current:
			skill_name = str(branch.title)
			effect_text = str(branch.summary)
			break
	var bounds: Rect2 = Layout.INFO_REGION.grow(-42.0) # 右侧内容使用统一内边距。
	ItemName.draw(parent, skill_name, current, Rect2(bounds.position, Vector2(bounds.size.x, 52)), 34)
	_divider(parent, bounds.position + Vector2(0, 72), bounds.size.x)
	var effect: Label = Art.label(parent, effect_text, bounds.position + Vector2(0, 100),
		Vector2(bounds.size.x, bounds.size.y - 248), 26, Color("24558c")) # 技能效果在两条分割线之间自动换行。
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_divider(parent, Vector2(bounds.position.x, bounds.end.y - 128), bounds.size.x)
	price(parent, Rect2(bounds.position, bounds.size - Vector2(0, 46)),
		int(preview.get("fee", AdventurePromotionCatalog.COST)), coin_balance)
	Art.label(parent, "转职后将无法撤销", Vector2(bounds.position.x, bounds.end.y - 40),
		Vector2(bounds.size.x, 40), 24, Color("a32824"))
