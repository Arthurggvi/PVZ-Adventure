extends Control
## 正式海滨主菜单：真实档案/功能入口＋本机日周期，制作工具不参与玩家运行。
## 唯一运行数据包；只读res资源，不引用ArtControl绝对路径。
const PACK := "res://assets/adventure/main_menu/coastal"
## 场景合成、日周期、原有交互与真实HUD组件。
const Host=preload("res://scripts/ui/start_menu/coastal/scene_host.gd")
const Clock=preload("res://scripts/ui/start_menu/coastal/menu_clock.gd")
const Entries=preload("res://scripts/ui/start_menu/building_entry_layer.gd")
const Profile=preload("res://scripts/adventure/ui/adventure_profile_hud.gd")
const Dialogs=preload("res://scripts/ui/start_menu/coastal/menu_dialogs.gd")
const FONT=preload("res://assets/fonts/方正少儿_GBK.ttf")
## 只作为交付核对钩子，实际功能通过同一门面。
signal feature_requested(entry_id: String, accepted: bool)
## 可复用合成/时钟实例；随菜单退出一起释放。
var host: Node
var clock := Clock.new()
## 同一原画坐标画布，命中和标签随其统一缩放。
var canvas: Control
var entry_layer: Control
var profile_hud: Control
var dialogs: CanvasLayer
## 单调动作计时；不读取系统日期决定风和船的位置。
var elapsed := 0.0
var _last_ticks := 0
## 只有录制时显式冻结动作，由工具手动指定，不修改游戏时间。
var motion_paused := false
## 原生关闭策略恢复值与场景准备状态。
var _old_auto_quit := true
var initialized := false

func _ready() -> void:
	AdventureSession.adventure_active=false
	Global.time_scale=1.0
	Engine.time_scale=1.0
	hide() # 首次只显示当前时段，避免先闪白天再变夜晚。
	_old_auto_quit=get_tree().auto_accept_quit
	get_tree().auto_accept_quit=false
	var cycle: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PACK+"/config/daily_cycle.json")) # 只决定显示状态。
	clock.configure(cycle)
	host=Host.new()
	add_child(host)
	host.configure(PACK,false)
	_apply_time()
	canvas=Control.new()
	canvas.name="SceneCanvas"
	canvas.size=Vector2(1672,941)
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var art := TextureRect.new() # 唯一动态场景显示，不保存另一份日/夜图片。
	art.texture=host.output_view.get_texture()
	art.size=canvas.size
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art)
	dialogs=Dialogs.new()
	add_child(dialogs)
	dialogs.exit_confirmed.connect(_confirm_exit)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PACK+"/config/entries.json")) # 已通过的建筑命中与表现。
	entry_layer=Entries.new()
	canvas.add_child(entry_layer)
	entry_layer.configure(data,AdventureToolbar.feature_status,AdventureToolbar.request_feature,_entries_blocked,FONT)
	entry_layer.highlight_changed.connect(host.set_entry_hover)
	entry_layer.guide_changed.connect(host.set_entry_guide)
	entry_layer.action_requested.connect(func(id: String, accepted: bool):feature_requested.emit(id,accepted))
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PACK+"/config/ui_layout.json")) # 已确认布局，不把UI烘焙进背景。
	profile_hud=Profile.new()
	profile_hud.theme=preload("res://scripts/adventure/island_ui.gd").make_theme()
	profile_hud.configure_coastal_presentation()
	profile_hud.configure_canvas_layout(float(layout.profile_scale),Vector2(layout.profile_action[0],layout.profile_action[1]))
	canvas.add_child(profile_hud)
	profile_hud.position=Vector2(layout.profile_position[0],layout.profile_position[1])
	profile_hud.add_action("存档",_open_profiles)
	profile_hud.mouse_filter=Control.MOUSE_FILTER_STOP
	var transition := preload("res://scenes/ui/transitions/SceneTransition.tscn").instantiate() # 地图导航共享原过渡服务。
	transition.name="SceneTransition"
	add_child(transition)
	resized.connect(_fit)
	_fit()
	SoundManager.play_town_bgm()
	SoundManager.setup_ui_start_menu_sound(self)
	_last_ticks=Time.get_ticks_usec()
	initialized=true
	for frame in range(3): # 等待四级离屏合成获得第一帧；不会暴露默认白天。
		await get_tree().process_frame
	if is_inside_tree():
		show()

## The transition curtain may reveal only after the first composited menu frames.
func is_visual_ready() -> bool:
	return initialized and visible

func _fit() -> void:
	if canvas==null:
		return
	var factor := minf(size.x/1672.0,size.y/941.0) # 所有图像和命中使用同一仿射变换。
	canvas.scale=Vector2.ONE*factor
	canvas.position=(size-Vector2(1672,941)*factor)*.5

func _process(_delta: float) -> void:
	if not initialized:
		return
	var now := Time.get_ticks_usec() # 单调时钟，不随系统日期跳变。
	var step := clampf(float(now-_last_ticks)/1000000.0,0.0,.10) # 恢复窗口时不跳过长时间动作。
	_last_ticks=now
	if not motion_paused:
		elapsed+=step
		host.set_elapsed(elapsed)
	clock.advance(step)
	_apply_time()
	host.advance_entry_hover(step)

func _apply_time() -> void:
	host.apply_uniforms(clock.values,float(clock.values.get("water_time_gain",1.0)))

## [param hour] 为制作/验收显示覆盖；不修改系统时钟、存档或动作计时。
func set_preview_hour(hour: float) -> void:
	clock.set_manual_hour(hour)
	_apply_time()

## 返回实际当地时间模式，可由制作工具恢复；正式默认即此模式。
func use_local_time() -> void:
	clock.use_local()

func is_adventure_toolbar_blocked() -> bool:
	return dialogs!=null and dialogs.is_open()

func _entries_blocked() -> bool:
	return is_adventure_toolbar_blocked() or AdventureToolbar.scene_entries_blocked()

func _open_profiles() -> void:
	if not _entries_blocked():
		dialogs.open_profiles()

func _confirm_exit() -> void:
	if not Global.user_manager.curr_user_name.is_empty():
		if not Global.save_service.is_current_profile_loaded() or not Global.save_service.save_now():
			dialogs.show_save_error()
			return
	var tree := get_tree() # ??????????????
	tree.create_timer(.08,true,false,true).timeout.connect(tree.quit.bind(0))
	queue_free()

func _notification(what: int) -> void:
	if not initialized:
		return
	if what==NOTIFICATION_APPLICATION_FOCUS_IN:
		clock.resync(false)
		_last_ticks=Time.get_ticks_usec()
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not _entries_blocked():
			dialogs.open_exit_confirmation(not Global.user_manager.curr_user_name.is_empty())

func _exit_tree() -> void:
	get_tree().auto_accept_quit=_old_auto_quit

## 调参工具的显式入口；不重新加载档案、重建场景或改变动作计时。
func reload_visual_effects() -> Dictionary:
	return host.reload_effects() if initialized else {"ok":false,"error":"菜单尚未完成初始化"}
