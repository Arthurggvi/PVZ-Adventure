## 月光蔓延的单株光环；按棋盘拓扑授予原生睡眠豁免，不改永久唤醒或占位。
extends Node
class_name AdventureMushroomAwakeAura

## 兜底检查的战斗秒数；只查询来源周围，处理移动、环境及外部状态变化。
const REFRESH_SECONDS: float = 0.2
## 本株来源，由冻结转职控制器在入树前配置。
var _plant: Plant000Base
## 本次绑定的实际战场，防止跨场景借用旧棋盘。
var _game: MainGameManager
## 上一轮获得本来源豁免的弱引用，不延长已离场植物的生命周期。
var _affected: Dictionary[int, WeakRef] = {}
## 独立监控计时器；短暂重挂后仅在原生计时已停止时恢复检查。
var _refresh_timer: Timer
## 一次同步离树过程只安排一次回收，父节点与控制器离树通知可以重合。
var _exit_cleanup_pending: bool = false

## [param plant] 为持有月光蔓延的真实植株；本控制器须挂在该植株下。
func configure(plant: Plant000Base) -> void:
	_plant = plant

## 子节点先于植物就绪，等原生 Sleep 信号全部绑定后再开始授予豁免。
func _ready() -> void:
	# 独立继承战场暂停；来源被无效化禁用时仍能撤销光环，不执行其植物行为。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not is_instance_valid(_plant):
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 每株只绑定一次；占位登记后的种植通知负责同一调用内即时唤醒。
func _bind() -> void:
	_game = Global.main_game
	if not is_instance_valid(_game) or _game.board == null:
		return
	_plant.signal_character_death.connect(_clear, CONNECT_ONE_SHOT)
	_plant.tree_exiting.connect(_schedule_exit_cleanup)
	_plant.child_entered_tree.connect(_on_source_child_entered)
	_plant.child_exiting_tree.connect(_on_source_child_exiting)
	for cell: PlantCell in _game.board.cells(): # 只订阅棋盘变化，刷新仍仅扫描九宫格。
		cell.signal_plant_create.connect(_on_board_change.unbind(2))
		cell.signal_plant_free.connect(_on_board_change.unbind(2))
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_SECONDS
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_refresh()
	# 父节点 ready 早于占位登记；恢复事务可能延后种植通知，再补一次首次刷新。
	_refresh.call_deferred()

## 种植、铲除或伴生植株变化即时生效，避免等待下一次周期检查。
func _on_board_change() -> void:
	_refresh()

## [param child] 为来源新加入的子节点；无效化节点入树时立即收回贡献。
func _on_source_child_entered(child: Node) -> void:
	if child is AdventurePlantNullification:
		_clear()

## [param child] 为正在离开的子节点；解除无效化后等待该节点彻底摘除再重算。
func _on_source_child_exiting(child: Node) -> void:
	if child is AdventurePlantNullification:
		_refresh.call_deferred()

## 来源必须仍属于本战场、真实登记在格子内且没有被无效化。
## 平台整体平移保留逻辑格身份；不按世界像素距离错误改变邻接。
func _source_active() -> bool:
	if not is_inside_tree() or is_queued_for_deletion() \
			or not is_instance_valid(_plant) or not is_instance_valid(_game) \
			or not _plant.is_ancestor_of(self) or _plant.is_death or _plant.is_queued_for_deletion() \
			or not _plant.is_inside_tree() or not _game.is_inside_tree() \
			or _game.is_queued_for_deletion() or Global.main_game != _game \
			or not _game.is_ancestor_of(_plant) or _game.board == null \
			or _plant.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or _plant.process_mode == Node.PROCESS_MODE_DISABLED \
			or _plant.has_node(NodePath(AdventurePlantNullification.NODE_NAME)):
		return false
	var source_cell: PlantCell = _plant.plant_cell # 每轮读取当前归属，允许后续迁格。
	return is_instance_valid(source_cell) and not source_cell.is_queued_for_deletion() \
		and source_cell.board == _game.board and source_cell.living_plants().has(_plant)

## 按来源实例独立增删；重叠光环撤销其中一个不会覆盖另一个。
func _refresh() -> void:
	if not _source_active():
		_clear()
		return
	var next: Dictionary[int, WeakRef] = {} # 本轮真实受益者，普通占位和伴生共享查询。
	for cell: PlantCell in _game.board.neighbors(_plant.plant_cell): # 一步拓扑邻接即规则地图的三乘三。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		for target: Plant000Base in cell.living_plants(): # 同实例跨格或多层引用只授予一次。
			if not (target.native_day_sleep or target.is_sleep_in_day) \
					or not target.is_node_ready() or not is_instance_valid(target.sleep_component):
				continue
			next[target.get_instance_id()] = weakref(target)
	for target_id: int in _affected: # 撤销移出范围或离场目标上的本株来源。
		if not next.has(target_id):
			_set_target(_affected[target_id], false)
	for target_id: int in next: # 原生 SleepComponent 对相同来源幂等，不重复启动生产时钟。
		_set_target(next[target_id], true)
	_affected = next

## [param reference] 是目标弱引用；[param enabled] 仅更改本光环实例的豁免条目。
func _set_target(reference: WeakRef, enabled: bool) -> void:
	var target: Plant000Base = reference.get_ref() as Plant000Base # 已销毁目标自然忽略。
	if is_instance_valid(target) and is_instance_valid(target.sleep_component):
		target.sleep_component.set_awake_source(get_instance_id(), enabled)

## 撤销本株的全部贡献；SleepComponent 自行保留其他来源、咖啡豆与夜晚清醒。
func _clear() -> void:
	for reference: WeakRef in _affected.values(): # 无论来源死亡还是控制器单独被移除都对称释放。
		_set_target(reference, false)
	_affected.clear()

## 承托容器重挂会短暂离树；重新进入后只恢复监控，不制造睡眠状态抖动。
func _enter_tree() -> void:
	if is_instance_valid(_game):
		_resume_monitoring.call_deferred()

## 保留来源计数直至整次同步重挂完成；实际死亡仍由死亡信号立即清理。
func _exit_tree() -> void:
	_schedule_exit_cleanup()

## 原生监控 Timer 若因离树停止则重新启动；不重置植物的任何行为计时器。
func _resume_monitoring() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if is_instance_valid(_refresh_timer) and _refresh_timer.is_stopped():
		_refresh_timer.start()
	_refresh()

## 静态回收任务保存弱引用快照，控制器本帧被释放后仍能撤销全部已授予来源。
func _schedule_exit_cleanup() -> void:
	if _exit_cleanup_pending:
		return
	_exit_cleanup_pending = true
	AdventureMushroomAwakeAura._finish_exit.call_deferred(weakref(self), get_instance_id(), _affected.duplicate())

## [param controller] 是可能已释放的控制器弱引用；[param source_id] 是其原始来源身份。
## [param affected] 保存离树时的受益者；同帧正常回树则保留并重算，真正离场才撤销。
static func _finish_exit(controller: WeakRef, source_id: int, affected: Dictionary) -> void:
	var aura: AdventureMushroomAwakeAura = controller.get_ref() as AdventureMushroomAwakeAura # 已释放时仍可用快照回收。
	if is_instance_valid(aura):
		aura._exit_cleanup_pending = false
		if aura._source_active():
			aura._resume_monitoring()
			return
		aura._clear()
	for reference: WeakRef in affected.values(): # 不依赖来源节点仍然存在，避免永久残留豁免。
		var target: Plant000Base = reference.get_ref() as Plant000Base # 目标也可能已随关卡释放。
		if is_instance_valid(target) and is_instance_valid(target.sleep_component):
			target.sleep_component.set_awake_source(source_id, false)
