## 图书馆窗口编排：持有临时选择与展示状态，资产操作全部委托图书馆服务。
extends Control

## 通知统一模态宿主释放窗口引用。
signal closed
## 独立布局与已有书本美术。
const View = preload("res://scripts/adventure/ui/library_panel_view.gd")
## 图书馆事务服务。
const Service = preload("res://scripts/adventure/library/library_service.gd")
## 共享操作反馈，避免常驻冗余说明。
const Feedback = preload("res://scripts/adventure/ui/research_feedback.gd")
## 本窗口固定皮肤的动态路径集合。
const ResourcePaths = preload("res://scripts/adventure/ui/ui_resource_paths.gd")

## 首屏准备只含固定布局；随机货架生成并保存后再按实际书目准备预览。
static func get_initial_resource_paths() -> PackedStringArray:
	var paths: PackedStringArray = ResourcePaths.frame() # 不为了预热触发每日刷新或任何存档写入。
	paths.append_array(ResourcePaths.skin(PackedStringArray(["overlays/star_filled.png",
		"res://assets/adventure/ui/bottom_bar/icons/icon_deck.png"]),
		PackedStringArray(["buttons/action_neutral", "buttons/action_confirm", "slots/item_slot"])))
	return paths
## 当前展示画布，按窗口等比适配。
var _view: View
## 当前档案的图书馆服务，不跨档复用。
var _service: Service
## 开馆时的档案身份，切换后立即关闭。
var _opened_state: AdventureState
## 当前页签，只允许 today / convert / synthesize。
var _mode := "today"
## 阶级过滤，零表示全部。
var _tier := 0
## 预留的材料 ID，重复项代表多本同书，不提前扣库存。
var _selected: Array[String] = []
## 当前页最近成功取得的技能书 ID。
var _result := ""
## 非阻塞的结果提示条。
var _feedback: Feedback
## 输入防重入与退出标志。
var _busy := false
## 退出标志防止关闭动画期间继续交易。
var _closing := false
## 入场和退出共用补间，快速关闭时停止旧补间。
var _fade: Tween
## 已观察自然日；轮询仅在跨日或首次货架失败后触发保存。
var _observed_day := ""

## 每日货架成功持久化后，等待当前五本书的实际预览准备完成。
func is_content_ready() -> bool:
	return is_instance_valid(_view) and _view.is_content_ready()

## 创建窗口并绑定现有档案；只有成功保存后的每日货架才会显示。
func _ready() -> void:
	name = "LibraryWindow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_opened_state = Global.global_game_state.adventure_state
	_service = Service.new(_opened_state, Global.adventure_inventory, Global.global_game_state, Global.save_service.save_now)
	var shade := ColorRect.new() # 全屏暗幕防止点击穿透背景建筑。
	shade.color = Color(0.025, 0.035, 0.025, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_view = View.new()
	add_child(_view)
	_view.action_requested.connect(_on_action)
	_feedback = Feedback.new()
	add_child(_feedback)
	Global.user_manager.signal_users_update.connect(_profile_changed)
	Global.global_game_state.coin_value_changed.connect(_coins_changed, CONNECT_DEFERRED)
	var timer := Timer.new() # 保持面板跨午夜时同步货架，不逐帧读系统日期。
	timer.wait_time = 1.0
	timer.timeout.connect(_check_day)
	add_child(timer)
	timer.start()
	_sync_day()
	_render()
	resized.connect(_fit)
	_fit()
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.18)

## 等比居中并为底部工具栏预留空间。
func _fit() -> void:
	var factor: float = maxf(0.1, minf((size.x - 30) / View.DESIGN.x, (size.y - 80) / View.DESIGN.y)) # 全画布保持文字与格子比例。
	_view.scale = Vector2.ONE * factor
	_view.position = Vector2((size.x - View.DESIGN.x * factor) * 0.5, (size.y - 64 - View.DESIGN.y * factor) * 0.5)

## 当前档案必须仍被真实存档服务加载，过期窗口不能提交。
func _is_current() -> bool:
	return not _closing and Global.global_game_state != null and Global.global_game_state.adventure_state == _opened_state \
		and Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.adventure_inventory != null and Global.adventure_inventory.owns_state(_opened_state) \
		and AdventureQuestService.feature_unlocked(_opened_state, "library")

## 使用正常切页入口打开 [param mode]，返回真实页签供教学定位；不提交交易。
func guide_tab(mode: String) -> Control:
	if not _is_current() or _busy:
		return null
	if mode != _mode:
		_on_action("mode", mode)
	return _view.tab_control(mode)

## 从实时库存及货架生成纯展示快照。
func _render() -> void:
	if not _is_current():
		return
	var shelf: Dictionary = _service.shelf() # 过期且未成功保存的新货架显示重试入口，不显示无法购买的旧货位。
	if str(shelf.day) < AdventureQuestService.today():
		shelf.offers = []
	_view.render({"mode": _mode, "tier": _tier, "coins": Global.global_game_state.coin_value,
		"shelf": shelf, "selected": _selected.duplicate(), "result": _result,
		"available": _service.available(_mode, _selected, _tier) if _mode != "today" else [],
		"quote": _service.quote(_mode, _selected) if _mode != "today" else {"ready": false}})

## 处理纯表现层发送的 [param action] 与 [param data]；交易前再次验证档案和实时材料。
func _on_action(action: String, data: Variant) -> void:
	if _busy or _closing:
		return
	if action == "close":
		request_close()
		return
	if not _is_current():
		request_close()
		return
	SoundManager.play_other_SFX(&"tap")
	match action:
		"mode":
			if str(data) not in ["today", "convert", "synthesize"] or _mode == str(data):
				return
			_mode = str(data)
			_tier = 0
			_selected.clear()
			_result = ""
		"tier":
			_tier = clampi(int(data), 0, 4 if _mode == "convert" else 3)
		"select":
			if _selected.size() >= (2 if _mode == "convert" else 3):
				return
			for entry: Dictionary in _service.available(_mode, _selected, _tier): # 只允许追加仍有余量的合法候选。
				if str(entry.id) == str(data):
					_selected.append(str(data))
					_result = ""
					break
		"remove":
			if int(data) >= 0 and int(data) < _selected.size():
				_selected.remove_at(int(data))
		"clear":
			_selected.clear()
		"retry":
			_sync_day()
		"refresh", "buy", "combine":
			_busy = true
			var outcome: Dictionary = {} # 所有资产结果都来自事务服务，不提前展示成功。
			if action == "refresh":
				outcome = _service.refresh(int(data))
			elif action == "buy":
				outcome = _service.buy(int(data.revision), int(data.slot))
			else:
				outcome = _service.combine(_mode, _selected)
			_busy = false
			if outcome.ok:
				var gained: String = str(outcome.get("book", "")) # 已保存结果才进入提示及预览。
				if action == "combine":
					_selected.clear()
					_result = gained
				_feedback.present("书架已更新" if gained.is_empty() else "已获得技能书",
					"" if gained.is_empty() else "%s · %s" % [View.Names.plant_name(int(Service.Rules.Books.definition(gained).plant_type)), Service.Rules.Books.definition(gained).title], true)
			else:
				_feedback.present("操作未完成", str(outcome.message), false)
				# 午夜前按钮提交时先拒绝收费，再独立刷新免费货架。
				if AdventureQuestService.today() != _observed_day:
					_sync_day()
	_render()

## 同步日期；失败记住本次观察日期，避免每秒重复存档与提示，可手动重试。
func _sync_day() -> void:
	if not _is_current():
		return
	_observed_day = AdventureQuestService.today()
	_busy = true
	var outcome: Dictionary = _service.ensure_today() # 首次免费货架也必须先落盘。
	_busy = false
	if not outcome.ok:
		_feedback.present("书架未更新", str(outcome.message), false)

## 定时确认日期与档案身份；自然日变化后重绘整批货架。
func _check_day() -> void:
	if _closing or _busy:
		return
	if not _is_current():
		request_close()
	elif AdventureQuestService.today() != _observed_day:
		_sync_day()
		_render()

## [param _amount] 是新余额通知；延迟连接避免在事务提交中重绘临时状态。
func _coins_changed(_amount: int) -> void:
	if not _busy:
		_render()

## 档案切换关闭旧窗口，同档重命名继续使用当前货架。
func _profile_changed() -> void:
	if not _is_current():
		request_close()

## [param event] 的取消键关闭模态，并拦截同一按键继续传给背景。
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()

## 播放关闭动效，结束后释放宿主引用；退出期间不允许再次交易。
func request_close() -> void:
	if _closing or _busy:
		return
	_closing = true
	if is_instance_valid(_fade):
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.14)
	_fade.tween_callback(_finish_close)

## 关闭信号只发出一次，统一模态管理器负责恢复主菜单交互。
func _finish_close() -> void:
	closed.emit()
	queue_free()
