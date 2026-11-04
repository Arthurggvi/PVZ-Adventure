## One scalable, purely visual research shell built from the existing inventory skin.
## No baked labels, data or mode-specific pictures in the shared background.
extends RefCounted
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
const Preview = preload("res://scripts/adventure/ui/research_preview_data.gd")
const DESIGN := Vector2(1920.0, 1080.0)
const FRAME := Rect2(55, 74, 1810, 948)
const CONTENT_REGIONS := [
	Rect2(112, 350, 414, 523),
	Rect2(544, 350, 710, 523),
	Rect2(1270, 350, 530, 523)
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
	Art.label(canvas, "植物研究所", Vector2(144, 128), Vector2(650, 85), 52, Color("f7e5af"))
	Art.image(canvas, "icons/currency_unified.png", Vector2(1515, 136), Vector2(57, 57))
	var coin := Art.label(canvas, "金币：—", Vector2(1581, 139), Vector2(149, 58), 26, Color("fae6b8"))
	coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close := Art.button(canvas, "controls/close", Vector2(1731, 126),
		Vector2(74, 74), Callable(owner, "request_close"))
	close.name = "ResearchClose"
	var tabs: Dictionary = {}
	var labels := ["合成", "强化", "转职"]
	var icons := ["icons/category_recipes.png", "overlays/star_filled.png", "icons/category_plants.png"]
	for i in Preview.MODES.size():
		var key: String = Preview.MODES[i]
		var btn := Art.button(canvas, "tabs/tab", Vector2(560 + i * 273, 237),
			Vector2(245, 90), Callable(owner, "choose_mode").bind(key))
		btn.name = "ResearchTab_" + key
		Art.image(btn, icons[i], Vector2(22, 15), Vector2(60, 60))
		Art.label(btn, labels[i], Vector2(93, 18), Vector2(122, 59), 35)
		tabs[key] = btn
	var content := Control.new()
	content.name = "ResearchModeContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size = DESIGN
	canvas.add_child(content)
	var status := Art.label(canvas, "展示界面 · 暂不消耗资源", Vector2(142, 906),
		Vector2(1060, 55), 25, Color("fae6b8"))
	var action := Art.button(canvas, "buttons/action_confirm", Vector2(1490, 899),
		Vector2(268, 82), Callable())
	action.name = "ResearchUnavailableAction"
	action.texture_disabled = Art.texture("buttons/action_confirm_disabled.png")
	action.disabled = true
	var action_text := Art.label(action, "合成", Vector2(48, 10), Vector2(170, 65), 35)
	action_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return {"canvas": canvas, "tabs": tabs, "coin": coin, "content": content,
		"status": status, "action": action, "action_text": action_text}
