## 单个地图节点的图片、标签、锁定覆盖层和交互动画。
extends TextureButton

## UI 构造工具。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 当前悬停动画；进入与离开时结束旧动画，防止比例累积。
var motion: Tween
## 独立描边覆盖层。
var halo: Panel
## 是否处于鼠标悬停状态。
var hovered := false

## [param stage] 来自 layout.json；[param unlocked] 控制状态文案，锁定节点仍可点击。
## [param cleared] 为通关状态；[param callback] 负责地图层的导航判断。
func configure(stage: Dictionary, unlocked: bool, cleared: bool, callback: Callable) -> void:
	texture_normal = load("res://assets/adventure/zombie_island/" + stage.button)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	size = Vector2(200, 200)
	pivot_offset = size / 2
	position = Vector2(stage.position_normalized[0] * 1920, stage.position_normalized[1] * 1080) - pivot_offset
	tooltip_text = stage.name + ("：点击进入" if stage.id == 1 else "：点击查看")
	halo = Panel.new()
	halo.position = Vector2(4, 4)
	halo.size = Vector2(192, 192)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 描边独立于底图，保持基础贴图原色。
	var style := UI.panel_style(Color.TRANSPARENT)
	style.set_corner_radius_all(96)
	style.set_border_width_all(5)
	style.border_color = Color("fff0a6")
	halo.add_theme_stylebox_override("panel", style)
	halo.visible = false
	add_child(halo)
	# 文字偏移独立配置，避开相邻节点和底部提示；节点中心仍取原 layout.json。
	var offsets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/adventure/island_label_offsets.json"))
	var configured: Array = offsets.get(str(int(stage.id)), [0, 0]) # 未配置时沿用下方标签。
	var shift := Vector2(configured[0], configured[1]) # 只作用于文字层。
	UI.label(self, "%d  %s" % [stage.id, stage.name], Rect2(Vector2(-70, 202) + shift, Vector2(340, 48)), 36)
	# 状态为独立 Label，图片中不包含数字、文字或锁头。
	var status := "已通关" if cleared else ("可挑战" if stage.id == 1 else "已开放 · 待建设")
	if not unlocked:
		status = "未解锁"
	UI.label(self, status, Rect2(Vector2(-50, 250) + shift, Vector2(300, 38)), 27)
	mouse_entered.connect(func():
		hovered = true
		halo.show()
		_animate(1.06))
	mouse_exited.connect(func():
		hovered = false
		halo.hide()
		_animate(1.0))
	focus_entered.connect(halo.show)
	focus_exited.connect(halo.hide)
	button_down.connect(func(): _animate(0.94))
	button_up.connect(func(): _animate(1.06 if hovered else 1.0))
	pressed.connect(callback)

## 在 0.15 秒内将按钮缩放到 [param factor]，保持中心不变。
func _animate(factor: float) -> void:
	if motion != null:
		motion.kill()
	motion = create_tween()
	motion.tween_property(self, "scale", Vector2.ONE * factor, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
