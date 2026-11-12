extends RefCounted
## 录制前景控件在按下后出现的真实GUI边界；不代替业务入口，也不更改玩家进度。

## [param recorder] 提供原生鼠标与实际截图；临时面板只用于明确展示遮挡状态。
func capture(recorder: Node) -> void:
	await recorder.move_to(Vector2(660,170),8)
	await recorder.hold(5,"输入边界：在图书馆按下后，前景界面覆盖鼠标")
	var actions_before: int=recorder.scene.action_log.size() # 请求数量用于判断是否穿透。
	recorder.button(true)
	await recorder.hold(2)
	var panel:=Panel.new() # 真正前景Control，非伪造的hover状态。
	panel.name="PointerCaptureGuard"
	panel.position=Vector2(595,115)
	panel.size=Vector2(260,130)
	panel.mouse_filter=Control.MOUSE_FILTER_STOP
	var style:=StyleBoxFlat.new() # 可见演示遮挡，不冒充生产业务窗口。
	style.bg_color=Color("243541")
	style.border_color=Color("d4bc80")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	recorder.scene.canvas.add_child(panel)
	var title:=Label.new() # 明确说明当前演示条件。
	title.text="前景界面\n背景入口应停止响应"
	title.position=Vector2(12,16)
	title.add_theme_font_override("font",recorder.scene.FONT)
	title.add_theme_font_size_override("font_size",22)
	title.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)
	await recorder.hold(6)
	recorder.snapshot("foreground_covers_pressed_entry")
	recorder.button(false)
	await recorder.hold(8,"松开鼠标：前景界面存在时不应打开背景图鉴")
	recorder.snapshot("covered_release_cancelled")
	var leaked: bool=recorder.scene.action_log.size()>actions_before # 只记录事实，不能伪造拒绝。
	var record: Dictionary={"accepted_background_action":leaked,"modal":AdventureToolbar._modal_feature,"gui_hover":str(recorder.get_viewport().gui_get_hovered_control().get_path()) if recorder.get_viewport().gui_get_hovered_control()!=null else ""} # 当前原生事件结果。
	var file:=FileAccess.open(recorder.folder.path_join("reports/pointer_capture_guard.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"  "))
	file.close()
	print("POINTER_CAPTURE_GUARD "+JSON.stringify(record))
	if is_instance_valid(AdventureToolbar._modal):
		await recorder.escape()
	panel.queue_free()
	await recorder.hold(4)
