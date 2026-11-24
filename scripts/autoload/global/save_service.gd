## 全局游戏存档服务：持久化金币、花园、关卡进度和统一选卡引用。[br]
## 文件 IO、卡牌身份序列化与自动保存逻辑集中于此，Global 保存业务运行态。
extends Node
class_name SaveService

## 安卓文件交接只从此脚本入口延迟调用，不将安卓实现注入普通存档逻辑。
const SaveHandoff = preload("res://scripts/adventure/player/adventure_save_handoff.gd")

@onready var user_manager: UserManager = %UserManager
## 与 Global 根下的 GlobalGameState 同级，用 % 引用，避免依赖 get_parent() 类型
@onready var global_game_state: GlobalGameState = %GlobalGameState

const SaveGameVersion := "20251130"
const SaveGameFileName := "GlobalSaveGame.json"
## 主游戏关卡等存档子目录名（单点定义）。其它脚本请用 `SaveService.MAIN_GAME_SAVE_DIR_NAME` 或 `Global.save_service.MAIN_GAME_SAVE_DIR_NAME`，勿复制字符串。
const MAIN_GAME_SAVE_DIR_NAME := "main_game_saves_data"
## 普通变更合并窗口及失败后的最短重试间隔，使用单调时钟毫秒。
const DIRTY_SAVE_INTERVAL_MS := 1000

var _auto_save_timer: Timer
## 解析失败的档案不可被自动保存/战斗结算覆盖。
var _safe_to_save := true
var _loaded_profile := ""
## 序列化及文件事务的单一工作线程；交给它的参数只有已分离的快照及绝对路径。
var _save_thread := Thread.new()
## 当前内存存档版本；普通变更标脏时递增，同步事务成功也推进版本。
var _revision := 0
## 最近成功持久化的版本。失败及写盘期间新增的变更继续保持待保存。
var _saved_revision := 0
## 后台线程已接纳的快照版本。
var _writing_revision := 0
## 在途快照对应的档案路径，空表示没有待回收的写入。
var _writing_path := ""
## 允许提交下一份普通快照的最早单调时钟毫秒。
var _save_after_ms := 0

func _ready() -> void:
	user_manager.signal_user_renamed.connect(_on_user_renamed)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

## 正常退出时先收尾在途事务，再保存合并窗口中尚未提交的进度。
func _exit_tree() -> void:
	if not _flush_dirty():
		push_warning("退出时未能完成待保存的档案写入。")

## 安卓切至后台时顺手保存已加载的档案，系统回收进程前仍可保留当前进度。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and OS.has_feature("android") and is_current_profile_loaded():
		call_deferred("_complete_requested_save_handoff") # 有效档案恢复时接纳助手的单次读取请求。
	if what == NOTIFICATION_APPLICATION_PAUSED and OS.has_feature("android") and is_current_profile_loaded():
		if not save_now():
			push_warning("切至后台时保存失败，恢复后将继续自动保存。")

func _on_user_renamed(previous: String, current: String) -> void:
	if _safe_to_save and _loaded_profile == previous:
		_loaded_profile = current

func is_current_profile_loaded() -> bool:
	return _safe_to_save and user_manager != null and not user_manager.curr_user_name.is_empty() \
		and _loaded_profile == user_manager.curr_user_name

func _get_save_game_path() -> String:
	if user_manager == null or not UserManager.is_valid_user_name(user_manager.curr_user_name):
		return ""
	return "user://" + user_manager.curr_user_name + "/" + SaveGameFileName

## 供安卓分享或导出使用：只返回已成功提交的当前玩家主存档绝对路径。
func prepare_current_export_path() -> String:
	if not is_current_profile_loaded() or not save_now():
		return ""
	var path: String = _get_save_game_path() # 不直接暴露目录枚举或其他玩家文件。
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return ProjectSettings.globalize_path(path)

func _path_for_user(user_name: String) -> String:
	return "user://" + user_name + "/" + SaveGameFileName if UserManager.is_valid_user_name(user_name) else ""

## 先校验目标档，旧档损坏时绝不切换、也不自动创建替代存档。
func can_load_user(user_name: String) -> bool:
	var path: String = _path_for_user(user_name)
	if path.is_empty():
		return false
	if path == _writing_path:
		_finish_background_save() # 显式切档预检等待同一档案的在途事务。
	return read_profile_snapshot(path).get("ok", false)

## [param value] 须为可以通过 JSON 精确保存的非负整数。
static func _valid_nonnegative_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(value) \
		and value >= 0 and value <= PlantCardInstance.MAX_JSON_INTEGER and value == floor(value)

## 读取并校验 [param path] 的全局存档和冒险存档，不加载玩家、不写盘。
static func read_profile_snapshot(path: String) -> Dictionary:
	var response: Dictionary = SaveFileStore.read(path, true)
	if not response.get("ok", false):
		return {"ok": false}
	if not response.get("exists", false):
		return {"ok": true, "new": true, "adventure": AdventureState.new(), "data": {}}
	var data: Dictionary = response["data"]
	if data.has("version") and str(data["version"]) != SaveGameVersion:
		return {"ok": false}
	if not data.has("coin_value") or not _valid_nonnegative_number(data["coin_value"]):
		return {"ok": false}
	if not data.has("garden_data") or not data["garden_data"] is Dictionary:
		return {"ok": false}
	if not data.has("curr_all_level_state_data") or not data["curr_all_level_state_data"] is Dictionary:
		return {"ok": false}
	if not data.has("curr_num_new_garden_plant") or not _valid_nonnegative_number(data["curr_num_new_garden_plant"]):
		return {"ok": false}
	var adventure: AdventureState = AdventureState.new()
	if data.has("adventure"):
		adventure = AdventureState.from_dict(data["adventure"])
		if adventure == null:
			return {"ok": false}
	var uid: String = SaveProfileIdentity.resolve(data, response.source) # 旧档使用已校验的同一份原始字节确定编号。
	if uid.is_empty():
		return {"ok": false}
	adventure.equipment.profile_uid = uid
	return {"ok": true, "new": false, "data": data, "adventure": adventure}

## 以 [param interval_sec] 为自动存档周期，短于普通调度周期时也作为显式限频值。
## 无显示服务器（--headless 探针、导入或 CI 进程）不启动定时保存：
## 这类进程会加载同一份用户档，若持续把旧内存状态写回，会覆盖正式游戏刚写下的进度。
func start_autosave(interval_sec: float = 60.0) -> void:
	if _auto_save_timer != null:
		return
	if DisplayServer.get_name() == "headless":
		print("无显示环境，跳过自动保存定时器")
		return

	_auto_save_timer = Timer.new()
	_auto_save_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_auto_save_timer.ignore_time_scale = true
	_auto_save_timer.wait_time = interval_sec
	_auto_save_timer.one_shot = false
	_auto_save_timer.autostart = true
	add_child(_auto_save_timer)
	print("开始自动保存存档")
	_auto_save_timer.timeout.connect(_on_auto_save_timer_timeout)

func stop_autosave() -> void:
	if _auto_save_timer == null:
		return
	_auto_save_timer.stop()
	_auto_save_timer.queue_free()
	_auto_save_timer = null

## 常规自动存档覆盖还未单独标脏的旧玩法状态，复用同一写入调度。
func _on_auto_save_timer_timeout() -> void:
	if not is_current_profile_loaded():
		return
	print(GlobalUtils.get_curr_time(), " 自动存档")
	_schedule_save(0)

## 标记当前档案有普通变更。连续变更共用同一截止时间，不推迟首次写入。
func mark_dirty() -> void:
	if not is_current_profile_loaded():
		return
	_schedule_save(DIRTY_SAVE_INTERVAL_MS)

## 记录由当前档案发起的变更，用 [param delay_ms] 延迟首次提交，并遵守已有的限频时间。
func _schedule_save(delay_ms: int) -> void:
	if _revision == _saved_revision:
		_save_after_ms = maxi(_save_after_ms, Time.get_ticks_msec() + delay_ms)
	_revision += 1
	set_process(true)

## 按单调时钟合并、限频，不使用 [param _delta]；活动写入尚未结束时立即返回。
func _process(_delta: float) -> void:
	if _save_thread.is_alive():
		return
	_finish_background_save()
	if _revision == _saved_revision or not is_current_profile_loaded():
		set_process(false)
		return
	var now: int = Time.get_ticks_msec() # 倍速和暂停不改变普通存档的频率。
	if now < _save_after_ms:
		return
	var interval: int = DIRTY_SAVE_INTERVAL_MS # 默认上限每秒一次，仍支持调用方指定的短自动保存周期。
	if _auto_save_timer != null:
		interval = mini(interval, maxi(1, ceili(_auto_save_timer.wait_time * 1000.0)))
	_save_after_ms = now + interval
	var path: String = _get_save_game_path() # 提交时固定当前档案身份。
	var data: Dictionary = _capture_save_data() # 只在主线程读运行态并复制纯数据。
	if data.is_empty():
		return
	var writer: Callable = SaveService._persist_snapshot.bind(ProjectSettings.globalize_path(path), data) # 不绑定场景节点或运行态资源。
	if _save_thread.start(writer) != OK:
		push_warning("无法启动后台存档，保留待保存进度。")
		return
	_writing_path = path
	_writing_revision = _revision

## 收回已提交事务；帧循环只对已结束的线程调用，显式同步操作可等待其完成。
func _finish_background_save() -> void:
	if not _save_thread.is_started():
		return
	if _save_thread.wait_to_finish() == true:
		_saved_revision = _writing_revision
		print(GlobalUtils.get_curr_time(), " 存档全局数据成功, 存档路径:", _writing_path)
	else:
		push_warning("后台存档失败，将重试待保存的档案进度。")
	_writing_path = ""

## 切档或退出时提交仍属于原档案的未完成版本，失败可由调用方阻止切档。
func _flush_dirty() -> bool:
	_finish_background_save()
	return _revision == _saved_revision or _write_now(_path_for_user(_loaded_profile))

## 保存当前用户的完整全局状态，选卡按卡槽顺序编码为三字段身份字典。[br]
## 关键事务必须确认落盘才成功，先等旧版本结束，再保存此刻的运行态。
func save_now() -> bool:
	if not is_current_profile_loaded():
		push_error("未加载或无法确认玩家档案完整性，拒绝写入存档。")
		return false
	_finish_background_save()
	return _write_now(_get_save_game_path())

## 确认无在途写入后将最新快照写入 [param path]；失败保留之前的持久版本。
func _write_now(path: String) -> bool:
	var data: Dictionary = _capture_save_data() # 显式事务保存与后台任务共用数据协议。
	if data.is_empty() or not _persist_snapshot(path, data):
		return false
	_revision += 1
	_saved_revision = _revision
	set_process(false)
	print(GlobalUtils.get_curr_time(), " 存档全局数据成功, 存档路径:", path)
	return true

## 从主线程运行态生成独立的纯数据快照；返回空字典表示运行态不适合保存。
func _capture_save_data() -> Dictionary:
	if not is_instance_valid(global_game_state) or global_game_state.adventure_state == null:
		return {}
	var adventure_data: Dictionary = global_game_state.adventure_state.save_snapshot() # 装备只复制 UID、定义 ID、槽位和期限。
	if adventure_data.is_empty():
		push_error("冒险状态无法创建存档快照。")
		return {}
	if not AdventureState.is_json_value(global_game_state.garden_data) \
			or not AdventureState.is_json_value(global_game_state.curr_all_level_state_data):
		push_error("花园或关卡进度包含不可保存的数据。")
		return {}
	var snapshot: Dictionary = {
		"version": SaveGameVersion,
		"coin_value": global_game_state.coin_value,
		"garden_data": global_game_state.garden_data.duplicate(true),
		"curr_num_new_garden_plant": global_game_state.curr_num_new_garden_plant,
		"curr_all_level_state_data": global_game_state.curr_all_level_state_data.duplicate(true),
		"selected_cards": _serialize_selected_cards(),
		"curr_plant": global_game_state.curr_plant.duplicate(),
		"curr_zombie": global_game_state.curr_zombie.duplicate(),
		"adventure": adventure_data,
	} # 普通保存与后台保存都沿用登录时解析的编号。
	var uid: String = global_game_state.adventure_state.equipment.profile_uid # 尚未加载的状态不写入空编号。
	if not uid.is_empty():
		snapshot[SaveProfileIdentity.FIELD] = uid
	return snapshot

## 只校验并持久化独立快照 [param data]；[param path] 已由主线程选定。
static func _persist_snapshot(path: String, data: Dictionary) -> bool:
	if not AdventureState.validate_save_snapshot(data["adventure"]):
		push_error("冒险状态校验失败，取消本次全局保存。")
		return false
	return SaveFileStore.write(path, data)

## 读取当前用户的全局状态；选卡只恢复新格式身份，缺失或无效条目按空列表处理。[br]
## 用户未登录或运行态未就绪时跳过，其他状态沿用各自默认值。
func load_global_game_data() -> bool:
	if not _flush_dirty():
		return false
	var path: String = _get_save_game_path()
	_safe_to_save = false
	_loaded_profile = ""
	if path.is_empty() or global_game_state == null:
		return false
	var decoded: Dictionary = read_profile_snapshot(path)
	if not decoded.get("ok", false):
		push_error("玩家存档无效或无法读取，拒绝混用其他玩家数据：" + path)
		return false
	var state: GlobalGameState = global_game_state
	var data: Dictionary = decoded["data"]
	var adventure: AdventureState = decoded["adventure"] # 先校验归属和落盘，再发布给登录后的界面。
	if decoded.new:
		adventure.equipment.profile_uid = SaveProfileIdentity.create_uid()
		if not SaveProfileIdentity.is_valid(adventure.equipment.profile_uid):
			push_error("无法分配玩家存档编号。")
			return false
	var equipment := PlayerEquipmentService.new(adventure.equipment) # 预检和独立工具读取时不会触发登录对账。
	var binding_changed: bool = equipment.reconcile_bound_items() # 同时补发本档已绑定徽章并清理外来实例。
	var legacy_changed: bool = equipment.start_legacy_boost_lifetimes() # 与绑定结果共用一次存档写入。
	if binding_changed or legacy_changed:
		data[SaveProfileIdentity.FIELD] = adventure.equipment.profile_uid
		if not data.has("adventure"):
			data["adventure"] = adventure.save_snapshot()
		data.adventure.equipment = adventure.equipment.to_dict()
		if not SaveFileStore.write(path, data):
			push_error("装备归属调整未保存，暂未加载该玩家档案：" + path)
			return false
	state.adventure_state = adventure
	state.coin_value = int(data.get("coin_value", state.DEFAULT_COIN_VALUE))
	state.curr_num_new_garden_plant = int(data.get("curr_num_new_garden_plant", state.DEFAULT_CURR_NUM_NEW_GARDEN_PLANT))
	state.garden_data = data.get("garden_data", state.DEFAULT_GARDEN_DATA).duplicate(true)
	state.curr_all_level_state_data = data.get("curr_all_level_state_data", state.DEFAULT_CURR_ALL_LEVEL_STATE_DATA).duplicate(true)
	state.selected_cards = _deserialize_selected_cards(data.get("selected_cards", []))
	_loaded_profile = user_manager.curr_user_name
	_safe_to_save = true
	if OS.has_feature("android"):
		call_deferred("_complete_requested_save_handoff") # 仅当当前档案已登录时向助手发送副本。
	return true

## 处理由受信存档助手启动游戏后提出的一次性文件读取请求。
func _complete_requested_save_handoff() -> void:
	if is_current_profile_loaded():
		SaveHandoff.maybe_complete_auto_request()

## 单独保存上次选卡的新格式身份列表，保留全局存档中的其他字段。[br]
## 用户未登录或运行态未就绪时跳过，选卡 Resource 不直接写入 JSON。
func save_selected_cards() -> void:
	# 只使用统一的完整存档事务，不能读到坏 JSON 再局部覆盖其他字段。
	save_now()

## 与完整读取共享同一验证及身份解码，不允许坏档写入空出战列表。
func load_selected_cards() -> void:
	var path: String = _get_save_game_path()
	if path.is_empty() or global_game_state == null:
		return
	var decoded: Dictionary = read_profile_snapshot(path) # 重选只读已提交档案，无需等待后台临时文件。
	if decoded.get("ok", false):
		global_game_state.selected_cards = _deserialize_selected_cards(decoded["data"].get("selected_cards", []))

## 将上次选卡引用转成 JSON 可写的字典列表，保持卡槽顺序；不写入 Resource 实例。
func _serialize_selected_cards() -> Array[Dictionary]:
	# 序列化后的卡片身份，供完整存档和单独保存选卡共用。
	var serialized_cards: Array[Dictionary] = []
	# 当前引用只读使用，编码不会修改卡片模板或游戏状态。
	for card_reference: ResourceCardReference in global_game_state.selected_cards:
		if card_reference != null:
			serialized_cards.append(card_reference.to_dict())
	return serialized_cards

## 从 [param data] 读取新格式的选卡列表；无效条目和旧格式不会恢复。[br]
## 返回有序的卡片身份引用，不修改金币、花园、关卡进度或其他存档字段。
func _deserialize_selected_cards(data: Variant) -> Array[ResourceCardReference]:
	# 成功解析的新格式卡片；缺失列表时保持为空。
	var selected_card_references: Array[ResourceCardReference] = []
	if not data is Array:
		return selected_card_references
	# 只接受由卡片引用定义的字典结构，不根据旧植物或僵尸字段推导类别。
	for card_data: Variant in data:
		if not card_data is Dictionary:
			continue
		# 解码创建独立的身份引用，错误或不支持的结构由引用资源拒绝。
		var card_reference: ResourceCardReference = ResourceCardReference.from_dict(card_data)
		if card_reference != null:
			selected_card_references.append(card_reference)
	return selected_card_references

func _load_json(path: String) -> Dictionary:
	var result: Dictionary = SaveFileStore.read(path)
	return result["data"] if result.get("ok", false) and result.get("exists", false) else {}
