## 调色期间把教堂战斗 HUD 绘到透明视口，保留原有的控件树和交互。
extends CanvasLayer

## 卡槽、阳光和战斗工具的画布层。
@export var card_layer: CanvasLayer
## 菜单、旗帜和其余战斗 HUD 的前景画布层。
@export var battle_hud: CanvasLayer

## HUD 原本所在的主视口，决定逻辑尺寸、拉伸和输入。
@onready var _host: Viewport = get_viewport()
## 只接收 HUD 绘制的透明视口。
@onready var _surface: SubViewport = $HudViewport
## 在世界上方合成已调色的 HUD。
@onready var _grade: ColorRect = $Grade
## 本场局部材质，保留纹理原有的透明度。
@onready var _material: ShaderMaterial = _grade.material

## 绑定 HUD 纹理，并同步主视口运行中的尺寸变化。
func _ready() -> void:
	_host.size_changed.connect(_resize_surface)
	_material.set_shader_parameter("hud_texture", _surface.get_texture())

## 阶段退出时先把两个画布交还主视口，再释放临时的绘制目标。
func _exit_tree() -> void:
	if is_instance_valid(_grade) and _grade.visible:
		_set_grading(false)

## [param darkness] 从零到一推进变暗和退色。回到零时恢复直接绘制。
func set_darkness(darkness: float) -> void:
	var enabled: bool = darkness > 0.0 # 明亮阶段无需绘制额外视口。
	if enabled != _grade.visible:
		_set_grading(enabled)
	if enabled:
		_material.set_shader_parameter("darkness", darkness)

## [param enabled] 决定两个 HUD 层的绘制目标，控件仍使用主视口接收鼠标和键盘输入。
func _set_grading(enabled: bool) -> void:
	_grade.visible = enabled
	_resize_surface()
	var target: Viewport = _surface if enabled else _host # 常亮时用主视口恢复原有绘制。
	if is_instance_valid(card_layer) and card_layer.is_inside_tree():
		card_layer.custom_viewport = target
	if is_instance_valid(battle_hud) and battle_hud.is_inside_tree():
		battle_hud.custom_viewport = target
	_surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

## 匹配窗口的逻辑尺寸及实际像素密度，使 HUD 在缩放后仍保持锐利。
func _resize_surface() -> void:
	if not _grade.visible:
		return
	var logical: Vector2 = _host.get_visible_rect().size # 主视口中控件锚点使用的逻辑尺寸。
	var physical: Vector2 = logical * _host.get_stretch_transform().get_scale() # HUD 纹理按实际像素绘制。
	_surface.size_2d_override = Vector2i(logical.round())
	_surface.size = Vector2i(physical.round()).max(Vector2i(2, 2))
