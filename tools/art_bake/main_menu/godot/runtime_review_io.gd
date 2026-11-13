extends Node
## 仅隔离录制使用的原生输入和截图辅助，不参与正式菜单逻辑。
## 捕获目录、帧编号与当前业务证据。
var folder := ""
var frame_index := 0
var events: Array[Dictionary]=[]
## 公用鼠标驱动与录制字幕，静帧可隐藏字幕。
var driver: RefCounted
var overlay: CanvasLayer
var last_image: Image

## [param directory] 为隔离工作目录；只向其frames/renders/reports写交付。
func configure(directory: String) -> void:
	folder=directory
	Engine.max_fps=24
	driver=load("res://tools/art_bake/main_menu/godot/entry_input_driver.gd").new()
	driver.configure(get_viewport())
	overlay=load("res://tools/art_bake/main_menu/godot/entry_record_overlay.gd").new()
	add_child(overlay)
	overlay.configure(load("res://assets/fonts/方正少儿_GBK.ttf"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("frames/walkthrough"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("frames/day_cycle"))
	for filename: String in DirAccess.get_files_at(folder.path_join("frames/walkthrough")): # 只清本工具拥有的帧，不递归删工作目录。
		if filename.begins_with("frame_") and filename.ends_with(".png"):
			DirAccess.remove_absolute(folder.path_join("frames/walkthrough/"+filename))

## [param frames] 次真实绘制，字幕只标注操作；不伪造窗口或鼠标命中。
func hold(frames: int, caption: String="") -> void:
	if not caption.is_empty():
		overlay.caption.text=caption+"\n隔离演示档案 · 正式菜单组件"
	for index: int in frames:
		await get_tree().process_frame
		driver.refresh_pointer()
		await RenderingServer.frame_post_draw
		last_image=get_viewport().get_texture().get_image()
		var encoded := last_image.duplicate() as Image # 视频统一尺寸，原生截图不修改。
		if encoded.get_size()!=Vector2i(1066,600):
			var factor := minf(1066.0/encoded.get_width(),600.0/encoded.get_height()) # 保持比例，不挤压UI。
			encoded.resize(roundi(encoded.get_width()*factor),roundi(encoded.get_height()*factor),Image.INTERPOLATE_LANCZOS)
			var framed := Image.create(1066,600,false,encoded.get_format()) # 黑边只来自不同窗口比例。
			framed.fill(Color.BLACK)
			framed.blit_rect(encoded,Rect2i(Vector2i.ZERO,encoded.get_size()),(Vector2i(1066,600)-encoded.get_size())/2)
			encoded=framed
		assert(encoded.save_png(folder.path_join("frames/walkthrough/frame_%05d.png"%frame_index))==OK)
		frame_index+=1

## [param control] 使用实际控件几何中心，发送原生按下/释放。
func click_control(control: Control) -> void:
	assert(is_instance_valid(control) and control.is_visible_in_tree())
	await click_at(control.get_global_rect().get_center())

## [param point] 为视口坐标，不调用业务回调冒充点击。
func click_at(point: Vector2) -> void:
	driver.move(point)
	overlay.show_pointer(point,false)
	await hold(2)
	driver.button(true)
	overlay.show_pointer(point,true)
	await hold(2)
	driver.button(false)
	overlay.show_pointer(point,false)
	await hold(7)

## [param point] 为菜单母图坐标，只沿当前菜单画布转换一次。
func hover(scene: Control, point: Vector2) -> void:
	var position: Vector2=scene.canvas.position+point*scene.canvas.scale # 与命中控件共用坐标。
	driver.move(position)
	overlay.show_pointer(position,false)
	await hold(12)

func escape() -> void:
	driver.keyboard_mode=true
	for pressed: bool in [true,false]: # 原生ui_cancel关闭已有模态。
		var key := InputEventKey.new()
		key.keycode=KEY_ESCAPE
		key.pressed=pressed
		get_viewport().push_input(key,true)
		await hold(4)

## [param name] 保存干净截图及同帧状态；字幕不会进入静帧。
func snapshot(name: String) -> void:
	overlay.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	last_image=get_viewport().get_texture().get_image()
	assert(last_image.save_png(folder.path_join("renders/"+name+".png"))==OK)
	var scene: Node=get_tree().current_scene # 真实当前场景，不用旧引用冒充返回。
	var row := {"name":name,"frame":frame_index,"scene":scene.scene_file_path,"profile":Global.user_manager.curr_user_name,"profile_loaded":Global.save_service.is_current_profile_loaded(),"modal":AdventureToolbar._modal_feature,"research":AdventureToolbar.feature_status("research"),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
	if scene.has_method("set_preview_hour"):
		row["hour"]=scene.clock.current_hour
		row["dialogs"]="exit" if scene.dialogs.panel.visible else ""
		row["selector_visible"]=scene.dialogs.selector.visible
		row["displayed_name"]=scene.profile_hud.get_node("PlayerName").text
		row["hovered"]=scene.entry_layer.hovered_id
	events.append(row)
	print("MENU9B_SNAPSHOT "+JSON.stringify(row))
	overlay.show()

## 写出当前实际结果；[param extra] 只补性能/资源释放等本轮观测。
func write_report(extra: Dictionary) -> void:
	var result := {"frames":frame_index,"fps":24,"events":events,"user_data_dir":OS.get_user_data_dir(),"real_ui_input":true,"test_suites_run":false,"extra":extra}
	var output := FileAccess.open(folder.path_join("reports/runtime_walkthrough.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"  "))
	output.close()

func dispose() -> void:
	driver.dispose()
	driver=null
	last_image=null
