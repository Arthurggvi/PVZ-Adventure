## Bootstrap-to-interactive-menu timing, independent of engine startup time.
## Run with isolated user data in both headless and graphical mode.
extends Node

## 复用回城验收的背景细节检查。
const CoastalFrameCheck = preload("res://tests/adventure/coastal_frame_check.gd")

var _started_usec := 0

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("startup-boot-test"), "Must isolate user data")
	get_tree().current_scene = null
	get_tree().create_timer(20.0, true, false, true).timeout.connect(func():
		push_error("FAIL: bootstrap never reached an interactive menu")
		get_tree().quit(1))
	_started_usec = Time.get_ticks_usec()
	if get_tree().change_scene_to_file("res://scenes/main/00Bootstrap.tscn") != OK:
		push_error("FAIL: bootstrap scene cannot be instantiated")
		get_tree().quit(1)
		return
	_watch.call_deferred()

func _watch() -> void:
	while true:
		var scene: Node = get_tree().current_scene
		if is_instance_valid(scene) and scene.scene_file_path == 				"res://scenes/main/01StartMenuCoastal.tscn":
			var transition: Node = scene.get_node_or_null("SceneTransition")
			if transition != null and scene.is_visual_ready() and not transition.busy:
				if AllCards.is_catalog_materialized():
					push_error("FAIL: main menu unexpectedly initialized card catalogue")
					get_tree().quit(1)
					return
				var ready_ms := roundi(float(Time.get_ticks_usec() - _started_usec) / 1000.0) # 揭幕耗时不含验收读回。
				var graphical := DisplayServer.get_name() != "headless" # 无渲染设备只核对冷启动流程。
				if graphical:
					await RenderingServer.frame_post_draw
					var sampler_error := CoastalFrameCheck.sampler_budget_error(scene.host) # 验证正式合成的各次绘制。
					if not sampler_error.is_empty():
						push_error("FAIL: " + sampler_error)
						get_tree().quit(1)
						return
					var town_frame: Image = scene.host.output_view.get_texture().get_image() # 仅检查最终城镇背景，避免 UI 掩盖白屏。
					var frame_error := CoastalFrameCheck.error_for(town_frame) # 揭幕后的画面失败原因。
					if not frame_error.is_empty():
						push_error("FAIL: " + frame_error)
						get_tree().quit(1)
						return
				print("PASS: bootstrap → interactive coastal menu; elapsed_ms=", ready_ms,
					"; visual_check=", "passed" if graphical else "skipped (headless)")
				get_tree().quit(0)
				return
		await get_tree().process_frame
