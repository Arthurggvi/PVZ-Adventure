## 全局游戏存档服务：持久化金币、花园、关卡进度和统一选卡引用。[br]
## 文件 IO、卡牌身份序列化与自动保存逻辑集中于此，Global 保存业务运行态。
extends Node
class_name SaveService

@onready var user_manager: UserManager = %UserManager
## 与 Global 根下的 GlobalGameState 同级，用 % 引用，避免依赖 get_parent() 类型
@onready var global_game_state: GlobalGameState = %GlobalGameState

const SaveGameVersion := "20251130"
const SaveGameFileName := "GlobalSaveGame.json"
## 主游戏关卡等存档子目录名（单点定义）。其它脚本请用 `SaveService.MAIN_GAME_SAVE_DIR_NAME` 或 `Global.save_service.MAIN_GAME_SAVE_DIR_NAME`，勿复制字符串。
const MAIN_GAME_SAVE_DIR_NAME := "main_game_saves_data"

var _auto_save_timer: Timer
## 解析失败的档案不可被自动保存/战斗结算覆盖。
var _safe_to_save := true
var _loaded_profile := ""

func _ready() -> void:
	user_manager.signal_user_renamed.connect(_on_user_renamed)

func _on_user_renamed(previous: String, current: String) -> void:
	if _safe_to_save and _loaded_profile == previous:
		_loaded_profile = current

func is_current_profile_loaded() -> bool:
	return _safe_to_save and user_manager != null and _loaded_profile == user_manager.curr_user_name

func _get_save_game_path() -> String:
	if user_manager == null or not UserManager.is_valid_user_name(user_manager.curr_user_name):
		return ""
	return "user://" + user_manager.curr_user_name + "/" + SaveGameFileName

func _path_for_user(name: String) -> String:
	return "user://" + name + "/" + SaveGameFileName if UserManager.is_valid_user_name(name) else ""

## 先校验目标档，旧档损坏时绝不切换、也不自动创建替代存档。
func can_load_user(name: String) -> bool:
	var path: String = _path_for_user(name)
	if path.is_empty():
		return false
	return _decode_profile(path).get("ok", false)

func _valid_nonnegative_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(value) \
		and value >= 0 and value <= PlantCardInstance.MAX_JSON_INTEGER and value == floor(value)

func _decode_profile(path: String) -> Dictionary:
	var response: Dictionary = SaveFileStore.read(path)
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
	return {"ok": true, "new": false, "data": data, "adventure": adventure}

## 启用自动保存存档
func start_autosave(interval_sec: float = 60.0) -> void:
	if _auto_save_timer != null:
		return

	_auto_save_timer = Timer.new()
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

func _on_auto_save_timer_timeout() -> void:
	# 单一全局存档已包含冒险状态，不再暂停冒险会话期间的保存。
	print(GlobalUtils.get_curr_time(), " 自动存档")
	save_now()

## 保存当前用户的完整全局状态，选卡按卡槽顺序编码为三字段身份字典。[br]
## 用户未登录或运行态未就绪时跳过，写入失败时不报告保存成功。
func save_now() -> bool:
	# 当前用户的全局存档路径；空路径表示尚未登录。
	var path := _get_save_game_path()
	if path.is_empty():
		# 未选用户时常见，不算错误（用 verbose 避免自动存档定时刷屏）
		print("全局存档跳过：未登录用户或用户名为空")
		return false

	if global_game_state == null or not _safe_to_save or _loaded_profile != user_manager.curr_user_name:
		push_error("未加载或无法确认玩家档案完整性，拒绝写入存档。")
		return false

	# 冒险域必须可序列化，不能用空字典覆盖未完成或非法的内存状态。
	var adventure_data: Dictionary = global_game_state.adventure_state.to_dict()
	if adventure_data.is_empty():
		push_error("冒险状态校验失败，取消本次全局保存。")
		return false
	# 本次写入的完整状态，Resource 选卡引用转换为 JSON 可保存的身份值。
	var data: Dictionary = {
		"version": SaveGameVersion,
		"coin_value": global_game_state.coin_value,
		"garden_data": global_game_state.garden_data,
		"curr_num_new_garden_plant": global_game_state.curr_num_new_garden_plant,
		"curr_all_level_state_data": global_game_state.curr_all_level_state_data,
		"selected_cards": _serialize_selected_cards(),
		"curr_plant": global_game_state.curr_plant,
		"curr_zombie": global_game_state.curr_zombie,
		"adventure": adventure_data,
	}

	if not _save_json(data, path):
		return false
	print(GlobalUtils.get_curr_time(), " 存档全局数据成功, 存档路径:", path)
	return true

## 读取当前用户的全局状态；选卡只恢复新格式身份，缺失或无效条目按空列表处理。[br]
## 用户未登录或运行态未就绪时跳过，其他状态沿用各自默认值。
func load_global_game_data() -> bool:
	var path: String = _get_save_game_path()
	_safe_to_save = false
	_loaded_profile = ""
	if path.is_empty() or global_game_state == null:
		return false
	var decoded: Dictionary = _decode_profile(path)
	if not decoded.get("ok", false):
		push_error("玩家存档无效或无法读取，拒绝混用其他玩家数据：" + path)
		return false
	var state: GlobalGameState = global_game_state
	var data: Dictionary = decoded["data"]
	state.adventure_state = decoded["adventure"]
	state.coin_value = int(data.get("coin_value", state.DEFAULT_COIN_VALUE))
	state.curr_num_new_garden_plant = int(data.get("curr_num_new_garden_plant", state.DEFAULT_CURR_NUM_NEW_GARDEN_PLANT))
	state.garden_data = data.get("garden_data", state.DEFAULT_GARDEN_DATA).duplicate(true)
	state.curr_all_level_state_data = data.get("curr_all_level_state_data", state.DEFAULT_CURR_ALL_LEVEL_STATE_DATA).duplicate(true)
	state.selected_cards = _deserialize_selected_cards(data.get("selected_cards", []))
	_loaded_profile = user_manager.curr_user_name
	_safe_to_save = true
	return true

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
	var decoded: Dictionary = _decode_profile(path)
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

func _save_json(data: Dictionary, path: String) -> bool:
	return SaveFileStore.write(path, data)

func _load_json(path: String) -> Dictionary:
	var result: Dictionary = SaveFileStore.read(path)
	return result["data"] if result.get("ok", false) and result.get("exists", false) else {}
