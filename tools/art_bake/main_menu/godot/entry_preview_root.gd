extends Control
## 9A完整工程候选：复用真实工具栏/窗口，独立user目录；不替换正式启动入口。
## 纯建筑输入层，不拥有玩家状态。
const Entries = preload("res://scripts/ui/start_menu/building_entry_layer.gd")
## 已有中文字体，仅运行时引用，不打包字体。
const FONT = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 共享美术宿主、同一原画画布和交互层。
var host: Node
var canvas: Control
var entry_layer: Control
## 外部资产工作目录，仅供制作候选。
var workspace := ""
## 显式动画时间与录制模式。
var elapsed := 0.0
var recording := false
## 图像/交互的当前适配比例。
var fit_scale := 1.0
## 当前演示档案解锁记录快照。
var unlocked_quest: Dictionary = {}
## 同一功能请求记录，不伪造窗口成功。
var action_log: Array[Dictionary] = []

func _ready() -> void:
	workspace = str(ProjectSettings.get_setting("menu_entry_preview/workspace",""))
	assert(not workspace.is_empty(),"Preview workspace missing")
	assert(OS.get_user_data_dir().contains("PVZ-Menu9A-Isolated-20261112"),"Refuse nonisolated player directory")
	_prepare_profile()
	host=load(workspace.path_join("runtime/scene_host.gd")).new()
	add_child(host)
	host.configure(workspace)
	canvas=Control.new()
	canvas.name="SceneCanvas"
	canvas.size=Vector2(1672,941)
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var art:=TextureRect.new() # 真实运行的同一动态画面。
	art.texture=host.output_view.get_texture()
	art.size=canvas.size
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(art)
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(workspace.path_join("config/entries.json"))) # 命中/表现配置。
	entry_layer=Entries.new()
	canvas.add_child(entry_layer)
	entry_layer.configure(data,AdventureToolbar.feature_status,AdventureToolbar.request_feature,AdventureToolbar.scene_entries_blocked,FONT)
	entry_layer.highlight_changed.connect(host.set_entry_hover)
	entry_layer.guide_changed.connect(host.set_entry_guide)
	entry_layer.action_requested.connect(_record_action)
	# 保留已认可的档案和功能台占位，作为真实GUI阻挡，不重做最终UI。
	for filename in ["layer_profile_proposed.png","layer_console_proposed.png"]:
		var graphic:=TextureRect.new() # 静态界面本身不加入场景受光。
		graphic.texture=host.texture_file(workspace.path_join("ui/"+filename))
		graphic.size=canvas.size
		graphic.mouse_filter=Control.MOUSE_FILTER_IGNORE
		canvas.add_child(graphic)
	var profile_label:=Label.new() # 替换占位图中的“未选择存档”，明确当前为隔离演示档案。
	profile_label.text="隔离演示档案"
	profile_label.position=Vector2(35,137)
	profile_label.size=Vector2(237,29)
	profile_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	profile_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	profile_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	profile_label.add_theme_font_override("font",FONT)
	profile_label.add_theme_font_size_override("font_size",21)
	var name_style:=StyleBoxFlat.new() # 沿用已有头像框的名字底色。
	name_style.bg_color=Color("192733")
	name_style.set_corner_radius_all(5)
	profile_label.add_theme_stylebox_override("normal",name_style)
	canvas.add_child(profile_label)
	for region: Rect2 in [Rect2(0,0,306,176),Rect2(315,9,212,49),Rect2(1175,655,470,113)]:
		var blocker:=Control.new() # 占位区域不能让背景建筑接收hover或click。
		blocker.position=region.position
		blocker.size=region.size
		blocker.mouse_filter=Control.MOUSE_FILTER_STOP
		canvas.add_child(blocker)
	resized.connect(_fit)
	_fit()
	SoundManager.play_town_bgm()
	if OS.get_cmdline_user_args().has("--record-entries"):
		var recorder: Node=load("res://tools/art_bake/main_menu/godot/entry_record.gd").new() # 只在明确录制时注入鼠标。
		add_child(recorder)
		recorder.start.call_deferred(self)

## 隔离演示档案通过原服务装载；状态素材只存在临时user目录，不读正式玩家。
func _prepare_profile() -> void:
	Global.save_service.stop_autosave()
	var profile_name: String="MenuPreview_"+str(Time.get_ticks_msec()) # 每次隔离录制独立。
	assert(Global.user_manager.add_user(profile_name).is_empty())
	assert(Global.user_manager.set_current_user(profile_name))
	assert(Global.reload_session_for_current_user())
	var state: AdventureState=Global.global_game_state.adventure_state # 演示状态，不是新解锁系统。
	state.quests.records["first_expedition"]={"status":"claimed","period":"","progress":1}
	state.quests.records["first_craft"]={"status":"claimed","period":"","progress":1}
	unlocked_quest=state.quests.records["first_expedition"].duplicate(true)
	for id: int in [1,2,3]: # 让真实图鉴有可见条目；只写演示档案内存。
		state.discover_character("plant",id)
	state.discover_character("zombie",1)
	Global.quests_changed.emit()
	Global.almanac_changed.emit()

## [param locked] 切换演示研究室状态以核对锁定提示；生产条件仍由原任务服务判断。
func set_demo_research_locked(locked: bool) -> void:
	var state: AdventureState=Global.global_game_state.adventure_state # 当前隔离状态。
	if locked:
		state.quests.records["first_expedition"]={"status":"active","period":"","progress":0}
	else:
		state.quests.records["first_expedition"]=unlocked_quest.duplicate(true)
	Global.quests_changed.emit()

## [param id] 的真实请求结果只记录，不代替门面。
func _record_action(id: String, accepted: bool) -> void:
	action_log.append({"entry":id,"accepted":accepted,"time":elapsed,"modal":AdventureToolbar._modal_feature})

## 统一画布适配；命中、高亮和标签不另加分辨率补偿。
func _fit() -> void:
	fit_scale=minf(size.x/1672.0,size.y/941.0)
	canvas.scale=Vector2.ONE*fit_scale
	canvas.position=(size-Vector2(1672,941)*fit_scale)*.5

## [param point] 从原画坐标转换到真实输入坐标，用于可重复鼠标演示。
func screen_point(point: Vector2) -> Vector2:
	return canvas.position+point*fit_scale

## [param delta] 由运行循环或录制器显式提供；不读取系统时钟改变昼夜。
func advance_scene(delta: float) -> void:
	elapsed+=delta
	host.set_elapsed(elapsed)
	host.advance_entry_hover(delta)

func _process(delta: float) -> void:
	if not recording and host!=null:
		advance_scene(delta)

## 普通菜单不额外阻塞工具栏；建筑层读取工具栏真正的模态/导航状态。
func is_adventure_toolbar_blocked() -> bool:
	return false
