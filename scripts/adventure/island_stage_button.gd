## 单个地图节点的图片、标签、锁定灰显与标题悬停反馈。
extends TextureButton

## UI 构造工具。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 锁定图标的非破坏性灰度材质，文字层保持原色。
const LOCKED_SHADER = preload("res://shaders/adventure/locked_stage.gdshader")
## 关卡标题，悬停反馈只作用于该文字层。
var title_label: Label
## 来自当前玩家真实进度的开放状态；锁定节点禁用交互。
var is_unlocked := false

## [param stage] 来自 layout.json；[param unlocked] 控制名称揭示，锁定节点禁用交互。
## [param _cleared] 保留既有调用签名，不再显示通关状态文字；[param callback] 负责地图层的导航判断。
## [param label_offsets] 由地图一次性读取；独立编辑器/验收入口可省略并使用原布局。
func configure(stage: Dictionary, unlocked: bool, _cleared: bool, callback: Callable,
		label_offsets: Dictionary = {}) -> void:
	texture_normal = load("res://assets/adventure/zombie_island/" + stage.button)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	size = Vector2(200, 200)
	pivot_offset = size / 2
	position = Vector2(stage.position_normalized[0] * 1920, stage.position_normalized[1] * 1080) - pivot_offset
	is_unlocked = unlocked
	# 锁定节点从控件层阻断鼠标、键盘与快捷键触发，保留灰显和问号标题。
	disabled = not unlocked
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	if not is_unlocked:
		# 材质只作用于按钮自身绘制，不修改 PNG，也不影响子 Label。
		var grayscale := ShaderMaterial.new()
		grayscale.shader = LOCKED_SHADER
		material = grayscale
	# 文字偏移独立配置，避开相邻节点和底部提示；节点中心仍取原 layout.json。
	var offsets: Dictionary = label_offsets # 正式地图复用传入数据，不逐按钮重读 JSON。
	if offsets.is_empty():
		offsets = JSON.parse_string(FileAccess.get_file_as_string("res://resources/adventure/island_label_offsets.json"))
	var configured: Array = offsets.get(str(int(stage.id)), [0, 0]) # 未配置时沿用下方标签。
	var shift := Vector2(configured[0], configured[1]) # 只作用于文字层。
	title_label = UI.label(self, stage.name if unlocked else "？", Rect2(Vector2(-70, 202) + shift, Vector2(340, 48)), 36)
	mouse_entered.connect(_update_title_highlight)
	mouse_exited.connect(_update_title_highlight)
	pressed.connect(callback)

## 已开放节点悬停时仅高亮自己的标题；移出后恢复，锁定节点始终没有特效。
func _update_title_highlight() -> void:
	title_label.add_theme_color_override("font_color",
		Color.YELLOW if is_unlocked and is_hovered() else Color.WHITE)
