extends Node
## 用真实GUI输入驱动候选菜单并截图；演示档案隔离，不直接调用建筑打开回调。
## 录制宿主、工作目录及可见鼠标标记。
var scene: Control
var folder := ""
var overlay: CanvasLayer
## 原生视口中的鼠标坐标和按钮状态。
var pointer := Vector2(540,370)
var down := false
## 帧号、实际事件记录与最新GPU帧。
var frame_index := 0
var events: Array[Dictionary] = []
var last_frame: Image
## 不同比例的真实GUI核对结果，独立于录像帧序列。
var layout_results: Array[Dictionary]=[]
## 统一原生输入回放源，不替代GUI命中。
var input_driver: RefCounted
## 捕获帧率只控制录像，不修改游戏时段。
const FPS := 24.0
## [param root] 为本轮候选根；每个截图均来自实际视口。
func start(root: Control) -> void:
	scene=root; scene.recording=true
	folder=scene.workspace
	Engine.max_fps=24
	DirAccess.make_dir_recursive_absolute(folder.path_join("entry_frames"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("entry_renders"))
	for name: String in DirAccess.get_files_at(folder.path_join("entry_frames")):
		if name.begins_with("frame_") and name.ends_with(".png"):
			DirAccess.remove_absolute(folder.path_join("entry_frames/"+name))
	overlay=load("res://tools/art_bake/main_menu/godot/entry_record_overlay.gd").new()
	add_child(overlay)
	overlay.configure(scene.FONT)
	input_driver=load("res://tools/art_bake/main_menu/godot/entry_input_driver.gd").new()
	input_driver.configure(get_viewport())
	input_driver.position=pointer
	await hold(12,"隔离演示档案 · 原生鼠标输入")
	await load("res://tools/art_bake/main_menu/godot/entry_pointer_guard.gd").new().capture(self)
	if OS.get_cmdline_user_args().has("--entry-smoke"):
		await move_to(Vector2(660,170),12)
		await hold(12,"白天 · 图书馆悬停")
		snapshot("smoke_hover")
		await click()
		await hold(6)
		await escape()
		await hold(6)
		await move_to(Vector2(980,350),6)
		await hold(6)
		snapshot("smoke_research_hover")
		await click()
		await hold(8)
		snapshot("smoke_research_open")
		assert(AdventureToolbar._modal_feature=="research")
		await escape()
		await hold(6)
		var sizing: RefCounted=load("res://tools/art_bake/main_menu/godot/entry_layout_review.gd").new() # 短预览同时覆盖缩放坐标。
		layout_results=await sizing.capture(scene,overlay)
		await finish()
		return
	await move_to(Vector2(660,170),12)
	await hold(24,"图书馆：悬停高亮，未点击不打开")
	snapshot("day_library_hover")
	await click()
	await hold(30,"点击图书馆 → 真实冒险图鉴窗口")
	snapshot("almanac_open")
	await move_to(Vector2(980,350),8)
	await hold(10,"窗口打开期间：背景研究室不响应")
	snapshot("modal_blocks_background")
	await escape()
	await hold(16,"关闭图鉴 → 返回同一动态菜单")
	await move_to(Vector2(980,350),12)
	await hold(24,"研究室：复用现有解锁条件")
	snapshot("day_research_hover")
	await click()
	await hold(36,"点击研究室 → 真实合成、强化、转职入口")
	snapshot("research_open")
	await escape()
	await hold(18,"关闭研究室 → 返回")
	await move_to(Vector2(1440,432),14)
	await hold(24,"港口与船：同一个冒险地图入口")
	snapshot("day_harbor_hover")
	await click()
	await hold(30,"点击港口 → 真实地区选择窗口")
	snapshot("map_open")
	await escape()
	await hold(18,"关闭地图 → 返回；不启动关卡")
	await move_to(Vector2(250,360),14)
	await hold(24,"家：尚未开放，不回绕旧花园")
	snapshot("home_unavailable")
	await click()
	await move_to(Vector2(252,607),12)
	await hold(24,"商店：尚未开放，不绕过功能状态")
	snapshot("shop_unavailable")
	await click()
	scene.set_demo_research_locked(true)
	await move_to(Vector2(980,350),14)
	await hold(24,"隔离档案切为未解锁状态：显示真实条件")
	snapshot("research_locked")
	await click()
	scene.set_demo_research_locked(false)
	await move_to(Vector2(450,30),12)
	await hold(18,"鼠标在档案框上：后面的建筑不高亮、不接收点击")
	snapshot("ui_blocks_background")
	await click()
	# 同目标按下释放：从研究室按下，移到空地再松开，不应打开。
	await move_to(Vector2(980,350),10)
	button(true)
	await hold(2,"按下后拖出建筑：取消打开")
	await move_to(Vector2(820,650),14)
	button(false)
	await hold(14,"释放在空地：没有窗口")
	snapshot("drag_cancelled")
	scene.host.set_time(1.0)
	await hold(12,"夜间同样的入口反馈；环境和窗灯保持原时段")
	for item: Array in [["library",660,170],["research",980,350],["harbor",1545,352],["shop",252,607]]:
		await move_to(Vector2(item[1],item[2]),12)
		await hold(26,"夜晚 · "+str(scene.entry_layer.entries[item[0]].name)+" 悬停；布料和船体同步强调")
		snapshot("night_"+item[0]+"_hover")
	# 焦点由原生Control设置，Enter仍经过_gui_input及同一业务门面。
	input_driver.keyboard_mode=true
	scene.entry_layer.controls["library"].grab_focus()
	var tab:=InputEventKey.new() # 把输入方式切为键盘，不依赖鼠标所在建筑。
	tab.keycode=KEY_SHIFT
	tab.pressed=true
	get_viewport().push_input(tab,true)
	await hold(12,"键盘焦点：同一图书馆高亮")
	snapshot("keyboard_library_focus")
	var enter:=InputEventKey.new() # 正式ui_accept按键路径。
	enter.keycode=KEY_ENTER
	enter.pressed=true
	get_viewport().push_input(enter,true)
	await hold(18,"Enter → 同一真实图鉴窗口")
	snapshot("keyboard_almanac_open")
	enter.pressed=false
	get_viewport().push_input(enter,true)
	await escape()
	await hold(12,"关闭返回，键盘与鼠标共用入口")
	var layout: RefCounted=load("res://tools/art_bake/main_menu/godot/entry_layout_review.gd").new() # 复用候选画布做真实窗口核对。
	layout_results=await layout.capture(scene,overlay)
	await finish()
## [param frames] 个真实GPU帧，字幕 [param caption] 仅标注，不伪造界面。
func hold(frames: int, caption: String="") -> void:
	if not caption.is_empty():
		overlay.caption.text=caption+"\n隔离预览 · 不修改玩家存档"
	for index: int in frames:
		await get_tree().process_frame
		input_driver.refresh_pointer() # 在系统事件与窗口变化之后重送原生鼠标状态。
		scene.entry_layer.refresh_target()
		scene.advance_scene(1.0/FPS)
		await RenderingServer.frame_post_draw
		last_frame=get_viewport().get_texture().get_image()
		assert(last_frame.save_png(folder.path_join("entry_frames/frame_%05d.png"%frame_index))==OK)
		frame_index+=1
## [param point] 为母图坐标；经同一视口转换发送原生Motion事件。
func move_to(point: Vector2, frames: int) -> void:
	var start_point: Vector2=pointer # 当前视口位置。
	var target: Vector2=scene.screen_point(point) # 画布缩放只在此转换一次。
	for index: int in frames:
		pointer=start_point.lerp(target,float(index+1)/frames)
		input_driver.move(pointer)
		overlay.show_pointer(pointer,down)
		await hold(1)
## [param pressed] 走原生GUI按键，不调用建筑回调。
func button(pressed: bool) -> void:
	down=pressed
	input_driver.button(pressed)
	overlay.show_pointer(pointer,pressed)
func click() -> void:
	button(true)
	await hold(2)
	button(false)
	await hold(4)
## 原生取消键关闭当前已有窗口。
func escape() -> void:
	input_driver.keyboard_mode=true
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new() # 使用原ui_cancel映射。
		event.keycode=KEY_ESCAPE
		event.pressed=pressed
		get_viewport().push_input(event,true)
		await hold(2)
## [param name] 保存当时实际窗口和门面状态，方便区分hover、打开和阻塞。
func snapshot(name: String) -> void:
	assert(last_frame.save_png(folder.path_join("entry_renders/"+name+".png"))==OK)
	events.append({"name":name,"frame":frame_index,"hovered":scene.entry_layer.hovered_id,"modal":AdventureToolbar._modal_feature,"navigation_open":AdventureToolbar._navigation.is_open(),"blocked":AdventureToolbar.scene_entries_blocked(),"gui_hover":str(get_viewport().gui_get_hovered_control().get_path()) if get_viewport().gui_get_hovered_control()!=null else "","research":AdventureToolbar.feature_status("research")})
	print("ENTRY_SNAPSHOT "+JSON.stringify(events[-1]))
func finish() -> void:
	var record: Dictionary={"frames":frame_index,"fps":FPS,"events":events,"actions":scene.action_log,"user_data_dir":OS.get_user_data_dir(),"real_gui_input":true,"real_windows":true,"startup_menu_replaced":false,"layout_review":layout_results,"game_test_suite_run":false} # 当前录制证据。
	var file:=FileAccess.open(folder.path_join("reports/entry_record.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"  "))
	file.close()
	print("ENTRY_RECORD_COMPLETE "+JSON.stringify({"frames":frame_index,"actions":scene.action_log}))
	var tree: SceneTree=get_tree() # 先回收候选视口与纹理再结束原生进程。
	reparent(tree.root)
	scene.queue_free()
	scene=null
	last_frame=null
	input_driver.dispose();input_driver=null
	await tree.process_frame
	await tree.process_frame
	tree.quit(0)
