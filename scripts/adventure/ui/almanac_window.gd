## 冒险图鉴模态窗口；协调发现目录、独立 Boss 档案及无需解锁的 Buff 说明与演示。
extends Control

## 由工具栏统一清理模态引用。
signal closed
## 固定画布与目录、故事、阶级控件。
const Layout = preload("res://scripts/adventure/ui/almanac_layout.gd")
## 窗口私有的可见项资源准备队列。
const ResourcePresenter = preload("res://scripts/adventure/ui/almanac_resource_presenter.gd")
## 植物和僵尸按发现记录筛选。
const Data = preload("res://scripts/adventure/ui/almanac_data.gd")
## Boss 使用独立只读目录。
const BossData = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
## Buff 使用完整状态目录，不要求战斗发现或阶级。
const BuffData = preload("res://scripts/adventure/ui/buff_almanac_data.gd")
## 打开时所属档案，切档后不展示旧记录。
var _state: AdventureState
## 入口指定的初始分类，在加入场景树之前设置。
var initial_kind: String = "plant"
## 旧版图鉴只显示 Boss，不切换为冒险发现目录。
var boss_only: bool = false
## 当前分类，不保存到玩家档案。
var _kind: String = "plant"
## 当前筛选文本；分类切换时保留。
var _search: String = ""
## 当前稳定条目编号，0 表示空目录。
var _selected: int = 0
## 植物和僵尸当前阶级，首次选择默认一阶。
var _tier: int = 1
## 所有可见控件的独立布局组件。
var _layout: Layout
## 每个窗口独占的请求队列与资源强引用。
var _presenter: ResourcePresenter = ResourcePresenter.new()
## 每次选择、阶级或目录变化递增，旧结果不得覆盖新内容。
var _revision: int = 0
## 详情准备优先于滚动目录头像。
var _detail_pending: bool = false
## 加载失败时允许再次点击同一条目重试。
var _detail_failed: bool = false
## 防止关闭淡出期间继续操作或交付旧请求。
var _closing: bool = false

## 声明首屏公共皮肤，角色和 Buff 演示依赖仍由当前选择决定。
static func get_initial_resource_paths() -> PackedStringArray:
	return ResourcePresenter.initial_resource_paths()

## 首屏可见头像及选中详情就绪后，工具栏才移除可取消反馈。
func is_content_ready() -> bool:
	return _layout != null and not _closing and not _detail_pending and not _presenter.is_busy() and _layout.directory.next_portrait_id() == 0

## 建立布局并连接档案与发现通知；只读图鉴不写入发现记录。
func _ready() -> void:
	_state = Global.global_game_state.adventure_state
	_kind = "boss" if boss_only else (initial_kind if ["plant", "zombie", "boss", "buff"].has(initial_kind) else "plant")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new() # 模态暗幕拦截地图点击，工具栏仍使用自己的层级。
	shade.color = Color(0.035, 0.045, 0.025, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_layout = Layout.new()
	_layout.boss_only = boss_only
	_layout.close_requested.connect(request_close)
	_layout.kind_requested.connect(_choose_kind)
	_layout.search_changed.connect(_search_changed)
	_layout.tier_requested.connect(_choose_tier)
	add_child(_layout)
	_layout.directory.selected.connect(_select)
	Global.almanac_changed.connect(_refresh)
	Global.user_manager.signal_users_update.connect(_profile_changed)
	resized.connect(_fit)
	_refresh()
	_fit()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	SoundManager.play_other_SFX(&"buttonclick")

## [param _delta] 为帧间隔；每帧最多交付一套预览，选中详情优先于可见目录头像。
func _process(_delta: float) -> void:
	if _closing or _layout == null:
		return
	if _presenter.is_busy():
		_finish_preview(_presenter.poll())
		return
	if _detail_pending:
		_finish_preview(_presenter.request(_kind, _selected, _tier, true, _revision))
		return
	var type_id: int = _layout.directory.next_portrait_id() # 只有可见且尚未处理的角色才申请资源。
	if type_id != 0:
		_finish_preview(_presenter.request(_kind, type_id, 1, false, _revision))

## 校验 [param job] 的完整身份后交付；空结果表示仍在加载，失效结果直接丢弃。
func _finish_preview(job: Dictionary) -> void:
	if job.is_empty() or int(job.revision) != _revision or str(job.kind) != _kind:
		return
	if bool(job.detail):
		if int(job.type_id) != _selected or int(job.tier) != _tier:
			return
		_detail_pending = false
		_detail_failed = not bool(job.loaded)
		_layout.details.show_entry(_kind, _selected, _tier, bool(job.loaded))
	else:
		_layout.directory.draw_portrait(int(job.type_id), bool(job.loaded))

## 视口变化后复用原图鉴的等比缩放与工具栏留白。
func _fit() -> void:
	_layout.fit_to(size)

## 切换到 [param kind]；旧版入口仅接纳 Boss，新的分类从一阶开始并保留搜索词。
func _choose_kind(kind: String) -> void:
	if _closing or (boss_only and kind != "boss") or not ["plant", "zombie", "boss", "buff"].has(kind):
		return
	_kind = kind
	_selected = 0
	_layout.directory.reset_scroll()
	_refresh()
	SoundManager.play_other_SFX(&"tap")

## 根据 [param value] 重新筛选；Buff 的名称、类别、规则与来源由其目录统一匹配。
func _search_changed(value: String) -> void:
	if _closing:
		return
	_search = value
	_layout.directory.reset_scroll()
	_refresh()

## 重建当前目录；植物和僵尸遵守发现记录，Boss 与 Buff 使用各自完整只读资料。
func _refresh() -> void:
	if _closing or _state != Global.global_game_state.adventure_state:
		return
	var entries: Array[Dictionary] = ( # 过滤后的目录快照，不持有战斗实例。
		BuffData.rows(_search) if _kind == "buff"
		else (BossData.rows(_search) if _kind == "boss" else Data.rows(_state, _kind, _search)))
	_layout.directory.rebuild(entries, _kind, _search)
	if not _layout.directory.has_type(_selected):
		_selected = int(entries[0].type_id) if not entries.is_empty() else 0
		_tier = 1
	_render_detail()

## 选择 [param type_id] 并回到一阶；加载失败后允许再次点击同一条目重试。
func _select(type_id: int) -> void:
	if _closing or not _layout.directory.has_type(type_id):
		return
	if _selected == type_id and not _detail_failed:
		_layout.directory.set_selected(type_id)
		return
	_tier = 1 if _selected != type_id else _tier
	_selected = type_id
	_render_detail()
	SoundManager.play_other_SFX(&"tap")

## 查看 [param tier]；仅植物与僵尸具有五阶，发现后全部开放且不受库存卡等级限制。
func _choose_tier(tier: int) -> void:
	if _closing or _selected == 0 or (_kind != "plant" and _kind != "zombie"):
		return
	if tier == _tier and not _detail_failed:
		_layout.set_selection(_kind, _selected, _tier)
		return
	_tier = clampi(tier, 1, 5)
	_render_detail()
	SoundManager.play_other_SFX(&"tap")

## 当帧撤销旧请求和旧画面，同时更新故事与阶级栏；新详情等待资源队列交付。
func _render_detail() -> void:
	_revision += 1
	_presenter.cancel()
	_detail_pending = _selected != 0
	_detail_failed = false
	_layout.set_selection(_kind, _selected, _tier)
	if _detail_pending:
		_layout.details.show_loading()
	else:
		_layout.details.show_entry(_kind, 0, _tier)

## 离场时移交在途批次并释放窗口资源，不同步等待后台线程。
func _exit_tree() -> void:
	_presenter.dispose()

## 切换档案时关闭旧图鉴；同一档案重命名不影响当前内容。
func _profile_changed() -> void:
	if _state != Global.global_game_state.adventure_state:
		request_close()

## [param event] 为当前输入；Esc 关闭并拦截事件，避免传到地图或其他窗口。
func _input(event: InputEvent) -> void:
	if not _closing and event.is_action_pressed(&"ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()

## 遵守工具栏模态契约，先撤销请求交付，再淡出并且只发出一次 closed 信号。
func request_close() -> void:
	if _closing:
		return
	_closing = true
	_presenter.cancel()
	SoundManager.play_other_SFX(&"buttonclick")
	var tween: Tween = create_tween() # 短淡出不改变宿主场景或玩家资产。
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func() -> void: closed.emit(); queue_free())
