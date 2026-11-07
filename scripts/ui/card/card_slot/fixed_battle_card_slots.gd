## 普通与金币模式共用固定卡槽；费用、冷却和选卡动画由各自模式处理。
extends PanelContainer
class_name FixedBattleCardSlots

## 两种卡槽场景共用的占位模板。
@onready var _placeholder_template: TextureRect = $CardUiList/CardPlaceholder_ori
## 按配置数量显示卡槽的容器。
@onready var _slot_row: HBoxContainer = $CardUiList

## 本场配置的容量，与显示或隐藏了几个占位无关。
var _capacity: int = 0
## 依照出战顺序存放槽位节点，供选择动画定位。
var _placeholders: Array[Control] = []
## 出战顺序；战斗快捷键与卡槽根节点共享此数组引用。
var curr_cards: Array[Card] = []

## 按 [param capacity] 创建本场占位并返回其顺序，初始化时调用一次。
func _initialize_slots(capacity: int) -> Array[Control]:
	_capacity = capacity
	for index: int in range(_capacity): # 每个配置槽位拥有独立显示节点。
		var placeholder := _placeholder_template.duplicate() as Control # 保留原场景的尺寸与素材。
		_slot_row.add_child(placeholder)
		_placeholders.append(placeholder)
	_placeholder_template.free()
	return _placeholders

## 是否还可追加一张出战卡。
func has_free_slot() -> bool:
	return curr_cards.size() < _capacity

## 将 [param card] 加到出战末尾并返回对应占位；槽位已满时返回 null。
func append_card(card: Card) -> Control:
	if not has_free_slot():
		return null
	var slot: Control = slot_at(curr_cards.size()) # 追加前的数量即目标下标。
	curr_cards.append(card)
	return slot

## 将 [param card] 移出出战队列，返回其旧下标供动画重新排位；未选中时返回 -1。
func remove_card(card: Card) -> int:
	var index: int = curr_cards.find(card) # 调用方用旧位置定位需要前移的卡。
	if index >= 0:
		curr_cards.remove_at(index)
	return index

## 返回已分配的 [param index] 对应的占位节点，用于挂载或动画。
func slot_at(index: int) -> Control:
	return _placeholders[index]

## [param hide_spare] 为 true 时只显示已有出战卡的槽位。
func _set_spare_slots_hidden(hide_spare: bool) -> void:
	for index: int in range(_placeholders.size()): # 按出战顺序判断是否为空槽。
		_placeholders[index].visible = not hide_spare or index < curr_cards.size()
