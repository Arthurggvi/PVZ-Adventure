## 单地区卡片：预览、禁用层、完整相框、交互状态与运行时名称保持独立。
extends TextureButton

## 布局与受控路由许可适配器。
const Catalog = preload("res://scripts/adventure/destination_catalog.gd")
## 当前开放卡片的状态纹理；透明 normal 也保留配置资源。
var _states: Dictionary = {}

## 根据 [param destination] 和共享 [param card_layout] 设置已有可编辑节点，不读写存档。
func configure(destination: Dictionary, card_layout: Dictionary) -> void:
	position = Catalog.rect(destination.rect).position
	size = Catalog.rect(destination.rect).size
	disabled = not Catalog.can_enter(destination)
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	tooltip_text = destination.name + ("（尚未开放）" if disabled else "")
	$Preview.position = Vector2(card_layout.preview_offset[0], card_layout.preview_offset[1])
	$Preview.size = Vector2(card_layout.preview_size[0], card_layout.preview_size[1])
	$Preview.texture = load(Catalog.ROOT + destination.preview)
	$Frame.texture = load(Catalog.ROOT + destination.frame)
	$DisabledOverlay.visible = disabled and destination.has("disabled_overlay")
	if destination.has("disabled_overlay"):
		$DisabledOverlay.texture = load(Catalog.ROOT + destination.disabled_overlay)
	# 固定文字安全框不接受字体最小行高撑大；内部 Label 双向居中并裁剪在配置范围。
	$NameBounds.position = Catalog.rect(card_layout.label_rect_local).position
	$NameBounds.size = Catalog.rect(card_layout.label_rect_local).size
	$NameBounds/NameLabel.text = destination.name
	$NameBounds/NameLabel.add_theme_font_size_override("font_size", int(card_layout.label_font_size))
	_states.clear()
	if destination.has("states_prefix"):
		for state: String in ["normal", "hover", "pressed"]: # 三种原始美术状态均作为相框上方的独立图层。
			_states[state] = load(Catalog.ROOT + destination.states_prefix + state + ".png")
	_refresh_state()

## 鼠标、键盘焦点和确认均驱动同一组状态，禁用卡片没有可操作焦点。
func _ready() -> void:
	for changed: Signal in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up]: # 生命周期内只绑定一次。
		changed.connect(_refresh_state)
	_refresh_state()

## 刷新独立状态层；名称始终在最上方，不被按下层或灰色遮罩覆盖。
func _refresh_state() -> void:
	$ActiveState.visible = not disabled and not _states.is_empty()
	if _states.is_empty():
		return
	var state := "pressed" if is_pressed() else ("hover" if is_hovered() or has_focus() else "normal") # 焦点等同悬停提示。
	$ActiveState.texture = _states[state]
