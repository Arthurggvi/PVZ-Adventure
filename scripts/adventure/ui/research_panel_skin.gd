## One scalable, purely visual research shell built from the existing inventory skin.
## No baked labels, data or mode-specific pictures in the shared background.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Preview = preload("res://scripts/adventure/ui/research_ui_meta.gd")
const DESIGN := Vector2(1920.0, 1080.0)
const FRAME := Rect2(55, 74, 1810, 948)
## 三个内容面板从页首木条下沿开始，底部与操作栏留出间距。
const CONTENT_TOP: float = 228.0
## 页首按钮移走后可用于内容的高度。
const CONTENT_HEIGHT: float = 873.0 - CONTENT_TOP
## 左侧候选格的面板边界。
const SELECTION_REGION := Rect2(112, CONTENT_TOP, 414, CONTENT_HEIGHT)
## 工作槽布局从中间面板边界计算。
const WORK_REGION := Rect2(544, CONTENT_TOP, 710, CONTENT_HEIGHT)
## 右侧信息布局的面板边界。
const INFO_REGION := Rect2(1270, CONTENT_TOP, 530, CONTENT_HEIGHT)
const CONTENT_REGIONS := [
	SELECTION_REGION,
	WORK_REGION,
	INFO_REGION
]

static func build(owner: Control, with_background: bool = false) -> Dictionary:
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.06, 0.04, 0.10 if with_background else 0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.add_child(shade)
	var canvas := Control.new()
	canvas.name = "ResearchCanvas"
	canvas.size = DESIGN
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.add_child(canvas)
	Art.panel(canvas, "panels/outer_frame_ninepatch.png", FRAME.position, FRAME.size, 42)
	Art.panel(canvas, "panels/wood_ninepatch.png", Vector2(100, 205), Vector2(1718, 683), 35)
	Art.panel(canvas, "panels/wood_ninepatch.png", Vector2(100, 110), Vector2(1718, 105), 35)
	Art.panel(canvas, "panels/wood_ninepatch.png", Vector2(110, 887), Vector2(1700, 106), 30)
	for region: Rect2 in CONTENT_REGIONS:
		Art.panel(canvas, "panels/parchment_ninepatch.png", region.position, region.size, 30)
	var coin := Art.label(canvas, "$0", Vector2(1450, 139), Vector2(280, 58), 26, Color("fae6b8")) # 金币只显示符号和数值。
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close := Art.button(canvas, "controls/close", Vector2(1731, 126),
		Vector2(74, 74), Callable(owner, "request_close"))
	close.name = "ResearchClose"
	var tabs: Dictionary = {}
	var labels := ["合成", "强化", "转职"]
	var icons := ["icons/category_recipes.png", "overlays/star_filled.png", "icons/category_plants.png"]
	for i in Preview.MODES.size():
		var key: String = Preview.MODES[i]
		var btn := Art.button(canvas, "tabs/tab", Vector2(116 + i * 210, 126.5),
			Vector2(196, 72), Callable(owner, "choose_mode").bind(key)) # 按原比例缩放，横排在页首左侧。
		btn.name = "ResearchTab_" + key
		Art.image(btn, icons[i], Vector2(18, 12), Vector2(48, 48))
		Art.label(btn, labels[i], Vector2(74, 14), Vector2(98, 47), 28)
		tabs[key] = btn
	var content := Control.new()
	content.name = "ResearchModeContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size = DESIGN
	canvas.add_child(content)
	var action := Art.button(canvas, "buttons/action_confirm", Vector2(1490, 899),
		Vector2(268, 82), Callable(owner, "perform_action"))
	action.name = "ResearchAction"
	action.texture_disabled = Art.texture("buttons/action_confirm_disabled.png")
	action.disabled = true
	var action_text := Art.label(action, "合成", Vector2(48, 10), Vector2(170, 65), 35)
	action_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return {"canvas": canvas, "tabs": tabs, "coin": coin, "content": content,
		"action": action, "action_text": action_text}
