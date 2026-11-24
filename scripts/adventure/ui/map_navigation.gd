## 地图导航的唯一拥有者；临时选择器与加载反馈均随持久工具栏管理。
extends Node

## 打开、取消和关闭时同步工具栏输入锁。
signal navigation_state_changed

## 正式选择器由共享批次后台准备，工具栏不预载其表现依赖。
const PICKER_PATH := "res://scenes/adventure/AdventureDestinationPicker.tscn"
## 只解析权威布局和纹理路径，不创建窗口或加载纹理。
const Catalog = preload("res://scripts/adventure/destination_catalog.gd")
## 场景、模态与地图选择器共用的临时资源请求实现。
const ResourceBatch = preload("res://scripts/ui/transitions/resource_load_batch.gd")
## 地区布局解析与窗口实例化使用同一故障断点协议。
const Checkpoint = preload("res://scripts/ui/transitions/resource_load_checkpoint.gd")
## 不依赖地图素材的可取消反馈。
const LoadingView = preload("res://scripts/adventure/ui/modal_loading_view.gd")
## 僵尸岛卡片的稳定地区 ID。
const ZOMBIE_ISLAND := "zombie_island"
## 奇境大陆地区 ID 与配置卡、资源路径一致。
const WONDERLAND := "wonderland"
## 城镇卡片的稳定地区 ID，目标场景由主场景注册表提供。
const TOWN := "town"

## 已完成准备并入树的真实选择器。
var _picker: Control
## 加载及失败期间保持相同输入所有权的轻量反馈。
var _feedback: Control
## 打开请求所属的真实场景。
var _source_scene: Node
## 打开请求所属档案对象，重载同名档案也必须撤销旧请求。
var _source_state: AdventureState
## 打开时的玩家名，避免旧请求呈现在其他玩家页面。
var _source_profile := ""
## 当前请求身份，关闭后旧结果不能再发布。
var _request_id := 0
## 接受请求的帧编号，至少让轻量反馈先获得一次绘制机会。
var _request_frame := 0
## 当前请求是否已经开始解析和准备，失败后保留可关闭反馈。
var _preparation_started := false
## 仅当前请求持有的后台资源批次。
var _batch: ResourceBatch
## 已验证的布局直接交给真实窗口，避免再次读取 JSON。
var _layout: Dictionary = {}

## 加载期间也持有导航互斥锁，不允许其他窗口穿透打开。
func is_open() -> bool:
	return is_instance_valid(_picker) or is_instance_valid(_feedback)

## 接受 [param scene] 的打开请求并立即显示反馈；返回值不表示真实窗口已完成。
func open_from(scene: Node) -> bool:
	if not is_instance_valid(scene) or not scene.is_in_group(&"adventure_toolbar_surface"):
		return false
	if is_open():
		return true
	_request_id += 1
	_request_frame = Engine.get_process_frames()
	_preparation_started = false
	_source_scene = scene
	_source_state = Global.global_game_state.adventure_state if Global.global_game_state != null else null
	_source_profile = Global.user_manager.curr_user_name
	_feedback = LoadingView.new()
	_feedback.name = "MapDestinationLoading"
	_feedback.z_index = 100
	_feedback.closed.connect(close)
	add_child(_feedback)
	navigation_state_changed.emit()
	return true

## 每帧只轮询共享批次；离场或换档立即撤销结果，后台句柄由加载后端回收。
func _process(_delta: float) -> void:
	if not is_open():
		return
	if not _context_matches():
		close()
		return
	if not is_instance_valid(_feedback):
		return
	if not _preparation_started:
		if Engine.get_process_frames() <= _request_frame:
			return
		_start_preparation()
		return
	if _batch == null:
		return
	var status: int = _batch.poll() # 只有完成状态才允许在主线程读取和实例化。
	_feedback.set_resource_activity(_batch.activity())
	_feedback.set_progress(_batch.progress())
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_feedback.show_error("地图资源暂时无法加载，请关闭后重试。")
		_retire_batch()
		return
	_publish_picker(_request_id)

## 解析一次布局，并用同一份通过校验的路径清单后台准备完整首屏。
func _start_preparation() -> void:
	_preparation_started = true
	var catalog := Catalog.new() # 当前请求独享配置读取器，不保留全局缓存。
	var token: int = Checkpoint.begin(Catalog.ROOT + "layout.json", "地图布局解析")
	_layout = catalog.load_layout()
	Checkpoint.finish(token, "ok" if not _layout.is_empty() else "failed")
	if _layout.is_empty():
		_feedback.show_error(catalog.error_message)
		return
	var paths := PackedStringArray([PICKER_PATH]) # 场景静态依赖与 JSON 动态贴图同属本次请求。
	paths.append_array(catalog.resource_paths)
	_batch = ResourceBatch.new()
	if _batch.start(paths, 12_000) != OK: # 首次地图选择是轻量模态，失败应及时恢复入口。
		_feedback.show_error("地图资源暂时无法加载，请关闭后重试。")
		_retire_batch()

## [param request_id] 仍有效时才创建窗口；批次持有至同步构造结束。
func _publish_picker(request_id: int) -> void:
	if request_id != _request_id or not _context_matches():
		close()
		return
	var packed: PackedScene = _batch.get_resource(PICKER_PATH) as PackedScene # 只读取已完成资源。
	if packed == null:
		_feedback.show_error("地图窗口暂时无法打开，请关闭后重试。")
		_retire_batch()
		return
	var token: int = Checkpoint.begin(PICKER_PATH, "地图窗口实例化")
	var instance: Node = packed.instantiate() # 失败实例必须释放，不能遗留未入树节点。
	Checkpoint.finish(token, "ok" if instance is Control else "failed")
	if not instance is Control:
		if is_instance_valid(instance):
			instance.free()
		_feedback.show_error("地图窗口暂时无法打开，请关闭后重试。")
		_retire_batch()
		return
	_picker = instance as Control
	_picker.set("layout", _layout)
	_picker.set_meta("prepared_resources", _batch.resources.duplicate())
	_picker.name = "MapDestinationPicker"
	_picker.close_requested.connect(close)
	_picker.destination_selected.connect(_navigate)
	add_child(_picker)
	_picker.remove_meta("prepared_resources") # 贴图由纸图及卡片控件直接持有。
	_batch = null
	_layout = {}
	_feedback.dismiss() # 新选择器已可交互，旧卡片不再接收输入。
	_feedback = null

## 同时验证场景、档案对象与玩家名；任何身份变化都取消当前请求。
func _context_matches() -> bool:
	return is_instance_valid(_source_scene) and get_tree().current_scene == _source_scene \
		and Global.user_manager.curr_user_name == _source_profile \
		and (Global.global_game_state.adventure_state if Global.global_game_state != null else null) == _source_state

## 关闭真实窗口或准备反馈，立即恢复导航输入，线程回收不阻塞当前帧。
func close() -> void:
	var was_open := is_open() # 即便重复关闭，也只向工具栏发布一次状态变化。
	_request_id += 1
	_retire_batch()
	if is_instance_valid(_picker):
		_picker.hide()
		_picker.queue_free()
	if is_instance_valid(_feedback):
		_feedback.dismiss()
	_picker = null
	_feedback = null
	_source_scene = null
	_source_state = null
	_source_profile = ""
	_layout = {}
	if was_open:
		navigation_state_changed.emit()

## 取消立即撤销本次业务交付，线程句柄按加载后端协议有限回收。
func _retire_batch() -> void:
	if _batch != null:
		AdventureToolbar.retire_resource_batch(_batch)
		_batch = null

## 宿主退出时释放请求资格；常规切场使用同一个关闭路径。
func _exit_tree() -> void:
	close()

## 跳转至 [param destination_id] 对应的场景，选择当前地区时直接关闭地图。
func _navigate(destination_id: String) -> void:
	if not is_instance_valid(_picker) or not _picker.is_presented() or not _picker.can_select(destination_id):
		return
	if not is_instance_valid(_source_scene) or get_tree().current_scene != _source_scene:
		close()
		return
	var target_scene: String
	match destination_id:
		ZOMBIE_ISLAND:
			target_scene = AdventureSession.MAP_SCENE
		WONDERLAND:
			target_scene = "res://scenes/adventure/wonderland_map.tscn"
		TOWN:
			target_scene = Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu]
		_:
			_picker.set_navigation_pending(false)
			return
	if _source_scene.scene_file_path == target_scene:
		close()
		return
	# 档案和冒险进度由 AdventureSession 校验/保存，导航本身不接管用户状态。
	if destination_id in [ZOMBIE_ISLAND, WONDERLAND] and not AdventureSession.prepare_adventure():
		_picker.show_entry_error(AdventureSession.entry_error)
		return
	var transition: Node = _source_scene.get_node_or_null("SceneTransition")
	if transition == null:
		_picker.show_entry_error("当前场景缺少统一场景切换组件。")
		return
	var on_failed := _transition_failed.bind(_request_id) # 失败只能恢复发起切换的同一次选择器。
	transition.transition_failed.connect(on_failed, CONNECT_ONE_SHOT)
	if not transition.change_scene(target_scene):
		transition.transition_failed.disconnect(on_failed)
		_picker.show_entry_error("场景加载请求未被接受，请稍后重试。")

## [param request_id] 已被关闭或后续打开替代时忽略旧切场失败，不影响新反馈或新窗口。
func _transition_failed(request_id: int) -> void:
	if request_id == _request_id and is_instance_valid(_picker) and _context_matches():
		_picker.show_entry_error("场景资源加载失败，可以重试。")
