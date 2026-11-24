extends Node
class_name ConfigService

## 配置服务：只负责 config.ini 的读写、保存当前设置、并对外提供配置值
## 运行态逻辑请直接通过 Global.config_service/<var> 与 <signal> 获取

signal signal_change_display_plant_HP_label(value: bool)
signal signal_change_display_zombie_HP_label(value: bool)
signal signal_change_card_slot_top_mouse_focus
signal signal_fog_is_static
## 子弹无目标时追踪鼠标
signal signal_track_bullet_mouse
## 战斗快捷键已更新，设置窗口和战斗栏可刷新键帽。
signal tool_shortcuts_changed
## 可选装饰性特效的兼容开关；运行时组件按需回退为原生贴图。
signal optional_rendering_changed(disabled: bool)

@onready var user_manager: UserManager = %UserManager

const CURRENT_CONFIG_FILE := "config.ini"
## 铲子所用的 InputMap 动作。
const SHOVEL_ACTION := &"ShortcutKeys_Shovel"
## 手套所用的 InputMap 动作。
const GLOVE_ACTION := &"ShortcutKeys_Glove"
## 角色技能的 InputMap 动作；运行时注册，避免修改正在使用的 project.godot。
const SKILL_ACTION := &"ShortcutKeys_CharacterSkill"
## 角色技能默认物理按键，与铲子 W、手套 E、数字卡槽区分。
const SKILL_DEFAULT_KEY: Key = KEY_Q
## 切换战斗倍速的 InputMap 动作，在配置服务初始化时注册。
const BATTLE_SPEED_ACTION := &"ShortcutKeys_BattleSpeed"
## 二倍速默认物理按键，左右 Shift 均可触发。
const BATTLE_SPEED_DEFAULT_KEY: Key = KEY_SHIFT

## 各研究页签的工作槽选择，随玩家配置加载并保存。
var _research_selections: Dictionary = {}
## 玩家独立的兼容模式，不影响出战数值、物品、棋盘与存档。
var optional_rendering_disabled: bool = false
## 手动八秒自测的最后状态；running 表示未正常结束，并非已确认原生崩溃。
var _render_probe_state: String = "not_run"

## 用户选项（持久化字段）

var display_plant_HP_label := false:
	set(value):
		if display_plant_HP_label == value:
			return
		display_plant_HP_label = value
		signal_change_display_plant_HP_label.emit(display_plant_HP_label)

var display_zombie_HP_label := false:
	set(value):
		if display_zombie_HP_label == value:
			return
		display_zombie_HP_label = value
		signal_change_display_zombie_HP_label.emit(display_zombie_HP_label)

var card_slot_top_mouse_focus := false:
	set(value):
		if card_slot_top_mouse_focus == value:
			return
		card_slot_top_mouse_focus = value
		signal_change_card_slot_top_mouse_focus.emit()

var fog_is_static := false:
	set(value):
		if fog_is_static == value:
			return
		fog_is_static = value
		signal_fog_is_static.emit()

var plant_be_shovel_front := true
var open_all_level := false

##追踪子弹无目标时跟随标
var track_bullet_mouse := false:
	set(value):
		if track_bullet_mouse == value:
			return
		track_bullet_mouse = value
		signal_track_bullet_mouse.emit()


## 直接启动关卡时也可使用默认倍速键，已加载的玩家档案可覆盖此绑定。
func _ready() -> void:
	_apply_tool_shortcut(BATTLE_SPEED_ACTION, BATTLE_SPEED_DEFAULT_KEY)

func _get_config_path() -> String:
	if user_manager == null or user_manager.curr_user_name.is_empty():
		return ""
	return "user://" + user_manager.curr_user_name + "/" + CURRENT_CONFIG_FILE

## 加载当前玩家配置。旧配置缺少研究室选择或快捷键时使用默认值。
func load_and_apply_config() -> void:

	_research_selections = {}
	optional_rendering_disabled = false
	_render_probe_state = "not_run"
	var path := _get_config_path() # 当前玩家独立的配置路径。
	var config := ConfigFile.new() # 配置不存在时读取各项默认值。
	if path.is_empty():
		optional_rendering_changed.emit(false) # 退出用户时及时恢复默认显示策略。
		_load_tool_shortcuts(config)
		return

	# config 不存在时 load 的返回值可能非 OK，此时仍使用默认值应用（不报错可提升兼容性）
	config.load(path)
	var selections: Variant = config.get_value("research", "selections", {}) # 选择记录为可选配置项。
	if selections is Dictionary:
		_research_selections = selections

	# 音量设置
	SoundManager.set_volume(SoundManager.Bus.MASTER, config.get_value("audio", "master", 1.0))
	SoundManager.set_volume(SoundManager.Bus.BGM, config.get_value("audio", "bgm", 0.5))
	SoundManager.set_volume(SoundManager.Bus.SFX, config.get_value("audio", "sfx", 0.5))

	# 用户选项控制台
	display_plant_HP_label = config.get_value("user_control", "display_plant_HP_label", false)
	display_zombie_HP_label = config.get_value("user_control", "display_zombie_HP_label", false)
	card_slot_top_mouse_focus = config.get_value("user_control", "card_slot_top_mouse_focus", false)
	fog_is_static = config.get_value("user_control", "fog_is_static", false)
	plant_be_shovel_front = config.get_value("user_control", "plant_be_shovel_front", true)
	open_all_level = config.get_value("user_control", "open_all_level", false)
	track_bullet_mouse = config.get_value("user_control", "track_bullet_mouse", false)
	var disabled: Variant = config.get_value("graphics", "disable_optional_rendering", false)
	optional_rendering_disabled = disabled if disabled is bool else false
	var probe: Variant = config.get_value("graphics", "render_probe_state", "not_run")
	_render_probe_state = probe if probe is String and probe in ["not_run", "running", "passed", "canceled"] else "not_run"
	optional_rendering_changed.emit(optional_rendering_disabled)

	_load_tool_shortcuts(config)
	EventBus.push_event("on_config_update")

## 返回战斗动作 [param action] 的键帽文字，键盘按当前布局显示，鼠标侧键显示为 M4 或 M5。
func get_tool_shortcut_label(action: StringName) -> String:
	var code := _get_tool_shortcut(action) # InputMap 中实际生效的绑定编码。
	if is_tool_shortcut_mouse_button(code):
		return "M4" if code == MOUSE_BUTTON_XBUTTON1 else "M5"
	var physical_key := code as Key # 键盘绑定沿用物理键位。
	var label := physical_key # 无界面进程以物理键位作为显示文字。
	if DisplayServer.get_name() != "headless":
		label = DisplayServer.keyboard_get_keycode_from_physical(physical_key)
	return OS.get_keycode_string(label if label != KEY_NONE else physical_key)

## 将战斗动作 [param action] 绑定到 [param code] 指定的物理键或鼠标侧键，冲突时返回错误。
func set_tool_shortcut(action: StringName, code: int) -> Error:
	var bindings: Dictionary = _current_tool_shortcuts() # 根据实际生效的绑定检查冲突。
	if not bindings.has(action) or not _is_supported_tool_shortcut(code, action):
		return ERR_INVALID_PARAMETER
	for other: StringName in bindings: # 同一按键只允许绑定一项战斗动作。
		if other != action and bindings[other] == code:
			return ERR_ALREADY_IN_USE
	bindings[action] = code
	return _save_tool_shortcuts(bindings)

## 恢复全部战斗快捷键的默认键位，同时清除不兼容的旧绑定。
func reset_tool_shortcuts() -> Error:
	return _save_tool_shortcuts({
		SHOVEL_ACTION: _default_tool_shortcut(SHOVEL_ACTION),
		GLOVE_ACTION: _default_tool_shortcut(GLOVE_ACTION),
		SKILL_ACTION: SKILL_DEFAULT_KEY,
		BATTLE_SPEED_ACTION: BATTLE_SPEED_DEFAULT_KEY,
	})

## [param code] 是两枚可绑定的鼠标侧键之一时返回 true；其编号与支持的键盘键码不重叠。
static func is_tool_shortcut_mouse_button(code: int) -> bool:
	return code == MOUSE_BUTTON_XBUTTON1 or code == MOUSE_BUTTON_XBUTTON2

## 返回绑定编码 [param code] 是否允许用于 [param action]；只有切换倍速的动作额外接受 Shift。
func _is_supported_tool_shortcut(code: int, action: StringName = &"") -> bool:
	return is_tool_shortcut_mouse_button(code) or (code >= KEY_A and code <= KEY_Z) \
		or (code >= KEY_F1 and code <= KEY_F12) or (action == BATTLE_SPEED_ACTION and code == KEY_SHIFT)

## 返回 [param action] 当前的物理键码或鼠标侧键编号；动态动作尚未注册时返回默认值。
func _get_tool_shortcut(action: StringName) -> int:
	if InputMap.has_action(action):
		var events: Array[InputEvent] = InputMap.action_get_events(action) # 每个动作只保留一个快捷键事件。
		if not events.is_empty():
			if events[0] is InputEventKey:
				return (events[0] as InputEventKey).physical_keycode
			if events[0] is InputEventMouseButton:
				return (events[0] as InputEventMouseButton).button_index
	if action == BATTLE_SPEED_ACTION:
		return BATTLE_SPEED_DEFAULT_KEY
	return SKILL_DEFAULT_KEY if action == SKILL_ACTION else KEY_NONE

## 从项目读出原生工具默认键；技能动作无需触碰 project.godot 即可注册。
func _default_tool_shortcut(action: StringName) -> Key:
	if action == SKILL_ACTION:
		return SKILL_DEFAULT_KEY
	var binding: InputEventKey = ProjectSettings.get_setting("input/%s" % action)["events"][0]
	return binding.physical_keycode

## 返回当前战斗快捷键的绑定副本，供改键和写盘失败时恢复。
func _current_tool_shortcuts() -> Dictionary:
	return {
		SHOVEL_ACTION: _get_tool_shortcut(SHOVEL_ACTION),
		GLOVE_ACTION: _get_tool_shortcut(GLOVE_ACTION),
		SKILL_ACTION: _get_tool_shortcut(SKILL_ACTION),
		BATTLE_SPEED_ACTION: _get_tool_shortcut(BATTLE_SPEED_ACTION),
	}

## 从 [param config] 恢复战斗快捷键；旧档缺少倍速绑定或保存的键位冲突时使用 Shift。
func _load_tool_shortcuts(config: ConfigFile) -> void:
	var default_shovel: Key = _default_tool_shortcut(SHOVEL_ACTION) # 旧档使用项目原始铲子键位。
	var default_glove: Key = _default_tool_shortcut(GLOVE_ACTION) # 旧档使用项目原始手套键位。
	var saved_shovel: Variant = config.get_value("shortcuts", "shovel", default_shovel) # 配置可被玩家手工修改。
	var saved_glove: Variant = config.get_value("shortcuts", "glove", default_glove) # 缺少字段时保留旧版本默认。
	var saved_skill: Variant = config.get_value("shortcuts", "character_skill", SKILL_DEFAULT_KEY) # 新动作不要求迁移存档。
	# 铲子绑定，无效值回退到项目默认键。
	var shovel: int = saved_shovel \
		if saved_shovel is int and _is_supported_tool_shortcut(saved_shovel) else default_shovel
	# 手套绑定，无效值回退到项目默认键。
	var glove: int = saved_glove \
		if saved_glove is int and _is_supported_tool_shortcut(saved_glove) else default_glove
	# 角色技能绑定，无效值回退到默认技能键。
	var skill: int = saved_skill \
		if saved_skill is int and _is_supported_tool_shortcut(saved_skill) else SKILL_DEFAULT_KEY
	if shovel == glove:
		shovel = default_shovel
		glove = default_glove
	if skill == shovel or skill == glove:
		for candidate: Key in [KEY_Q, KEY_R, KEY_T, KEY_F1]: # 保留既有双工具改键，优先调整新增技能。
			if candidate != shovel and candidate != glove:
				skill = candidate
				break
	var saved_battle_speed: Variant = config.get_value("shortcuts", "battle_speed", BATTLE_SPEED_DEFAULT_KEY) # 旧档缺少此项时直接使用默认键。
	var battle_speed: int = BATTLE_SPEED_DEFAULT_KEY # 发生冲突时优先保留既有三项绑定。
	if saved_battle_speed is int and _is_supported_tool_shortcut(saved_battle_speed, BATTLE_SPEED_ACTION) \
			and saved_battle_speed not in [shovel, glove, skill]:
		battle_speed = saved_battle_speed
	_apply_tool_shortcut(SHOVEL_ACTION, shovel)
	_apply_tool_shortcut(GLOVE_ACTION, glove)
	_apply_tool_shortcut(SKILL_ACTION, skill)
	_apply_tool_shortcut(BATTLE_SPEED_ACTION, battle_speed)
	tool_shortcuts_changed.emit()

## 将 [param action] 替换为 [param code] 对应的单一输入事件，在 InputMap 缺少该动作时先注册。
func _apply_tool_shortcut(action: StringName, code: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var binding: InputEvent # 保存到 InputMap 的标准事件，按绑定编码选择输入设备类型。
	if is_tool_shortcut_mouse_button(code):
		var mouse := InputEventMouseButton.new() # 只绑定侧键编号，触发不依赖指针位置。
		mouse.button_index = code as MouseButton
		binding = mouse
	else:
		var key := InputEventKey.new() # 保留项目原有工具的物理键语义。
		key.physical_keycode = code as Key
		binding = key
	binding.device = -1
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, binding)

## 应用并保存 [param bindings] 中的键位；写盘失败时恢复此前的全部动作。
func _save_tool_shortcuts(bindings: Dictionary) -> Error:
	var previous: Dictionary = _current_tool_shortcuts() # 恢复需要保留技能首次注册前的默认值。
	if previous == bindings:
		return OK
	for action: StringName in bindings:
		_apply_tool_shortcut(action, bindings[action])
	var result: Error = save_config() # 统一保存事件，不向外暴露半更新状态。
	if result != OK:
		for action: StringName in previous:
			_apply_tool_shortcut(action, previous[action])
		return result
	tool_shortcuts_changed.emit()
	return OK

## 返回 [param mode] 的选择副本，未保存过该页时返回空字典。
func get_research_selection(mode: String) -> Dictionary:
	var selection: Variant = _research_selections.get(mode, {}) # 外部不能修改配置中存储的副本。
	return selection.duplicate(true) if selection is Dictionary else {}

## 保存当前玩家在 [param mode] 的 [param selection]，空字典移除该页记录。[br]
## 记录未变化时不写盘。
func remember_research_selection(mode: String, selection: Dictionary) -> void:
	if selection.is_empty():
		if _research_selections.erase(mode):
			save_config()
		return
	if _research_selections.get(mode, {}) == selection:
		return
	_research_selections[mode] = selection.duplicate(true)
	save_config()

## 即时切换可选渲染；先落盘确认，失败恢复旧选项以免界面状态分裂。
func set_optional_rendering_disabled(disabled: bool) -> Error:
	if optional_rendering_disabled == disabled:
		return OK
	var previous: bool = optional_rendering_disabled
	optional_rendering_disabled = disabled
	var status: Error = save_config()
	if status != OK:
		optional_rendering_disabled = previous
		return status
	optional_rendering_changed.emit(optional_rendering_disabled)
	return OK

## 上次自测状态可为 not_run / running / passed / canceled。
func get_render_probe_state() -> String:
	return _render_probe_state

## 自测先同步记录 running，原生崩溃后仍能看见未完成标记。
func set_render_probe_state(next_state: String) -> Error:
	if next_state not in ["not_run", "running", "passed", "canceled"]:
		return ERR_INVALID_PARAMETER
	if _get_config_path().is_empty():
		return ERR_UNCONFIGURED
	var previous: String = _render_probe_state
	_render_probe_state = next_state
	var status: Error = save_config()
	if status != OK:
		_render_probe_state = previous
	return status

## 将当前玩家的设置和已记住的研究室选择写入同一份配置，返回写盘结果。
## 无当前玩家时只应用本次运行的设置。
func save_config() -> Error:
	var path := _get_config_path() # 没有当前玩家时不写文件。
	if path.is_empty():
		return OK

	var config := ConfigFile.new() # 使用运行态的设置构建完整配置。

	# 音乐相关
	config.set_value("audio", "master", SoundManager.get_volum(SoundManager.Bus.MASTER))
	config.set_value("audio", "bgm", SoundManager.get_volum(SoundManager.Bus.BGM))
	config.set_value("audio", "sfx", SoundManager.get_volum(SoundManager.Bus.SFX))

	# 用户选项控制台相关
	config.set_value("user_control", "display_plant_HP_label", display_plant_HP_label)
	config.set_value("user_control", "display_zombie_HP_label", display_zombie_HP_label)
	config.set_value("user_control", "card_slot_top_mouse_focus", card_slot_top_mouse_focus)
	config.set_value("user_control", "fog_is_static", fog_is_static)
	config.set_value("user_control", "plant_be_shovel_front", plant_be_shovel_front)
	config.set_value("user_control", "open_all_level", open_all_level)
	config.set_value("user_control", "track_bullet_mouse", track_bullet_mouse)
	# 兼容开关属于用户配置，不与 JSON 冒险存档或硬件型号绑定。
	config.set_value("graphics", "disable_optional_rendering", optional_rendering_disabled)
	config.set_value("graphics", "render_probe_state", _render_probe_state)

	# 沿用整数字段，保存各动作的物理键码或鼠标侧键编号。
	config.set_value("shortcuts", "shovel", _get_tool_shortcut(SHOVEL_ACTION))
	config.set_value("shortcuts", "glove", _get_tool_shortcut(GLOVE_ACTION))
	config.set_value("shortcuts", "character_skill", _get_tool_shortcut(SKILL_ACTION))
	config.set_value("shortcuts", "battle_speed", _get_tool_shortcut(BATTLE_SPEED_ACTION))

	if not _research_selections.is_empty():
		config.set_value("research", "selections", _research_selections)

	return config.save(path)
