## 战外左上角档案组件，展示当前角色头像和等级；导航动作由宿主注入。
extends Control

## 复用头像贴图、文字和导航按钮构造。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 与角色面板共享时装选择及头像裁切。
const PortraitArt = preload("res://scripts/adventure/ui/player_portrait_art.gd")
## 战外界面统一的设计分辨率，用于计算头像框缩放。
const DESIGN_SIZE := Vector2(1920, 1080)
## 头像、名字和下方按钮一起缩小一成，维持相对布局。
const HUD_SCALE := 0.9
## 设计分辨率下的头像框尺寸。
const FRAME_SIZE := Vector2(390, 224)
## 海滨菜单原画坐标中的紧凑档案尺寸，不影响地图和战斗布局。
const COASTAL_FRAME_SIZE := Vector2(296, 118)
## 从原立绘截取头肩的贴图。
var _avatar: TextureRect
## 共用等级角标，未选择存档时隐藏。
var _badge: PlayerLevelBadge
## 当前档案名称，过长时省略尾部。
var _player_name: Label
## 战斗 HUD 是否改为贴左上角停靠；菜单和地图仍保持原位置。
var _dock_top_left := false
## 左上角停靠时与视口边缘的间距。
var _dock_margin := 12.0
## 战斗 HUD 允许的最大设计宽度，用于卡在阳光槽左侧。
var _max_width := 0.0
## 可选父画布缩放；负值继续使用原来的视口自适配。
var _canvas_scale := -1.0
## 动作按钮默认在头像下方，菜单可显式放在右侧。
var _action_origin := Vector2(12, FRAME_SIZE.y + 10)
## 仅由海滨主菜单在入树前启用的紧凑暖色表现。
var _coastal_presentation := false

## 创建宿主选定的头像表现，并绑定同一套真实档案与角色变化。
func _ready() -> void:
	name = "AdventureProfileHud"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _coastal_presentation:
		_build_coastal_presentation()
	else:
		_build_default_presentation()
	# 用户索引信号在档案加载前触发，下一轮读取已经完成切换的角色状态。
	Global.user_manager.signal_users_update.connect(_refresh, Object.CONNECT_DEFERRED)
	Global.player_changed.connect(_refresh)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	_refresh()

## 保留地图与战斗既有头像、名字及等级角标的尺寸和样式。
func _build_default_presentation() -> void:
	size = FRAME_SIZE
	var backdrop := Panel.new() # 半透明底压低背景细节，让头像保持清楚。
	var style := StyleBoxFlat.new() # 四边描边，靠视口的两个角保持直角。
	style.bg_color = Color(0.055, 0.09, 0.12, 0.84)
	style.border_color = Color(0.62, 0.74, 0.79, 0.88)
	style.set_border_width_all(3)
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_right = 14
	backdrop.add_theme_stylebox_override("panel", style)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar = Art.image(self, "", Vector2(16, 16), Vector2(358, 154))
	_avatar.name = "Avatar"
	_player_name = Art.label(self, "", Vector2(44, 174), Vector2(302, 36), 26, Color("edf3f4"))
	_player_name.name = "PlayerName"
	_player_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_player_name.add_theme_color_override("font_shadow_color", Color("15202a"))
	var name_style := style.duplicate() as StyleBoxFlat # 名字单独有框，与头像框使用同一套描边色。
	name_style.bg_color = Color(0.105, 0.16, 0.205, 0.94)
	name_style.set_border_width_all(2)
	name_style.set_corner_radius_all(7)
	name_style.content_margin_left = 12
	name_style.content_margin_right = 12
	_player_name.add_theme_stylebox_override("normal", name_style)
	_badge = PlayerLevelBadge.new()
	_badge.name = "LevelBadge"
	_badge.position = Vector2(254, 17)
	_badge.size = Vector2(116, 73)
	add_child(_badge)

## 构造海滨专用的暖黑小卡片，头像与操作均收在卡片内部。
func _build_coastal_presentation() -> void:
	size = COASTAL_FRAME_SIZE
	var backdrop := Panel.new() # 暖黑半透明底保留港湾景色的色彩。
	var style := StyleBoxFlat.new() # 单像素旧黄铜边线减轻界面的视觉重量。
	style.bg_color = Color(0.075, 0.069, 0.055, 0.86)
	style.border_color = Color(0.60, 0.48, 0.30, 0.70)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.02, 0.018, 0.012, 0.20)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	backdrop.add_theme_stylebox_override("panel", style)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var portrait_backdrop := Panel.new() # 头像内底与边线呼应卡片，现有立绘保留透明区域。
	var portrait_style := StyleBoxFlat.new() # 内侧圆角只作为头像衬底，不改变原始纹理。
	portrait_style.bg_color = Color(0.18, 0.16, 0.115, 0.76)
	portrait_style.border_color = Color(0.59, 0.47, 0.28, 0.40)
	portrait_style.set_border_width_all(1)
	portrait_style.set_corner_radius_all(9)
	portrait_backdrop.position = Vector2(8, 8)
	portrait_backdrop.size = Vector2(102, 102)
	portrait_backdrop.add_theme_stylebox_override("panel", portrait_style)
	portrait_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait_backdrop)
	_avatar = Art.image(self, "", Vector2(10, 10), Vector2(98, 98))
	_avatar.name = "Avatar"
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_player_name = Art.label(self, "", Vector2(124, 19), Vector2(160, 30), 21, Color("f1e6cc"))
	_player_name.name = "PlayerName"
	_player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_player_name.add_theme_color_override("font_shadow_color", Color(0.025, 0.021, 0.014, 0.78))
	var divider := ColorRect.new() # 细短分隔线将姓名与等级、存档动作分开。
	divider.position = Vector2(124, 53)
	divider.size = Vector2(160, 1)
	divider.color = Color(0.65, 0.52, 0.32, 0.25)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)
	_badge = PlayerLevelBadge.new()
	_badge.name = "LevelBadge"
	_badge.position = Vector2(123, 61)
	_badge.size = Vector2(116, 73)
	_badge.scale = Vector2(68.0 / 116.0, 43.0 / 73.0) # 等级图与超出素材范围的文字同时缩入 68×43。
	add_child(_badge)

## 随视口等比调整尺寸，默认左上角由场景根节点的锚点定位。
func _fit_viewport() -> void:
	if _canvas_scale > 0.0:
		scale=Vector2.ONE*_canvas_scale
		return
	var viewport_size := get_viewport().get_visible_rect().size # 包含宽屏布局的两侧留空。
	var factor := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y) # 保持组件内的统一比例。
	var fitted_scale := factor * HUD_SCALE # 地图与战斗沿用既有九成缩放。
	if _max_width > 0.0: # 不超过阳光槽左侧的可用宽度，宽高仍按原图比例缩放。
		fitted_scale = minf(fitted_scale, _max_width / FRAME_SIZE.x)
	scale = Vector2.ONE * fitted_scale
	if _dock_top_left: # 战斗 HUD 贴左上角，右侧给阳光槽留出空隙。
		position = Vector2(_dock_margin, _dock_margin)

## 将头像框改贴左上角并限制最大宽度；由战斗 HUD 在加入场景后调用。
func dock_top_left(max_width: float, margin: float = 12.0) -> void:
	_dock_top_left = true
	_dock_margin = margin
	_max_width = max_width
	pivot_offset = Vector2.ZERO # 左上角固定，缩放只向右下延伸。
	_fit_viewport()

## 添加宿主的 [param caption] 动作并连接 [param callback]；海滨按钮收在卡片右下角。
func add_action(caption: String, callback: Callable) -> void:
	if _coastal_presentation:
		_add_coastal_action(caption, callback)
		return
	var button_size := Vector2(270, 62) # 与地图原有返回按钮宽度一致。
	var button := Art.action_button(self, caption, "buttons/action_neutral",
		_action_origin, button_size, callback) # 靠左避开地图第一个关卡的标题。
	button.name = "Action"
	button.add_theme_font_size_override("font_size", 32)

## 在卡片内添加 [param caption] 小按钮；有效的 [param callback] 使用原有宿主入口。
func _add_coastal_action(caption: String, callback: Callable) -> void:
	var button := Button.new() # 使用原生焦点和点击信号，紧凑样式不引入额外操作层。
	button.name = "Action"
	button.text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color("e7d7b5"))
	button.add_theme_color_override("font_hover_color", Color("fff1d1"))
	button.add_theme_color_override("font_pressed_color", Color("f0dfb8"))
	button.add_theme_color_override("font_focus_color", Color("fff1d1"))
	button.add_theme_color_override("font_disabled_color", Color("8b8069"))
	button.add_theme_constant_override("outline_size", 0)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]: # 各交互状态保持低饱和暖色。
		var style := StyleBoxFlat.new() # 独立状态样式避免悬停时影响卡片或其他入口。
		style.bg_color = Color(0.31, 0.25, 0.16, 0.58)
		style.border_color = Color(0.65, 0.52, 0.32, 0.64)
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		if state == "hover":
			style.bg_color = Color(0.42, 0.33, 0.20, 0.79)
			style.border_color = Color(0.78, 0.64, 0.40, 0.88)
		elif state == "pressed":
			style.bg_color = Color(0.21, 0.17, 0.11, 0.90)
		elif state == "disabled":
			style.bg_color = Color(0.15, 0.14, 0.11, 0.55)
			style.border_color = Color(0.42, 0.37, 0.27, 0.45)
		elif state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color(0.88, 0.73, 0.46, 0.95)
		button.add_theme_stylebox_override(state, style)
	if callback.is_valid():
		button.pressed.connect(callback)
	add_child(button)
	button.position = _action_origin
	button.size = Vector2(76, 34)

## 同步已成功加载的档案；访客使用默认头像且不显示虚构等级。
func _refresh() -> void:
	var loaded: bool = Global.save_service.is_current_profile_loaded() # 选择器可能正在切换或回滚档案。
	var portrait: Texture2D = PortraitArt.DEFAULT_PORTRAIT # 无档案也保留固定头像布局。
	_player_name.text = Global.user_manager.curr_user_name if loaded else "未选择存档"
	_badge.visible = loaded
	if loaded:
		var state: AdventureState = Global.global_game_state.adventure_state # 当前档案已确认有效。
		var equipment := PlayerEquipmentService.new(state.equipment) # 由装备服务判断时装的有效装配状态。
		portrait = PortraitArt.resolve(equipment.rows(EquipmentDefinition.Slot.OUTFIT))
		_badge.present(int(PlayerProgression.progress(state.experience).level))
	_avatar.texture = PortraitArt.head_crop(portrait)

## [param factor] 使用宿主原画比例；[param action_position] 为本组件局部按钮位置。
func configure_canvas_layout(factor: float, action_position: Vector2) -> void:
	_canvas_scale=factor
	_action_origin=action_position
	if is_node_ready():
		_fit_viewport()

## 海滨主菜单在加入场景树前显式启用；原画尺寸为 296×118，宿主负责卡片位置。
## 已进入场景树时不重建控件，避免重复档案信号和宿主动作。
func configure_coastal_presentation() -> void:
	if is_inside_tree():
		return
	_coastal_presentation = true
	_canvas_scale = 1.0
	_action_origin = Vector2(208, 70)
