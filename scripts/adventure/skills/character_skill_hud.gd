## 角色主动技能按钮：只显示状态并转发施放意图，不修改敌人、冷却或玩家档案。
extends Control
class_name CharacterSkillHud

## 头像与技能图标共用同一份战斗浮卡。
const HoverCard = preload("res://scripts/adventure/skills/character_skill_hover.gd")
## 战斗按钮的基准画布尺寸。
const BUTTON_SIZE := Vector2(84, 84)
## 待施放技能所在战斗的唯一运行时。
var _runtime: CharacterSkillRuntime
## 显示技能图标和冷却状态的施放按钮。
var _button: Button
## 战斗宿主头像上的透明入口，只镜像技能按钮状态。
var _avatar_button: Button
## 当前技能的图标。
var _icon: TextureRect
## 按剩余冷却高度显示的半透明遮罩。
var _shade: ColorRect
## 技能剩余秒数标签。
var _seconds: Label
## 当前键盘或鼠标侧键绑定的小角标。
var _keycap: Label
## 只显示技能信息，不拦截施放和战场操作。
var _hover_card: HoverCard
## 状态轮询间隔，仅刷新禁用状态与战斗阶段，不触碰敌人。
var _poll_elapsed: float = 0.0
## 本场战斗与档案框共用的皮肤，空值使用原版技能按钮。
var _valhalla: ValhallaBattleSkin
## 技能框金边材质，独立响应充能、悬停和施放反光。
var _valhalla_finish: ShaderMaterial
## 上一次冷却比例，只有真正走完冷却才播放就绪高光。
var _previous_cooldown: float = 0.0
## 随技能按钮显示而播放的入场渐显。
var _valhalla_entrance: Tween
## 同一时刻只保留一道沿框高光，重复施放也不叠亮。
var _valhalla_pulse: Tween
## 悬停与键盘聚焦共用的短渐变，避免进出按钮时闪跳。
var _valhalla_attention: Tween

## [param runtime] 是战斗场景持有的技能控制器，HUD 不单独持有技能定义。
## [param skin] 是与头像框一致的可选神殿皮肤。
func setup(runtime: CharacterSkillRuntime, skin: ValhallaBattleSkin = null) -> void:
	_runtime = runtime
	_valhalla = skin

## 在 [param avatar] 上绑定战斗专用入口；重复绑定不会叠加，空引用解除绑定。
func bind_avatar(avatar: Control) -> void:
	if is_instance_valid(_avatar_button) and _avatar_button.get_parent() == avatar:
		_sync_avatar_button()
		return
	_release_avatar_button()
	if not is_instance_valid(avatar):
		return
	_avatar_button = Button.new() # 保留原生松开触发与 canceled 输入的取消语义。
	_avatar_button.name = "AvatarSkillButton"
	_avatar_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_avatar_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_avatar_button.focus_mode = Control.FOCUS_NONE
	_avatar_button.accessibility_name = "施放角色技能"
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]: # 各态透明，头像保持原尺寸。
		_avatar_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_avatar_button.pressed.connect(_request_activation)
	avatar.add_child(_avatar_button)
	_avatar_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid(_hover_card):
		_hover_card.watch(_avatar_button)
	_sync_avatar_button()

## 外部头像不继承本 HUD 的可见性，因此显式同步现有按钮的只读表现。
func _sync_avatar_button() -> void:
	if not is_instance_valid(_avatar_button):
		return
	_avatar_button.visible = is_visible_in_tree() and is_instance_valid(_button)
	if is_instance_valid(_button):
		_avatar_button.disabled = _button.disabled
		_avatar_button.accessibility_description = _button.accessibility_description

## 先隐藏再延迟释放外部入口，重绑和场景退出期间不残留可点击控件。
func _release_avatar_button() -> void:
	if is_instance_valid(_avatar_button):
		_avatar_button.hide()
		_avatar_button.queue_free()
	_avatar_button = null

## 外部档案头像可能晚于技能 HUD 销毁，离树时主动回收入口。
func _exit_tree() -> void:
	_release_avatar_button()

## 构建一次可伸缩的战斗技能控件；未绑定技能时完全隐藏。
func _ready() -> void:
	size = ValhallaBattleSkin.SKILL_SIZE if _valhalla != null else BUTTON_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	_button = Button.new() # 鼠标与触摸复用 Godot 原生按钮事件。
	_button.name = "SkillButton"
	_button.size = size
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.accessibility_name = "角色技能"
	_button.add_theme_stylebox_override("normal", _style(Color("28372d"), Color("b59a63")))
	_button.add_theme_stylebox_override("hover", _style(Color("425138"), Color("eed39b")))
	_button.add_theme_stylebox_override("pressed", _style(Color("1a261e"), Color("eed39b")))
	_button.add_theme_stylebox_override("disabled", _style(Color("252820"), Color("665e48")))
	_button.pressed.connect(_request_activation)
	add_child(_button)
	if _valhalla != null:
		_valhalla.add_hall(_button, true)
	_icon = TextureRect.new() # 保持图标比例，透明 PNG 可直接复用时装风格。
	_icon.position = Vector2(6, 6)
	_icon.size = Vector2(72, 72)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_icon)
	_shade = ColorRect.new() # 剩余冷却从顶部向下遮罩，不生成新纹理。
	_shade.color = Color(0.055, 0.075, 0.08, 0.75)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_shade)
	if _valhalla != null:
		_valhalla_finish = _valhalla.add_frame(_button, true)
	_seconds = Label.new() # 数字和遮罩分别渲染，避免反复创建标签。
	_seconds.position = Vector2(6, 24)
	_seconds.size = Vector2(72, 36)
	_seconds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seconds.add_theme_font_size_override("font_size", 24)
	_seconds.add_theme_color_override("font_color", Color("fff0ce"))
	_seconds.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_seconds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_seconds)
	_keycap = Label.new() # 安卓/触摸平台不显示物理键帽。
	_keycap.position = Vector2(59, 60)
	_keycap.size = Vector2(20, 19)
	_keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_keycap.add_theme_font_size_override("font_size", 15)
	_keycap.add_theme_color_override("font_color", Color("f9e0a2"))
	_keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.add_child(_keycap)
	if _valhalla != null:
		_style_valhalla_button()
	_hover_card = HoverCard.new()
	_hover_card.valhalla = _valhalla != null
	add_child(_hover_card)
	_hover_card.watch(_button)
	if is_instance_valid(_avatar_button):
		_hover_card.watch(_avatar_button)
	if is_instance_valid(_runtime):
		_hover_card.can_show = _runtime.is_input_enabled
		_runtime.state_changed.connect(_refresh)
	if is_instance_valid(Global.config_service):
		Global.config_service.tool_shortcuts_changed.connect(_refresh_keycap)
	visibility_changed.connect(_sync_avatar_button)
	_refresh_keycap()
	_refresh()
	set_process(is_instance_valid(_runtime) and _runtime.definition() != null)

## 在现有按钮中调整内容层的位置，键鼠与触摸仍使用原生按钮及同一张浮卡。
func _style_valhalla_button() -> void:
	var transparent := StyleBoxEmpty.new() # 皮肤美术承接原来由木色底绘制的各态边线。
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]: # 状态仍由原来的按钮逻辑管理。
		_button.add_theme_stylebox_override(state, transparent)
	_icon.position = Vector2(16, 20)
	_icon.size = Vector2(64, 64)
	_shade.color = Color(0.025, 0.065, 0.16, 0.78)
	_seconds.position = Vector2(14, 28)
	_seconds.size = Vector2(68, 40)
	_seconds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seconds.add_theme_font_size_override("font_size", 30)
	_seconds.add_theme_color_override("font_outline_color", Color("081429"))
	_seconds.add_theme_constant_override("outline_size", 6)
	_keycap.position = Vector2(10, 70)
	_keycap.size = Vector2(37, 16)
	_keycap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_keycap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_keycap.add_theme_font_size_override("font_size", 13)
	var key_style := StyleBoxFlat.new() # 暗底从柱廊上的高光中托起物理按键字样。
	key_style.bg_color = Color("101c30ec")
	key_style.set_corner_radius_all(4)
	_keycap.add_theme_stylebox_override("normal", key_style)
	_valhalla.add_inspect_mark(_button)
	_valhalla_finish.set_shader_parameter("attention", 0.0) # 将默认值落实到材质上，补间从首次进场就能读取。
	_button.mouse_entered.connect(_update_valhalla_attention)
	_button.mouse_exited.connect(_update_valhalla_attention)
	_button.focus_entered.connect(_update_valhalla_attention)
	_button.focus_exited.connect(_update_valhalla_attention)
	visibility_changed.connect(_on_valhalla_visibility)
	if is_instance_valid(_runtime):
		_runtime.cast_committed.connect(_on_valhalla_cast)

## 显示时先亮起小窗，再由宝石沿边框送出一圈入场反光。
func _on_valhalla_visibility() -> void:
	if is_visible_in_tree():
		if _valhalla_entrance != null:
			_valhalla_entrance.kill()
		_valhalla_entrance = ValhallaBattleSkin.reveal(_button)
		_play_valhalla_pulse()
	_update_valhalla_attention()

## 聚焦和悬停使用同一条渐变；隐藏时回到未聚焦亮度。
func _update_valhalla_attention() -> void:
	var lit: bool = is_visible_in_tree() and (_button.is_hovered() or _button.has_focus()) # 触摸无悬停时也可使用焦点反馈。
	if _valhalla_attention != null:
		_valhalla_attention.kill()
	_valhalla_attention = create_tween()
	_valhalla_attention.tween_property(_valhalla_finish, "shader_parameter/attention", 1.0 if lit else 0.0, 0.18)

## [param _skill_id] 的效果已提交；同步边缘光效，无目标或被锁定的点击不会闪亮。
func _on_valhalla_cast(_skill_id: StringName) -> void:
	_play_valhalla_pulse()

## 用单次从下向上的沿框反光提示入场、施放或重新就绪。
func _play_valhalla_pulse() -> void:
	if not is_visible_in_tree():
		return
	if _valhalla_pulse != null:
		_valhalla_pulse.kill()
	_valhalla_finish.set_shader_parameter("flare", 1.0)
	_valhalla_pulse = create_tween()
	_valhalla_pulse.tween_property(_valhalla_finish, "shader_parameter/flare", 0.0, 0.70)

## 构造 [param fill] 的按钮填色和 [param border] 的木质框轮廓。
func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 每种按钮态拥有独立外观，不共享可变资源。
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(11)
	return style

## 后续绑定技能或冷却变化时只重绘既有图层。
func _refresh() -> void:
	var skill: CharacterSkillDefinition = _runtime.definition() if is_instance_valid(_runtime) else null # 技能定义变化时同步图标和浮卡。
	_hover_card.set_skill(skill)
	if skill == null:
		hide()
		set_process(false)
		return
	_icon.texture = skill.icon
	_button.accessibility_description = "%s。%s 冷却 %s 秒。" % [
		skill.display_name, skill.description, String.num(skill.cooldown_seconds, 1).trim_suffix(".0")]
	_render_cooldown()
	# 技能首次在开战后绑定，必须立即恢复控件可见性，不能依赖下一次轮询唤醒。
	var battle: MainGameManager = _runtime.get_parent() as MainGameManager
	visible = is_instance_valid(battle) and battle.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME
	set_process(true)

## 同步冷却遮罩和整数秒数；锁定时按钮仍展示剩余时间。
func _render_cooldown() -> void:
	var remaining: float = _runtime.remaining_seconds() # 只读运行时投影。
	var ratio: float = _runtime.cooldown_ratio() # 0 就绪、1 满冷却。
	_shade.position = _icon.position
	_shade.size = Vector2(_icon.size.x, _icon.size.y * ratio)
	_seconds.text = str(ceili(remaining)) if remaining > 0.0 else ""
	_button.disabled = not _runtime.is_available()
	if _valhalla_finish != null:
		_valhalla_finish.set_shader_parameter("charge", 1.0 - ratio)
		if _previous_cooldown > 0.0 and ratio <= 0.0:
			_play_valhalla_pulse()
		_previous_cooldown = ratio
	_sync_avatar_button()

## 角色技能在战斗阶段才可见；间歇刷新用于处理胜负、暂停和弹窗边界。
func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < 0.15:
		return
	_poll_elapsed = 0.0
	if not is_instance_valid(_runtime):
		hide()
		set_process(false)
		return
	var can_show: bool = _runtime.definition() != null # 运行时失效后不再访问已释放的定义。
	var battle: MainGameManager = _runtime.get_parent() as MainGameManager # 运行时只附着在主战斗场景。
	visible = can_show and is_instance_valid(battle) \
		and battle.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME
	if can_show:
		_button.disabled = not _runtime.is_available()
	_sync_avatar_button()

## 点击或触摸时由运行时重新校验所有阶段和冷却条件。
func _request_activation() -> void:
	if is_instance_valid(_runtime):
		_runtime.try_activate()

## 将界面未消耗的键盘事件 [param event] 交给技能快捷键处理。
func _unhandled_key_input(event: InputEvent) -> void:
	handle_skill_shortcut(event)

## 当可用的技能快捷键匹配 [param event] 时消费输入并尝试施放，返回是否已消费。
func handle_skill_shortcut(event: InputEvent) -> bool:
	if is_visible_in_tree() and event.is_action_pressed(ConfigService.SKILL_ACTION, false, true) \
			and not event.is_echo() and not _button.disabled:
		get_viewport().set_input_as_handled()
		_request_activation()
		return true
	return false

## 设置改键后更新键帽；桌面和移动端分别展示。
func _refresh_keycap() -> void:
	_keycap.visible = not OS.has_feature("mobile")
	if _keycap.visible:
		_keycap.text = Global.config_service.get_tool_shortcut_label(ConfigService.SKILL_ACTION)
