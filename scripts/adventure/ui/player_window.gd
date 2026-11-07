## 角色窗口控制器：连接档案服务与纯表现面板，拒绝跨档和关闭中的异步请求。
extends Control
class_name PlayerWindow

## 关闭完成后通知工具栏释放模态引用。
signal closed
## 复用背包的素材确认弹窗。
const InventoryDialog = preload("res://scripts/adventure/ui/inventory_dialog.gd")
## 打开时绑定的档案身份。
var _opened_state: AdventureState
## 子面板只接收展示投影。
var _panel: PlayerPanelView
## 关闭动画期间不再提交命令。
var _closing: bool = false
## 当前确认或提示弹窗，ESC 优先由它处理。
var _dialog: InventoryDialog
## 面板打开时检查装备到期，只有状态变化才重新构建网格。
var _expiry_timer: Timer
## 当前投影里最近的有效到期秒，0 表示没有待到期的装备。
var _next_expiry: int = 0

## 构建遮罩并绑定已加载档案，打开窗口不发放或修改资产。
func _ready() -> void:
	_opened_state = Global.global_game_state.adventure_state
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new() # 阻止点击穿透地图。
	shade.color = Color(0.035, 0.045, 0.025, 0.72)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PlayerPanelView.new()
	add_child(_panel)
	_panel.close_requested.connect(request_close)
	_panel.toggle_requested.connect(_toggle_equipment)
	_expiry_timer = Timer.new()
	_expiry_timer.wait_time = 1.0
	_expiry_timer.ignore_time_scale = true
	_expiry_timer.timeout.connect(_check_expiry)
	add_child(_expiry_timer)
	Global.player_changed.connect(_refresh)
	Global.user_manager.signal_users_update.connect(_refresh)
	resized.connect(_fit)
	_fit()
	_refresh()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

## 留出底部工具栏空间，等比缩放到当前视口。
func _fit() -> void:
	var factor: float = maxf(0.1, minf((size.x - 36.0) / PlayerPanelView.DESIGN.x, (size.y - 94.0) / PlayerPanelView.DESIGN.y)) # 所有子区共享一个缩放坐标。
	_panel.scale = Vector2.ONE * factor
	_panel.position = Vector2((size.x - PlayerPanelView.DESIGN.x * factor) * 0.5,
		(size.y - 70.0 - PlayerPanelView.DESIGN.y * factor) * 0.5)

## 验证档案后投影成长、装备与效果；切档窗口自动失效。
func _refresh() -> void:
	if _closing:
		return
	if Global.global_game_state.adventure_state != _opened_state or not Global.save_service.is_current_profile_loaded():
		request_close()
		return
	var service := PlayerEquipmentService.new(_opened_state.equipment) # 事务回滚后也读取当前域。
	var rows: Array[Dictionary] = service.rows() # 面板和到期检查共用一份装备投影。
	_next_expiry = 0
	for row: Dictionary in rows: # 过期条目仍可选中丢弃，但不再需要刷新。
		var deadline: int = row.expires_at # 永久实例没有到期秒。
		if not row.expired and deadline > 0 and (_next_expiry == 0 or deadline < _next_expiry):
			_next_expiry = deadline
	if _next_expiry > 0:
		_expiry_timer.start()
	else:
		_expiry_timer.stop()
	_panel.present(Global.user_manager.curr_user_name, PlayerProgression.progress(_opened_state.experience),
		rows, PlayerEffects.resolve(_opened_state.equipment))

## 窗口打开期间跨过到期点时刷新，已装备栏和操作按钮一起更新。
func _check_expiry() -> void:
	if _next_expiry > 0 and int(Time.get_unix_time_from_system()) >= _next_expiry:
		_refresh()
	else:
		_panel.refresh_remaining_time()

## 按 [param uid] 的实时期限和槽位决定操作，过期实例需要确认丢弃。
func _toggle_equipment(uid: String) -> void:
	if _closing or is_instance_valid(_dialog) or Global.global_game_state.adventure_state != _opened_state:
		return
	if _opened_state.equipment.is_expired(uid, int(Time.get_unix_time_from_system())):
		var item: EquipmentDefinition = EquipmentCatalog.definition(_opened_state.equipment.owned.get(uid, "")) # 确认时指明被丢弃的实例。
		if item == null:
			return
		var dialog := InventoryDialog.new() # 沿用普通背包的单件丢弃确认。
		dialog.setup_confirmation("丢弃装备", "确定丢弃已过期的「%s」吗？" % item.display_name, "丢弃", "取消")
		dialog.confirmed.connect(_discard_expired.bind(uid))
		_open_dialog(dialog)
		return
	var action: PlayerTransaction.Action = PlayerTransaction.Action.UNEQUIP \
		if _opened_state.equipment.equipped.values().has(uid) else PlayerTransaction.Action.EQUIP # 事务层仍会重验引用。
	_commit(action, uid)

## 确认后提交指定 [param uid]；[param _quantity] 来自共用弹窗，固定为一件。
func _discard_expired(_quantity: int, uid: String) -> void:
	_commit(PlayerTransaction.Action.DISCARD_EXPIRED, uid)

## 提交 [param action] 对 [param uid] 的变更；延迟确认仍须校验窗口是否有效。
func _commit(action: PlayerTransaction.Action, uid: String) -> void:
	if _closing:
		return
	var issue: String = PlayerTransaction.commit(_opened_state, action, uid) # 保存成功信号负责刷新。
	if issue.is_empty():
		SoundManager.play_other_SFX(&"tap")
		return
	var dialog := InventoryDialog.new() # 保存错误使用与确认一致的界面。
	dialog.setup("角色装备", issue)
	_open_dialog(dialog)

## 打开已配置的 [param dialog]，其关闭信号先于确认回调清理引用。
func _open_dialog(dialog: InventoryDialog) -> void:
	_dialog = dialog
	dialog.closed.connect(func(): _dialog = null)
	add_child(dialog)

## ESC 关闭角色；错误弹窗存在时先让其接收输入。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not is_instance_valid(_dialog):
		request_close()
		get_viewport().set_input_as_handled()

## 只关闭表现；重复点击不会重复发出 closed。
func request_close() -> void:
	if _closing:
		return
	_closing = true
	_expiry_timer.stop()
	var fade: Tween = create_tween() # 窗口离树时自动取消。
	fade.tween_property(self, "modulate:a", 0.0, 0.14)
	fade.tween_callback(func():
		closed.emit()
		queue_free())
