## 教学遮罩只突出真实控件；高亮孔透传鼠标，业务动作仍由原按钮处理。
extends Control

## 用户可稍后继续，关闭本次提示不标记教学完成。
signal postponed
## 共用任务和背包的美术。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 当前实际控件，窗口销毁后自动收回点击孔。
var target: Control
## 操作型教学默认放行高亮目标；暂停中的纯说明可关闭透传，避免误操作。
var allow_target_input := true
## 提示卡片及其文字。
var _card: Control
## 背板随公告/短提示两种布局缩放，避免遮住大半个奖励或合成面板。
var _panel: NinePatchRect
## 多行教学说明。
var _text: Label
## 无目标时的确认按钮。
var _action: Button
## 暂缓按钮在短提示中居中显示。
var _later: Button
## 呼吸边框的相位，以真实帧时间推进。
var _elapsed := 0.0
## 当前目标在视口内的矩形。
var _hole := Rect2()

## 构建统一提示卡，初始隐藏，调用 present 后显示。
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = preload("res://assets/fonts/方正少儿_GBK.ttf")
	_card = Control.new()
	_card.size = Vector2(600, 220)
	add_child(_card)
	_panel = Art.panel(_card, "panels/wood_ninepatch.png", Vector2.ZERO, _card.size, 30)
	_text = Art.label(_card, "", Vector2(30, 20), Vector2(540, 110), 28, Color("ffedba"))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action = Art.action_button(_card, "继续", "buttons/action_confirm", Vector2(320, 146), Vector2(240, 56), Callable())
	_later = Art.action_button(_card, "稍后继续", "buttons/action_neutral", Vector2(40, 146), Vector2(240, 56), func(): postponed.emit())
	hide()

## 展示 [param message] 并突出 [param control]；无目标时用 [param action] 和 [param caption] 确认。
func present(message: String, control: Control = null, action: Callable = Callable(), caption: String = "继续") -> void:
	target = control
	_text.text = message
	_action.text = caption
	_action.visible = action.is_valid()
	_card.size = Vector2(600, 220) if action.is_valid() else Vector2(480, 150)
	_panel.size = _card.size
	_text.size = Vector2(540, 110) if action.is_valid() else Vector2(420, 68)
	_text.add_theme_font_size_override("font_size", 28 if action.is_valid() else 23)
	_later.position = Vector2(40, 146) if action.is_valid() else Vector2(140, 96)
	_later.size = Vector2(240, 56) if action.is_valid() else Vector2(200, 42)
	_later.add_theme_font_size_override("font_size", 28 if action.is_valid() else 22)
	for connection: Dictionary in _action.pressed.get_connections(): # 每个步骤只有一个确认回调。
		_action.pressed.disconnect(connection.callable)
	if action.is_valid():
		_action.pressed.connect(action)
	if not visible:
		modulate.a = 0.0
		show()
		create_tween().tween_property(self, "modulate:a", 1.0, 0.28)
	_layout()

## 随 [param delta] 更新动画和按钮的真实位置，适应工具栏滑出及窗口缩放。
func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	_layout()
	queue_redraw()

## 提示卡优先放在目标上方；顶部页签空间不足时放到下方，避免挡住高亮。
func _layout() -> void:
	var factor := minf(size.x / 1066.0, size.y / 600.0) # 和游戏逻辑分辨率保持同等阅读比例。
	_card.scale = Vector2.ONE * factor
	var dimensions: Vector2 = _card.size * factor # 实际提示卡尺寸。
	_hole = target.get_global_rect().grow(7.0 * factor) if is_instance_valid(target) and target.is_visible_in_tree() else Rect2()
	var center: Vector2 = _hole.get_center() if _hole.has_area() else size * 0.5 # 无目标时用中央解锁公告。
	var top: float = _hole.position.y - dimensions.y - 28.0 * factor # 给高亮和提示卡之间留出呼吸空间。
	if top < 12.0 and _hole.end.y + dimensions.y + 24.0 * factor <= size.y - 12.0:
		top = _hole.end.y + 24.0 * factor
	_card.position = Vector2(clampf(center.x - dimensions.x * 0.5, 12.0, maxf(12.0, size.x - dimensions.x - 12.0)),
		clampf(top, 12.0, maxf(12.0, size.y - dimensions.y - 12.0))) if _hole.has_area() else (size - dimensions) * 0.5

## [param point] 是遮罩局部坐标；操作型教学仅放行高亮孔，说明型教学拦截整张遮罩。
func _has_point(point: Vector2) -> bool:
	return not allow_target_input or not _hole.has_area() or not _hole.has_point(point)

## 四块遮幕保留目标原样显示，金色边框与箭头持续轻微跳动。
func _draw() -> void:
	var shade := Color(0.02, 0.035, 0.02, 0.64) # 与原戴夫遮幕相近的暗绿色。
	if not _hole.has_area():
		draw_rect(Rect2(Vector2.ZERO, size), shade)
		return
	var bounds: Rect2 = _hole.intersection(Rect2(Vector2.ZERO, size)) # 动画途中可能部分超出视口。
	draw_rect(Rect2(0, 0, size.x, maxf(0, bounds.position.y)), shade)
	draw_rect(Rect2(0, bounds.end.y, size.x, maxf(0, size.y - bounds.end.y)), shade)
	draw_rect(Rect2(0, bounds.position.y, maxf(0, bounds.position.x), bounds.size.y), shade)
	draw_rect(Rect2(bounds.end.x, bounds.position.y, maxf(0, size.x - bounds.end.x), bounds.size.y), shade)
	var gold := Color(1.0, 0.84, 0.32, 0.8 + 0.2 * sin(_elapsed * 4.0)) # 边框亮度呼吸。
	draw_rect(_hole, gold, false, 3.0)
	var below: bool = _card.position.y >= _hole.end.y # 顶部头像的提示卡在下方，箭头不能画到屏幕外。
	var direction: float = 1.0 if below else -1.0 # 箭尾始终朝向说明卡，箭尖朝真实目标。
	var edge: float = _hole.end.y if below else _hole.position.y # 对应提示卡一侧的高亮边缘。
	var tip := Vector2(_hole.get_center().x, edge + direction * (8.0 + 5.0 * sin(_elapsed * 5.0))) # 真实目标旁的轻微跳动。
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-10, direction * 14), tip + Vector2(10, direction * 14)]), gold)
