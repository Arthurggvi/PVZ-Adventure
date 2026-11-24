## 隔离配置目录的八秒 Shader 自测；验证设置状态持久化与反馈，不访问冒险档。
extends Control

const Settings = preload("res://scripts/ui/game_settings_window.gd")
const OUTPUT: String = "D:/Dev/PvZ/_review/star_compat_20261122/"

## 与项目真实自动加载服务一起运行，使 ConfigService 能写入独立测试用户。
func _ready() -> void:
	_check.call_deferred()

## 通过 UI 公开的真实按钮事件运行一轮设置与八秒自测。
func _check() -> void:
	var service: ConfigService = Global.config_service
	var fake: String = "__iQOO_RENDER_PROBE_TEST"
	var path: String = "user://" + fake
	DirAccess.make_dir_recursive_absolute(path)
	service.user_manager.curr_user_name = fake
	service.load_and_apply_config()
	var window: Control = Settings.new()
	add_child(window)
	await get_tree().process_frame
	var row: Control = window.get_node("Panel/General/RenderCompatibility")
	var toggle: CheckBox = row.get("_checkbox")
	var help: Button = row.get("_help")
	var test: Button = row.get("_test")
	print("CONFIG_BEFORE=", service.optional_rendering_disabled)
	toggle.button_pressed = true # 用真实的 toggled 信号写入 config.ini。
	print("CONFIG_AFTER_ON=", service.optional_rendering_disabled)
	if not service.optional_rendering_disabled:
		get_tree().quit(2)
		return
	service.load_and_apply_config() # 再读取持久化的值，不依赖内存缓存。
	print("CONFIG_RELOADED=", service.optional_rendering_disabled)
	if not service.optional_rendering_disabled:
		get_tree().quit(3)
		return
	toggle.button_pressed = false
	help.pressed.emit()
	await get_tree().process_frame
	_save_frame("settings_help.png")
	help.pressed.emit()
	test.pressed.emit()
	await get_tree().process_frame
	print("PROBE_START=", service.get_render_probe_state())
	if service.get_render_probe_state() != "running":
		get_tree().quit(4)
		return
	await get_tree().create_timer(8.4, false).timeout
	print("PROBE_END=", service.get_render_probe_state())
	if service.get_render_probe_state() != "passed":
		get_tree().quit(5)
		return
	service.load_and_apply_config()
	print("PROBE_RELOADED=", service.get_render_probe_state())
	if service.get_render_probe_state() != "passed":
		get_tree().quit(6)
		return
	print("SETTINGS_INTEGRATION_PASSED")
	get_tree().quit(0)

## 记录玩家点问号后的实际说明布局。
func _save_frame(filename: String) -> void:
	var pixels: Image = get_viewport().get_texture().get_image()
	print("CAPTURE=", filename, " result=", pixels.save_png(OUTPUT + filename))
