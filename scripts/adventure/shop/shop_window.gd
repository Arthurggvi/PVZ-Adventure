## 商店窗口编排：只管理选择、确认与演出；资产写入全部交给交易服务。
extends Control

## 统一模态宿主释放页面的通知。
signal closed
## 商品、分类及价格的唯一目录。
const Catalog = preload("res://scripts/adventure/shop/shop_catalog.gd")
## 统一购买事务。
const Service = preload("res://scripts/adventure/shop/shop_service.gd")
## 全屏表现层。
const View = preload("res://scripts/adventure/shop/shop_view.gd")
## 窗口缩放与金额格式直接依赖视觉原语，避免跨视图层解析嵌套脚本成员。
const Style = preload("res://scripts/adventure/shop/shop_skin.gd")
## 当前玩家的服务实例，不跨档复用。
var _service: Service
## 页面打开时的玩家身份。
var _opened_state: AdventureState
## 全屏等比画布。
var _view: View
## 当前商品页签。
var _category := "daily"
## 当前选中的稳定商品 ID。
var _selected := "seedling_pot"
## 购买前冻结的确认凭据；不缓存可写商品或钱包对象。
var _pending: Dictionary = {}
## 戴夫原生进场完成之前不允许交易。
var _actor_available := false
## 同步保存防重入锁。
var _busy := false
## 发疯动画结束前禁止下一笔购买。
var _celebrating := false
## 关闭期间拒绝全部资产操作。
var _closing := false
## 上次观察的本机自然日，用于午夜更新界面。
var _observed_day := ""
## 最近一次购买结果或错误文案。
var _notice := ""
## 页面入场与退出共用补间，生命周期随页面结束。
var _fade: Tween

## 按现有模态协议创建页面并绑定当前已加载档案。
func _ready() -> void:
	name = "ShopWindow"
	set_meta("covers_toolbar", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_opened_state = Global.global_game_state.adventure_state
	_service = Service.new(_opened_state, Global.adventure_inventory, Global.global_game_state,
		Global.save_service.save_now, _is_current)
	var background := ColorRect.new() # 超宽或超高窗口的画布外区域也完全覆盖主菜单。
	background.color = Color("292d21")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_view = View.new()
	add_child(_view)
	_view.action_requested.connect(_on_action)
	_view.dave.available.connect(_dave_available)
	_view.dave.celebration_finished.connect(_celebration_finished)
	Global.user_manager.signal_users_update.connect(_profile_changed)
	Global.global_game_state.coin_value_changed.connect(_coins_changed, CONNECT_DEFERRED)
	var timer := Timer.new() # 不逐帧读取系统时钟，跨午夜时刷新剩余次数。
	timer.wait_time = 1.0
	timer.timeout.connect(_check_day)
	add_child(timer)
	timer.start()
	_observed_day = AdventureQuestService.today()
	resized.connect(_fit)
	_fit()
	_render()
	_describe()
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.18)

## 按实际窗口尺寸等比居中，商品、戴夫与所有命中范围同步缩放。
func _fit() -> void:
	var factor: float = maxf(0.1, minf(size.x / Style.DESIGN.x, size.y / Style.DESIGN.y)) # 固定设计画布不裁切按钮。
	_view.scale = Vector2.ONE * factor
	_view.position = (size - Style.DESIGN * factor) * 0.5

## 交易所需的当前身份与场景条件；不允许在冒险战斗中购买扩容或装备。
func _is_current() -> bool:
	return not _closing and Global.global_game_state != null and Global.global_game_state.adventure_state == _opened_state \
		and Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and not AdventureSession.owns_battle(Global.game_para)

## 从服务查询全部展示状态，不在界面里重复计算价格或限购。
func _render() -> void:
	if not _is_current():
		return
	var offers: Array[Dictionary] = [] # 当前分类的只读商品报价。
	for id: String in Catalog.ids(_category): # 内容扩展后货架自动增加卡片。
		var offer: Dictionary = _service.quote(id) # 报价为空代表状态无效，不显示可购买按钮。
		if not offer.is_empty():
			offers.append(offer)
	_view.render({"category": _category, "selected": _selected, "offers": offers,
		"offer": _service.quote(_selected), "coins": Global.global_game_state.coin_value,
		"locked": _busy or _celebrating or not _actor_available or not _pending.is_empty(), "notice": _notice})

## 用一句短台词描述当前选择；完整规则由商品悬停展示。
func _describe() -> void:
	var offer: Dictionary = _service.quote(_selected) # 不用上一次点击时的余量或价格。
	if offer.is_empty():
		return
	_view.dave.say(str(offer.speech) if not offer.sold else ("这件你已经有啦。" if offer.get("unique", false) else "这件卖完啦。"))

## 解释 [param action] 和 [param id]；确认期间不接受商品与页签切换。
func _on_action(action: String, id: String) -> void:
	if _closing or _busy:
		return
	if action == "close":
		request_close()
		return
	if not _is_current():
		request_close()
		return
	if _celebrating or not _actor_available:
		return
	if not _pending.is_empty():
		if action == "cancel":
			_cancel_confirmation()
		elif action == "confirm":
			_confirm_purchase()
		return
	SoundManager.play_other_SFX(&"tap")
	match action:
		"category":
			if id not in Catalog.CATEGORIES or id == _category:
				return
			_category = id
			_selected = Catalog.ids(id)[0]
			_notice = ""
			_describe()
		"select":
			if id not in Catalog.ids(_category):
				return
			_selected = id
			_notice = ""
			_describe()
		"buy":
			_begin_confirmation()
	_render()

## 生成不可变确认凭据；确认单呈现价格，戴夫只询问成交。
func _begin_confirmation() -> void:
	var offer: Dictionary = _service.quote(_selected) # 点击购买时重新核对余额和库存。
	if offer.is_empty() or not offer.can_buy:
		return
	_notice = ""
	_pending = offer.token.duplicate()
	_view.dave.say("成交？")
	_view.show_confirmation(offer)

## 取消不扣款；恢复当前商品介绍与焦点。
func _cancel_confirmation() -> void:
	_pending.clear()
	_view.hide_confirmation()
	_describe()
	_render()

## 唯一资产提交点；只有持久化成功才让戴夫发疯。
func _confirm_purchase() -> void:
	if _pending.is_empty():
		return
	_busy = true
	var result: Dictionary = _service.buy(_pending.duplicate()) # 服务负责重验、发货、扣款与回滚。
	_pending.clear()
	_busy = false
	_view.hide_confirmation(false)
	if not _is_current():
		request_close()
		return
	if result.ok:
		_celebrating = true
		_notice = "已购入 · %s" % result.title
		Global.player_changed.emit()
		_view.dave.celebrate()
	else:
		_notice = str(result.message)
		_view.dave.say(_notice)
	_render()

## 原版戴夫进场完成后开放货架交互。
func _dave_available() -> void:
	_actor_available = true
	_render()

## 原生发疯动作结束后恢复购买，不按估算秒数提前打断动画。
func _celebration_finished() -> void:
	_celebrating = false
	_render()

## [param _amount] 是余额通知；延迟连接防止读取保存过程中的中间状态。
func _coins_changed(_amount: int) -> void:
	if not _busy:
		_render()

## 每秒检查换档与跨日，午夜未确认的订单作废并要求重新报价。
func _check_day() -> void:
	if _closing or _busy:
		return
	if not _is_current():
		request_close()
		return
	var today: String = AdventureQuestService.today() # 与服务相同的日期口径。
	if today == _observed_day:
		return
	_observed_day = today
	if not _pending.is_empty():
		_pending.clear()
		_view.hide_confirmation()
	_notice = "已补货"
	if not _celebrating:
		_describe()
	_render()

## 切换档案即时释放旧页面，不跨档保留确认单。
func _profile_changed() -> void:
	if not _is_current():
		request_close()

## [param event] 的 Esc 优先取消确认，再退出商店；阻止透传给主菜单。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not _pending.is_empty() and not _busy:
			_cancel_confirmation()
		else:
			request_close()

## 返回原来的菜单宿主；同步保存期间不关闭，成交演出可直接退出。
func request_close() -> void:
	if _closing or _busy:
		return
	_closing = true
	_pending.clear()
	if is_instance_valid(_fade):
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.14)
	_fade.tween_callback(_finish_close)

## 完成退出通知，模态宿主恢复工具栏和建筑交互。
func _finish_close() -> void:
	closed.emit()
	queue_free()
