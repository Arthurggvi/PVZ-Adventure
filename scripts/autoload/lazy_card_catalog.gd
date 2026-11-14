## AllCards 的唯一延迟加载门面；首次请求才装配原有模板树。
## 保持五个公共方法与卡牌身份协议，不维护第二份目录。
extends Node
## 唯一权威卡牌目录场景，保留编辑器内的配置和排序。
const CATALOG_SCENE := "res://scenes/autoload/all_cards.tscn"
## 首次使用后缓存的原目录节点，生命周期与 Autoload 相同。
var _catalog: AllCardsClass

## 只读查询是否已加载，不因测试查询触发实体化。
func is_catalog_materialized() -> bool:
	return is_instance_valid(_catalog)

## 原目录的唯一实例化入口；缺失资源则返回 null。
func _source() -> AllCardsClass:
	if is_instance_valid(_catalog):
		return _catalog
	var packed: PackedScene = load(CATALOG_SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		push_error("AllCards: canonical template scene cannot be loaded")
		return null
	var catalog := packed.instantiate() as AllCardsClass
	if catalog == null:
		push_error("AllCards: source scene does not implement AllCardsClass")
		return null
	add_child(catalog) # 原目录 _ready() 仍负责建立模板身份索引。
	_catalog = catalog
	return _catalog

## [param reference] 为卡牌稳定身份；从原目录查询模板。
func get_template(reference: ResourceCardReference) -> Card:
	var catalog := _source()
	return catalog.get_template(reference) if catalog != null else null

## [param reference] 标识卡牌；[param context] 指定用途；返回独立实例。
func create_card(reference: ResourceCardReference,
		context: Card.CardContext = Card.CardContext.Catalog) -> Card:
	var catalog := _source()
	return catalog.create_card(reference, context) if catalog != null else null

## [param reference] 与 [param promotion_tier] 由原目录统一制作静态卡面。
func create_static_preview(reference: ResourceCardReference, promotion_tier: int = 0) -> Node2D:
	var catalog := _source()
	return catalog.create_static_preview(reference, promotion_tier) if catalog != null else null

## [param card_type] 指定分类；返回原有顺序的卡牌身份列表。
func get_references(card_type: int) -> Array[ResourceCardReference]:
	var catalog := _source()
	if catalog != null:
		return catalog.get_references(card_type)
	var empty: Array[ResourceCardReference] = []
	return empty

## [param reference] 的出战资格只由原目录判断。
func is_battle_card(reference: ResourceCardReference) -> bool:
	var catalog := _source()
	return catalog.is_battle_card(reference) if catalog != null else false
