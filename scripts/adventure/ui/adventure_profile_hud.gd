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

## 创建同一套矩形头像框并绑定档案与角色变化。
func _ready() -> void:
	name = "AdventureProfileHud"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = FRAME_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# 用户索引信号在档案加载前触发，下一轮读取已经完成切换的角色状态。
	Global.user_manager.signal_users_update.connect(_refresh, Object.CONNECT_DEFERRED)
	Global.player_changed.connect(_refresh)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	_refresh()

## 随视口等比调整尺寸，默认左上角由场景根节点的锚点定位。
func _fit_viewport() -> void:
	var viewport_size := get_viewport().get_visible_rect().size # 包含宽屏布局的两侧留空。
	var factor := minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y) # 保持组件内的统一比例。
	var fitted_scale := factor * HUD_SCALE
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

## 在头像框下添加宿主的 [param caption] 按钮，点击执行 [param callback]。
func add_action(caption: String, callback: Callable) -> void:
	var button_size := Vector2(270, 62) # 与地图原有返回按钮宽度一致。
	var button := Art.action_button(self, caption, "buttons/action_neutral",
		Vector2(12, FRAME_SIZE.y + 10), button_size, callback) # 靠左避开地图第一个关卡的标题。
	button.name = "Action"
	button.add_theme_font_size_override("font_size", 32)

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
