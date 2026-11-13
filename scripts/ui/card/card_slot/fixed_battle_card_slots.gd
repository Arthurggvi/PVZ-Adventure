## 普通与金币模式共用卡槽预算；免槽卡保留真实卡片、顺序、费用和冷却。
extends PanelContainer
class_name FixedBattleCardSlots

## 隐藏但保留的占位模板，额外显示位只复制素材，不复制已有卡片。
@onready var _placeholder_template: TextureRect = $CardUiList/CardPlaceholder_ori
## 保留原生行容器，星徽等边缘特效不会被额外裁剪。
@onready var _slot_row: HBoxContainer = $CardUiList
## 本场普通卡预算，不等于包含免槽卡后的真实卡片数量。
var _capacity: int = 0
## 稳定的显示位；取消卡时不销毁动画仍引用的节点。
var _placeholders: Array[Control] = []
## 出战顺序；快捷键与卡槽根节点共享此数组引用，不能替换数组。
var curr_cards: Array[Card] = []
## 每个原生显示位的完整尺寸。
var _slot_size: Vector2
## 当前是否按设置隐藏没有卡片的普通槽。
var _hide_spare: bool = false
## 当前窗口的起始显示位，翻动不会改变真实出战顺序。
var _first_visible_slot: int = 0
## 溢出时才出现的翻动按钮，不增加卡栏高度或覆盖候选区。
var _navigation: Control
## 前后翻动按钮依次保存，窗口到达边界时禁用对应按钮。
var _navigation_buttons: Array[Button] = []
## 本卡栏独占的背景边距，额外按钮只占右侧空间。
var _panel_style: StyleBox
## 未溢出时的原生背景右边距。
var _base_right_margin: float = 0.0
## 两枚按钮上下排列，保持原生卡片完整可见。
const NAVIGATION_WIDTH: float = 24.0

## 按 [param capacity] 初始化预算和原生显示位，返回稳定的节点顺序。
func _initialize_slots(capacity: int) -> Array[Control]:
	_capacity = capacity
	_slot_size = _placeholder_template.get_combined_minimum_size()
	_placeholder_template.hide()
	_initialize_navigation()
	_ensure_slot_count(_capacity)
	_refresh_display()
	return _placeholders

## 所有已选真实卡的预算消耗；免槽卡不挤掉普通卡，失效引用也不能释放预算。
func used_slot_count() -> int:
	var result: int = 0 # 卡片来源冻结配置是费用的唯一依据。
	for card: Card in curr_cards: # 同种不同 UID 分别拥有自己的占槽费用。
		result += card.selection_slot_cost() if is_instance_valid(card) else 1
	return result

## 判断是否能追加 [param card]；省略参数保持普通卡消耗一个槽的兼容行为。
func has_free_slot(card: Card = null) -> bool:
	var cost: int = card.selection_slot_cost() if is_instance_valid(card) else 1 # 非冒险卡默认不免槽。
	return CardSlotRules.is_valid_capacity(_capacity) and used_slot_count() + cost <= _capacity

## 将 [param card] 登记到真实出战末尾，成功后返回可挂载的显示位。
func append_card(card: Card) -> Control:
	if not is_instance_valid(card) or curr_cards.has(card) or not has_free_slot(card):
		return null
	_ensure_slot_count(maxi(_capacity, curr_cards.size() + 1))
	var slot: Control = slot_at(curr_cards.size()) # 真实顺序与免槽资格无关。
	curr_cards.append(card)
	_refresh_display()
	return slot

## 将 [param card] 移出队列并返回原下标，保留旧显示位供尚未完成的动画使用。
func remove_card(card: Card) -> int:
	var index: int = curr_cards.find(card) # 调用方从原位置开始平移后续卡片。
	if index >= 0:
		curr_cards.remove_at(index)
		_refresh_display()
	return index

## 返回已分配的 [param index] 对应节点，不按占槽预算重新排列卡片。
func slot_at(index: int) -> Control:
	return _placeholders[index]

## 把 [param slot] 所在的连续卡片窗口显示出来；节点身份和出战顺序均不变。
func reveal_slot(slot: Control) -> void:
	var index: int = _placeholders.find(slot) # 只能翻动本卡栏拥有的显示位。
	if index < 0:
		return
	if index < _first_visible_slot:
		_first_visible_slot = index
	elif index >= _first_visible_slot + _capacity:
		_first_visible_slot = index - _capacity + 1
	_refresh_display()

## [param hide_spare] 只影响空位显示，不改变预算、实际卡片或选卡顺序。
func _set_spare_slots_hidden(hide_spare: bool) -> void:
	_hide_spare = hide_spare
	_refresh_display()

## 至少提供 [param count] 个真实显示位；扩容不移动或复制已有卡片。
func _ensure_slot_count(count: int) -> void:
	while _placeholders.size() < count: # 免槽卡只增加节点，不增加普通卡预算。
		var placeholder: Control = _placeholder_template.duplicate() as Control # 模板永不挂载真实卡片。
		placeholder.show()
		_slot_row.add_child(placeholder)
		_placeholders.append(placeholder)

## 以原生宽度显示连续卡片窗口；额外卡可翻动访问，历史空位保留以保护重排动画。
func _refresh_display() -> void:
	if not is_instance_valid(_navigation):
		return
	var total: int = curr_cards.size() if _hide_spare else maxi(_capacity, curr_cards.size()) # 保留空位设置语义。
	var columns: int = mini(_capacity, total) # 原定卡栏尺寸不随免槽卡数量无限增长。
	var last_start: int = maxi(0, total - columns) # 删除卡后窗口不能停在不存在的尾部。
	_first_visible_slot = clampi(_first_visible_slot, 0, last_start)
	for index: int in range(_placeholders.size()): # 隐藏整个位，不裁剪卡片、星徽或按钮。
		_placeholders[index].visible = index >= _first_visible_slot and index < _first_visible_slot + columns
	var overflow: bool = total > columns # 按钮只占新增右边距，卡栏高度和候选区位置不变。
	_navigation.visible = overflow
	_navigation_buttons[0].disabled = _first_visible_slot <= 0
	_navigation_buttons[1].disabled = _first_visible_slot >= last_start
	_panel_style.set_content_margin(SIDE_RIGHT, _base_right_margin + (NAVIGATION_WIDTH + 4.0 if overflow else 0.0))
	reset_size()

## 创建独立背景边距和右侧翻动按钮，所有修改只影响当前卡栏实例。
func _initialize_navigation() -> void:
	_panel_style = get_theme_stylebox("panel").duplicate() as StyleBox
	_base_right_margin = _panel_style.get_content_margin(SIDE_RIGHT)
	add_theme_stylebox_override("panel", _panel_style)
	_navigation = Control.new()
	_navigation.name = "CardOverflowNavigation"
	_navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_navigation)
	var buttons := VBoxContainer.new() # 锚定在内容区右侧新增的背景边距内。
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.anchor_left = 1.0
	buttons.anchor_right = 1.0
	buttons.offset_left = 4.0
	buttons.offset_right = NAVIGATION_WIDTH + 4.0
	buttons.offset_bottom = _slot_size.y
	buttons.add_theme_constant_override("separation", 0)
	_navigation.add_child(buttons)
	for direction: int in [-1, 1]: # 上下两枚按钮分别翻向卡组前端与后端。
		var button := Button.new() # 独立点击区，不改变卡片按钮或快捷键顺序。
		button.text = "<" if direction < 0 else ">"
		button.tooltip_text = "查看前面的卡片" if direction < 0 else "查看后面的卡片"
		button.custom_minimum_size = Vector2(NAVIGATION_WIDTH, _slot_size.y * 0.5)
		button.add_theme_font_size_override("font_size", 16)
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		button.pressed.connect(_shift_view.bind(direction))
		buttons.add_child(button)
		_navigation_buttons.append(button)

## 按 [param direction] 翻动一个完整卡位，边界由当前真实卡片数量限制。
func _shift_view(direction: int) -> void:
	_first_visible_slot += direction
	_refresh_display()
