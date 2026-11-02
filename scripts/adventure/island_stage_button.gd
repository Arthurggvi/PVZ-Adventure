## 单个地图节点的图片、标签、锁定灰显与标题悬停反馈。
extends TextureButton

## UI 构造工具。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 锁定图标的非破坏性灰度材质，文字层保持原色。
const LOCKED_SHADER = preload("res://shaders/adventure/locked_stage.gdshader")
## 关卡标题，悬停反馈只作用于该文字层。
var title_label: Label
## 当前关卡是否开放；锁定节点仍可点击查看解锁提示。
var is_unlocked := false

## [param stage] 来自 layout.json；[param unlocked] 控制状态文案，锁定节点仍可点击。
## [param cleared] 为通关状态；[param callback] 负责地图层的导航判断。
func configure(stage: Dictionary, unlocked: bool, cleared: bool, callback: Callable) -> void:
	texture_normal = load("res://assets/adventure/zombie_island/" + stage.button)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	size = Vector2(200, 200)
	pivot_offset = size / 2
	position = Vector2(stage.position_normalized[0] * 1920, stage.position_normalized[1] * 1080) - pivot_offset
	is_unlocked = unlocked
	# 锁定节点从控件层阻断鼠标、键盘与快捷键触发，保留独立未解锁文字。
	disabled = not unlocked or int(stage.id) != 1
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	if not is_unlocked:
		# 材质只作用于按钮自身绘制，不修改 PNG，也不影响子 Label。
		var grayscale := ShaderMaterial.new()
		grayscale.shader = LOCKED_SHADER
		material = grayscale
	# 文字偏移独立配置，避开相邻节点和底部提示；节点中心仍取原 layout.json。
	var offsets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/adventure/island_label_offsets.json"))
	var configured: Array = offsets.get(str(int(stage.id)), [0, 0]) # 未配置时沿用下方标签。
	var shift := Vector2(configured[0], configured[1]) # 只作用于文字层。
	title_label = UI.label(self, stage.name, Rect2(Vector2(-70, 202) + shift, Vector2(340, 48)), 36)
	# 状态为独立 Label，图片中不包含数字、文字或锁头。
	var status := "已通关" if cleared else ("可挑战" if stage.id == 1 else "已开放 · 待建设")
	if not unlocked:
		status = "未解锁"
	UI.label(self, status, Rect2(Vector2(-50, 250) + shift, Vector2(300, 38)), 27)
	mouse_entered.connect(_update_title_highlight)
	mouse_exited.connect(_update_title_highlight)
	pressed.connect(callback)

## 已开放节点悬停时仅高亮自己的标题；移出后恢复，锁定节点始终没有特效。
func _update_title_highlight() -> void:
	title_label.add_theme_color_override("font_color",
		Color.YELLOW if is_unlocked and is_hovered() else Color.WHITE)
