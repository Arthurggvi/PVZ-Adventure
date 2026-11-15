## Minimal no-save check: reusable lab panel, three modes, live pointer and close.
extends Node

const Research = preload("res://scripts/adventure/ui/research_window.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var initial_coins: int = Global.global_game_state.coin_value
	var ui: AdventureResearchWindow = Research.new()
	get_tree().root.add_child(ui)
	await get_tree().create_timer(0.32).timeout
	await _wait_for_content(ui)
	assert(ui.mode == "craft")
	assert(ui.ui.content.get_child_count() >= 4)
	assert(get_tree().root.get_node("AdventureToolbar")._hooks.has("research"))
	# Unowned recipes are intentionally absent from the real player-backed list.
	print("RESEARCH_UI initial=", ui.mode, " canvas=", ui.ui.canvas.position,
		" scaled=",ui.ui.canvas.scale)
	await _click(ui.ui.tabs["upgrade"].get_global_rect().get_center())
	assert(ui.mode == "upgrade", "Mode tab must receive mouse event")
	await _wait_for_content(ui)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://research_upgrade_in_game.png")
	await _click(ui.ui.tabs["promotion"].get_global_rect().get_center())
	assert(ui.mode == "promotion")
	await _wait_for_content(ui)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://research_promotion_in_game.png")
	await _click(ui.ui.tabs["craft"].get_global_rect().get_center())
	assert(ui.mode == "craft")
	await _wait_for_content(ui)
	assert(Global.global_game_state.coin_value == initial_coins)
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png("user://research_frontend_in_game.png")
	ui.request_close()
	await get_tree().create_timer(0.23).timeout
	assert(not is_instance_valid(ui))
	print("RESEARCH_UI_SMOKE_PASS single panel, three tabs, close, no writes")
	get_tree().quit(0)

## [param window] 的可见候选装配结束后再执行原有截图，不把请求接受当作绘制完成。
func _wait_for_content(window: AdventureResearchWindow) -> void:
	var deadline: int = Time.get_ticks_msec() + 12000 # 只作为异常上限，不用于性能断言。
	while Time.get_ticks_msec() < deadline and not window.is_content_ready():
		await get_tree().process_frame
	assert(window.is_content_ready())

func _click(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	get_viewport().push_input(press, true)
	press.pressed = false
	get_viewport().push_input(press, true)
	await get_tree().process_frame
