extends RefCounted
## 真实窗口比例复核；截图与坐标均来自同一画布，不加入录像主帧序列。

## [param scene] 为隔离候选；[param overlay] 标注当前尺寸，不接收输入。
func capture(scene: Control, overlay: CanvasLayer) -> Array[Dictionary]:
	var results: Array[Dictionary]=[] # 记录各尺寸的实际hover和图像大小。
	var window: Window=scene.get_window() # 当前独立预览窗口。
	var original: Vector2i=window.size # 结束后恢复原尺寸。
	for size: Vector2i in [Vector2i(1280,800),Vector2i(900,700)]:
		window.size=size
		for index: int in 5: # 等待原生布局与画布等比适配完成。
			await scene.get_tree().process_frame
		var point: Vector2=scene.screen_point(Vector2(660,170)) # 同一建筑原画坐标。
		scene.get_viewport().warp_mouse(point) # 使用视口坐标，自动包含窗口缩放和留边变换。
		var motion:=InputEventMouseMotion.new() # 实际GUI拾取，不手工指定建筑。
		motion.position=point
		motion.global_position=point
		scene.get_viewport().push_input(motion,true)
		overlay.show_pointer(point)
		overlay.caption.text="布局复核 · %d × %d\n同一命中轮廓与画布变换"%[size.x,size.y]
		for index: int in 10:
			scene.entry_layer.refresh_target()
			scene.advance_scene(1.0/24.0)
			await scene.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image=scene.get_viewport().get_texture().get_image() # 真正当前窗口绘制。
		var name: String="layout_%dx%d.png"%[size.x,size.y] # 原始比例截图，不拉伸。
		assert(image.save_png(scene.workspace.path_join("entry_renders/"+name))==OK)
		results.append({"window":[size.x,size.y],"image":[image.get_width(),image.get_height()],"hovered":scene.entry_layer.hovered_id,"fit":scene.fit_scale,"screen_point":[point.x,point.y]})
		assert(scene.entry_layer.hovered_id=="library","Scaled GUI hit mismatch")
	window.size=original
	return results
