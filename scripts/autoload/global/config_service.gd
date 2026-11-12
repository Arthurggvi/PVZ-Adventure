extends Node
class_name ConfigService

## 配置服务：只负责 config.ini 的读写、保存当前设置、并对外提供配置值
## 运行态逻辑请直接通过 Global.config_service/<var> 与 <signal> 获取

signal signal_change_disappear_spare_card_placeholder
signal signal_change_display_plant_HP_label(value: bool)
signal signal_change_display_zombie_HP_label(value: bool)
signal signal_change_card_slot_top_mouse_focus
signal signal_fog_is_static
## 子弹无目标时追踪鼠标
signal signal_track_bullet_mouse

@onready var user_manager: UserManager = %UserManager

const CURRENT_CONFIG_FILE := "config.ini"

## 各研究页签的工作槽选择，随玩家配置加载并保存。
var _research_selections: Dictionary = {}

## 用户选项（持久化字段）

var disappear_spare_card_Placeholder := false:
	set(value):
		if disappear_spare_card_Placeholder == value:
			return
		disappear_spare_card_Placeholder = value
		signal_change_disappear_spare_card_placeholder.emit()

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


func _get_config_path() -> String:
	if user_manager == null or user_manager.curr_user_name.is_empty():
		return ""
	return "user://" + user_manager.curr_user_name + "/" + CURRENT_CONFIG_FILE

## 加载当前玩家配置。没有研究室选择记录的旧配置沿用首次进入的默认选择。
func load_and_apply_config() -> void:

	_research_selections = {}
	var path := _get_config_path() # 当前玩家独立的配置路径。
	if path.is_empty():
		return

	var config := ConfigFile.new() # 配置不存在时读取各项默认值。
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
	disappear_spare_card_Placeholder = config.get_value("user_control", "disappear_spare_card_Placeholder", false)
	display_plant_HP_label = config.get_value("user_control", "display_plant_HP_label", false)
	display_zombie_HP_label = config.get_value("user_control", "display_zombie_HP_label", false)
	card_slot_top_mouse_focus = config.get_value("user_control", "card_slot_top_mouse_focus", false)
	fog_is_static = config.get_value("user_control", "fog_is_static", false)
	plant_be_shovel_front = config.get_value("user_control", "plant_be_shovel_front", true)
	open_all_level = config.get_value("user_control", "open_all_level", false)
	track_bullet_mouse = config.get_value("user_control", "track_bullet_mouse", false)

	EventBus.push_event("on_config_update")

## 返回 [param mode] 的选择副本，未保存过该页时返回空字典。
func get_research_selection(mode: String) -> Dictionary:
	var selection: Variant = _research_selections.get(mode, {}) # 外部不能修改配置中存储的副本。
	return selection.duplicate(true) if selection is Dictionary else {}

## 保存当前玩家在 [param mode] 的 [param selection]，相同选择不重复写盘。
func remember_research_selection(mode: String, selection: Dictionary) -> void:
	if _research_selections.get(mode, {}) == selection:
		return
	_research_selections[mode] = selection.duplicate(true)
	save_config()

## 将当前玩家的设置和已记住的研究室选择写入同一份配置。
func save_config() -> void:
	var path := _get_config_path() # 没有当前玩家时不写文件。
	if path.is_empty():
		return

	var config := ConfigFile.new() # 使用运行态的设置构建完整配置。

	# 音乐相关
	config.set_value("audio", "master", SoundManager.get_volum(SoundManager.Bus.MASTER))
	config.set_value("audio", "bgm", SoundManager.get_volum(SoundManager.Bus.BGM))
	config.set_value("audio", "sfx", SoundManager.get_volum(SoundManager.Bus.SFX))

	# 用户选项控制台相关
	config.set_value("user_control", "disappear_spare_card_Placeholder", disappear_spare_card_Placeholder)
	config.set_value("user_control", "display_plant_HP_label", display_plant_HP_label)
	config.set_value("user_control", "display_zombie_HP_label", display_zombie_HP_label)
	config.set_value("user_control", "card_slot_top_mouse_focus", card_slot_top_mouse_focus)
	config.set_value("user_control", "fog_is_static", fog_is_static)
	config.set_value("user_control", "plant_be_shovel_front", plant_be_shovel_front)
	config.set_value("user_control", "open_all_level", open_all_level)
	config.set_value("user_control", "track_bullet_mouse", track_bullet_mouse)

	if not _research_selections.is_empty():
		config.set_value("research", "selections", _research_selections)

	config.save(path)
