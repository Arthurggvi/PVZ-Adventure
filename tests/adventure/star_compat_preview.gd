## 真正进入项目自动加载环境的星章与设置截图/行为测试场景。
extends Control

const Badge = preload("res://scripts/adventure/ui/star_badge_view.gd")
const Settings = preload("res://scripts/ui/game_settings_window.gd")
const OUTPUT: String = "D:/Dev/PvZ/_review/star_compat_20261122/"

## 等 Godot 完成首帧后验证屏幕与无 Shader 材质路径。
func _ready() -> void:
	_run.call_deferred()

## 先验收设置行，再检查旧 31px 根节点及动态/兼容两种模式。
func _run() -> void:
	var window: Control = Settings.new()
	add_child(window)
	await get_tree().process_frame
	var panel: Panel = window.get_node("Panel")
	var general: Panel = panel.get_node("General")
	var row: Control = general.get_node("RenderCompatibility")
	print("SETTINGS_BOUNDS=", panel.size, " row=", row.position, " row_size=", row.size)
	if row.size.x < 400:
		get_tree().quit(2)
		return
	await get_tree().process_frame
	_capture("settings_desktop.png")
	# PC 视口内模拟 Android 只显示音频、显示和兼容选项的布局。
	panel.size = Vector2(468, 374)
	panel.get_node("Shortcuts").hide()
	for child: Node in panel.get_children():
		if child is Button and (child as Button).text == "完成":
			(child as Button).position.y = panel.size.y - 44
	window.call("_fit")
	await get_tree().process_frame
	_capture("settings_android_sim.png")
	window.queue_free()
	await get_tree().process_frame
	var preview := Control.new()
	add_child(preview)
	var index: int = 0
	for rank: int in [4, 5, 7, 8, 10]:
		var badge: Control = Badge.new()
		preview.add_child(badge)
		badge.position = Vector2(120.0 + index * 166.0, 200.0)
		badge.scale = Vector2.ONE * 3.0
		badge.configure(rank)
		print("BADGE rank=", rank, " visible=", badge.visible,
			" animated=", badge.get("_region") != null, " root=", badge.size)
		if rank >= 5 and badge.get("_region") == null:
			get_tree().quit(3)
			return
		index += 1
	await get_tree().process_frame
	_capture("baked_badges.png")
	Global.config_service.optional_rendering_disabled = true
	Global.config_service.optional_rendering_changed.emit(true)
	await get_tree().process_frame
	for child: Control in preview.get_children():
		if child.get("_region") != null:
			get_tree().quit(4)
			return
	_capture("static_badges.png")
	Global.config_service.optional_rendering_disabled = false
	Global.config_service.optional_rendering_changed.emit(false)
	print("STAR_COMPAT_SCENE_PASSED")
	get_tree().quit(0)

## 只保存测试帧，不访问真实玩家的存档路径。
func _capture(name: String) -> void:
	var frame: Image = get_viewport().get_texture().get_image()
	var result: Error = frame.save_png(OUTPUT + name)
	print("CAPTURE=", name, " result=", result)
