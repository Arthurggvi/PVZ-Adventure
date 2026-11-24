## AllCards 的唯一资源门面；身份查询只读轻量索引，卡面按请求的物种独立装配。
## 编辑器总览与单卡身份是权威源，索引由 tools/card_catalog.py 生成。
extends Node
## 纯身份和路径映射，不静态引用卡面资源。
const Manifest = preload("res://scripts/autoload/card_catalog_manifest.gd")
## 当前构造帧内的只读模板；同一身份复用一次，下一帧释放全部临时节点。
var _templates: Dictionary[Vector2i, Card] = {}
## 隐藏且不处理帧回调的模板宿主；复制出的卡牌仍继承实际界面的处理模式。
var _template_root: Control

## 返回是否已经装配任何卡面；纯身份查询不会改变此状态。
func is_catalog_materialized() -> bool:
	return not _templates.is_empty()

## 返回 [param reference] 的独立卡面路径；未注册或非法身份返回空串，不加载资源。
func get_template_path(reference: ResourceCardReference) -> String:
	if reference == null or not reference.is_valid():
		return ""
	return Manifest.PATHS.get(reference.get_template_key(), "")

## 收集 [param references] 的去重卡面路径，供统一加载管线提前准备；不装配模板。
func get_resource_paths(references: Array[ResourceCardReference]) -> PackedStringArray:
	var paths := PackedStringArray() # 同物种的多张库存卡只请求一次资源。
	for reference: ResourceCardReference in references: # 顺序保持调用方首次请求顺序。
		var path: String = get_template_path(reference) # 模仿卡使用目标植物卡面。
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	return paths

## 返回 [param reference] 的临时只读模板，仅供本帧同步复制；不得跨帧持有。失败返回 null。
func get_template(reference: ResourceCardReference) -> Card:
	var path: String = get_template_path(reference) # 元数据校验不触碰其他卡面。
	if path.is_empty():
		return null
	var key: Vector2i = reference.get_template_key() # 普通卡与模仿卡共享基础模板。
	if _templates.has(key):
		return _templates[key]
	var packed: PackedScene = load(path) as PackedScene # 已由切场准备的资源会复用 ResourceLoader 缓存。
	if packed == null or not packed.can_instantiate():
		push_error("AllCards：卡牌模板无法加载：" + path)
		return null
	var instance: Node = packed.instantiate() # 先保留原节点，错误类型也能立即释放。
	var card := instance as Card # 只接受具有稳定基础身份的卡牌场景。
	if card == null or card.card_reference == null or card.card_reference.is_imitater \
			or card.card_reference.get_template_key() != key:
		instance.free()
		push_error("AllCards：模板身份与生成索引不一致，请运行 tools/card_catalog.py：" + path)
		return null
	if not is_instance_valid(_template_root):
		_template_root = Control.new()
		_template_root.name = "RequestedCardTemplates"
		_template_root.hide()
		_template_root.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(_template_root)
		get_tree().process_frame.connect(_release_templates, CONNECT_ONE_SHOT)
	_template_root.add_child(card) # 保留原 _ready 初始化费用、种植条件及静态图容器。
	_templates[key] = card
	return card

## 本批同步复制已经完成；释放源节点，不影响独立卡面持有的资源。
func _release_templates() -> void:
	_templates.clear()
	if is_instance_valid(_template_root):
		_template_root.free()
	_template_root = null

## [param reference] 标识卡牌；[param context] 指定用途；返回尚未入树的独立实例。
func create_card(reference: ResourceCardReference,
		context: Card.CardContext = Card.CardContext.Catalog) -> Card:
	if (context == Card.CardContext.Battle or context == Card.CardContext.Selection) and not is_battle_card(reference):
		push_error("AllCards：此卡牌不支持选卡或出战用途")
		return null
	return AllCardsClass.copy_card(get_template(reference), reference, context)

## [param reference] 与 [param promotion_tier] 使用同一模板制作独立静态卡面。
func create_static_preview(reference: ResourceCardReference, promotion_tier: int = 0) -> Node2D:
	return AllCardsClass.copy_static_preview(get_template(reference), reference, promotion_tier)

## [param card_type] 指定分类；只按总览原顺序创建身份引用，不加载卡面。
func get_references(card_type: int) -> Array[ResourceCardReference]:
	var result: Array[ResourceCardReference] = [] # 调用方持有独立引用，不能改写索引。
	for key: Vector2i in Manifest.PATHS: # 字典由生成器按原分类容器顺序输出。
		if key.x == card_type:
			result.append(ResourceCardReference.create(key.x, key.y))
	return result

## [param reference] 的出战资格只依赖已注册身份；查询不会装配任何卡面。
func is_battle_card(reference: ResourceCardReference) -> bool:
	return not get_template_path(reference).is_empty() \
		and not (reference.card_type == ResourceCardReference.CardType.Plant \
			and reference.content_id == CharacterRegistry.PlantType.P999Imitater)
