## 左上角玩家档案组件，展示当前角色头像和等级；导航动作与战斗皮肤由宿主注入。
extends Control

## 复用头像贴图、文字和导航按钮构造。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 与角色面板共享已装配的时装，并为档案框生成取景。
const PortraitArt = preload("res://scripts/adventure/ui/player_portrait_art.gd")
## 只在人物外沿做渐隐，使立绘接入各样式的底图。
const PORTRAIT_BLEND = preload("res://shaders/adventure/profile_portrait.gdshader")
## 战外界面统一的设计分辨率，用于计算头像框缩放。
const DESIGN_SIZE := Vector2(1920, 1080)
## 头像、名字和下方按钮一起缩小一成，维持相对布局。
const HUD_SCALE := 0.9
## 设计分辨率下的头像框尺寸。
const FRAME_SIZE := Vector2(390, 224)
## 两种战斗外观共用的绘图尺寸；形状贴合神殿原画的长宽比。
const BATTLE_FRAME_SIZE := Vector2(400, 244)
## 海滨菜单原画坐标中的紧凑档案尺寸，不影响地图和战斗布局。
const COASTAL_FRAME_SIZE := Vector2(296, 118)
## 从原立绘重新取景的头像控件，战斗宿主也在这里绑定技能热区。
var _avatar: TextureRect
## 共用等级角标，未选择存档时隐藏。
var _badge: PlayerLevelBadge
## 当前档案名称，过长时省略尾部。
var _player_name: Label
## 战斗画布内的固定头像框宽度，0 表示沿用战外视口自适配。
var _battle_width: float = 0.0
## 战斗画布内的左上留白，单位为逻辑像素。
var _battle_margin: float = 0.0
## 可选父画布缩放；负值继续使用原来的视口自适配。
var _canvas_scale := -1.0
## 动作按钮默认在头像下方，菜单可显式放在右侧。
var _action_origin := Vector2(12, FRAME_SIZE.y + 10)
## 仅由海滨主菜单在入树前启用的紧凑暖色表现。
var _coastal_presentation := false
## 战斗宿主选出的神殿皮肤；为空时沿用原来的档案布局。
var _valhalla: ValhallaBattleSkin
## 神殿横幅的独立材质，供开战时点亮中央圣印和外框。
var _valhalla_finish: ShaderMaterial
## 挂在档案控件上的单次入场渐显，跨关卡阶段可重播。
var _valhalla_entrance: Tween

## 创建宿主选定的头像表现，并绑定同一套真实档案与角色变化。
func _ready() -> void:
	name = "AdventureProfileHud"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _coastal_presentation:
		_build_coastal_presentation()
	elif _valhalla != null:
		_build_valhalla_presentation()
	else:
		_build_default_presentation()
	# 用户索引信号在档案加载前触发，下一轮读取已经完成切换的角色状态。
	Global.user_manager.signal_users_update.connect(_refresh, Object.CONNECT_DEFERRED)
	Global.player_changed.connect(_refresh)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	_refresh()

## 只读提供已构建的头像控件；交互行为由宿主自行装配，共享档案不持有业务动作。
func avatar_control() -> Control:
	return _avatar

## 战斗宿主在入树前设置统一的 [param width]、[param margin] 和可选 [param skin]。
## 组件已入树时保留当前布局，避免重建正在使用的技能热区。
func configure_battle_layout(width: float, margin: float, skin: ValhallaBattleSkin) -> void:
	if is_inside_tree():
		return
	_battle_width = width
	_battle_margin = margin
	_valhalla = skin

## 在 [param bounds] 内等比绘制人物，渐隐肩部和取景框外沿。
func _build_avatar(bounds: Rect2) -> void:
	_avatar = Art.image(self, "", bounds.position, bounds.size)
	_avatar.name = &"Avatar"
	_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var blend := ShaderMaterial.new() # 每套布局以自己的逻辑尺寸归一化渐隐范围。
	blend.shader = PORTRAIT_BLEND
	blend.set_shader_parameter("extent", bounds.size)
	_avatar.material = blend

## 从背景、真实角色、金边和原生文字构造参考图的神殿档案横幅。
func _build_valhalla_presentation() -> void:
	size = BATTLE_FRAME_SIZE
	_valhalla.add_hall(self, false)
	_build_avatar(Rect2(97, 43, 206, 141))
	# 原版数字保留贴图与等级配色。将原图自带的底部标记对齐在画框的新羽翼后面。
	_badge = PlayerLevelBadge.new()
	_badge.name = "LevelBadge"
	_badge.position = Vector2(266, 63)
	_badge.size = Vector2(70, 48)
	_badge.fallback_font_size = 21
	add_child(_badge)
	_valhalla_finish = _valhalla.add_frame(self, false)
	_player_name = _valhalla.add_nameplate(self)
	visibility_changed.connect(_reveal_valhalla)

## 战斗档案出现时柔和点亮画框和文字，让开场红字先退完。
func _reveal_valhalla() -> void:
	if is_visible_in_tree():
		if _valhalla_entrance != null:
			_valhalla_entrance.kill()
		_valhalla_entrance = ValhallaBattleSkin.reveal(self)
		_valhalla_finish.set_shader_parameter("flare", 1.0)
		_valhalla_entrance.parallel().tween_property(_valhalla_finish, "shader_parameter/flare", 0.0, 0.82)

## 共用地图与普通战斗的档案外观，战斗里把原有内层布置居中放入统一画框。
func _build_default_presentation() -> void:
	size = BATTLE_FRAME_SIZE if _battle_width > 0.0 else FRAME_SIZE
	var inset: Vector2 = (size - FRAME_SIZE) * 0.5 # 战斗加大边框后保留头像、名字和等级之间的间距。
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
	# 横向留出发饰和持物的空间，让肩部渐隐在铭牌上沿。
	_build_avatar(Rect2(inset + Vector2(64, 12), Vector2(184, 162)))
	_player_name = Art.label(self, "", inset + Vector2(44, 174), Vector2(302, 36), 26, Color("edf3f4"))
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
	_badge.position = inset + Vector2(254, 17)
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
	var portrait_style := StyleBoxFlat.new() # 内侧圆角承接头像边缘的渐隐。
	portrait_style.bg_color = Color(0.18, 0.16, 0.115, 0.76)
	portrait_style.border_color = Color(0.59, 0.47, 0.28, 0.40)
	portrait_style.set_border_width_all(1)
	portrait_style.set_corner_radius_all(9)
	portrait_backdrop.position = Vector2(8, 8)
	portrait_backdrop.size = Vector2(102, 102)
	portrait_backdrop.add_theme_stylebox_override("panel", portrait_style)
	portrait_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait_backdrop)
	_build_avatar(Rect2(10, 10, 98, 98))
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

## 战斗组件占用固定的画布空间；战外组件沿用既有视口或原画布局。
func _fit_viewport() -> void:
	if _battle_width > 0.0:
		scale = Vector2.ONE * (_battle_width / BATTLE_FRAME_SIZE.x)
		position = Vector2(_battle_margin, _battle_margin)
		return
	if _canvas_scale > 0.0:
		scale=Vector2.ONE*_canvas_scale
		return
	var viewport_size := get_viewport().get_visible_rect().size # 包含宽屏布局的两侧留空。
	var factor := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y) # 保持组件内的统一比例。
	scale = Vector2.ONE * factor * HUD_SCALE

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
	var avatar: Texture2D = PortraitArt.DEFAULT_AVATAR # 访客也显示默认人物的头像。
	_player_name.text = Global.user_manager.curr_user_name if loaded else "未选择存档"
	_badge.visible = loaded
	if loaded:
		var state: AdventureState = Global.global_game_state.adventure_state # 当前档案已确认有效。
		var equipment := PlayerEquipmentService.new(state.equipment) # 由装备服务判断时装的有效装配状态。
		var outfits: Array[Dictionary] = equipment.rows(EquipmentDefinition.Slot.OUTFIT) # 同次刷新共用一份有效装配投影。
		avatar = PortraitArt.equipped_avatar(outfits)
		_badge.present(int(PlayerProgression.progress(state.experience).level))
	_avatar.texture = PortraitArt.framed_avatar(avatar, _avatar.size)

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
