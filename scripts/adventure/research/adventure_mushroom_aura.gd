## 蘑菇光环的共同生命周期；按真实棋盘增删来源，支持无效化、伴生与同帧重挂。
extends Node
class_name AdventureMushroomAura

## 兜底检查间隔，单位为受战场暂停控制的秒；不重置任何植物行为时钟。
const REFRESH_SECONDS: float = 0.2
## 入树前配置的真实来源植株，不借用同物种的其他实例。
var _plant: Plant000Base
## 首次绑定的实际战场；旧场景回调不能向新场景授予效果。
var _game: MainGameManager
## 静态目标过滤回调，接收 Plant000Base，返回是否满足该技能的附加条件。
var _accept_target: Callable
## 静态输出回调，接收目标、来源实例 ID 与启用状态；可绑定冻结规则。
var _set_target: Callable
## 上一轮受益目标的弱引用，退出快照不延长目标生命周期。
var _affected: Dictionary[int, WeakRef] = {}
## 独立监控计时器，随战场暂停，重挂后只恢复自身检查。
var _refresh_timer: Timer
## 合并父节点与控制器的离树通知，防止安排重复回收。
var _exit_cleanup_pending: bool = false

## [param plant] 是本光环的父植株；[param accept_target] 额外筛选目标。
## [param set_target] 必须为静态回调，签名为目标、来源 ID、启用状态；释放来源后仍须可调用。
## 仅在入树前配置；冻结规则应绑定到回调，不引用来源节点的方法。
func configure_aura(plant: Plant000Base, accept_target: Callable, set_target: Callable) -> void:
	_plant = plant
	_accept_target = accept_target
	_set_target = set_target

## 子节点先于植物就绪，等待原生组件完成信号绑定后再授予效果。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not is_instance_valid(_plant) or not _accept_target.is_valid() or not _set_target.is_valid():
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 每个控制器只绑定一次；种植通知晚于占位登记，负责首次同调用生效。
func _bind() -> void:
	_game = Global.main_game
	if not is_instance_valid(_game) or _game.board == null:
		return
	_plant.signal_character_death.connect(_clear, CONNECT_ONE_SHOT)
	_plant.tree_exiting.connect(_schedule_exit_cleanup)
	_plant.child_entered_tree.connect(_on_source_child_entered)
	_plant.child_exiting_tree.connect(_on_source_child_exiting)
	for cell: PlantCell in _game.board.cells(): # 只订阅变化，实际刷新仅查询来源九宫格。
		cell.signal_plant_create.connect(_on_board_change.unbind(2))
		cell.signal_plant_free.connect(_on_board_change.unbind(2))
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_SECONDS
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_refresh()
	# 父节点 ready 早于占位登记，恢复事务也可能推迟种植通知。
	_refresh.call_deferred()

## 普通种植、铲除和伴生变化均即时重算本来源。
func _on_board_change() -> void:
	_refresh()

## [param child] 为来源新子节点；无效化入树立即撤销全部贡献。
func _on_source_child_entered(child: Node) -> void:
	if child is AdventurePlantNullification:
		_clear()

## [param child] 为离开的来源子节点；待无效化彻底摘除再重新授予。
func _on_source_child_exiting(child: Node) -> void:
	if child is AdventurePlantNullification:
		_refresh.call_deferred()

## 当前控制器与来源必须仍在首次战场，真实占位且未被无效化。
func _source_active() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() \
		and MushroomPlantQuery.is_active(_plant, _game) and _plant.is_ancestor_of(self)

## 每个目标按实例去重；不同光环实例保留各自来源，受益端负责合成同类效果。
func _refresh() -> void:
	if not _source_active():
		_clear()
		return
	var next: Dictionary[int, WeakRef] = {} # 本轮目标，普通层与伴生层共用枚举。
	for cell: PlantCell in _game.board.neighbors(_plant.plant_cell): # 拓扑一步邻接包含中心格。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		for target: Plant000Base in cell.living_plants(): # 多格或重复登记只发一次来源。
			if not target.is_node_ready() or not MushroomPlantQuery.is_active(target, _game) \
					or not MushroomPlantQuery.is_mushroom(target) or not _accept_target.call(target):
				continue
			next[target.get_instance_id()] = weakref(target)
	for target_id: int in _affected: # 移出或失效的目标仅撤销本来源。
		if not next.has(target_id):
			_deliver(_affected[target_id], get_instance_id(), false, _set_target)
	for reference: WeakRef in next.values(): # 接收端幂等，重复刷新不重启原生行为。
		_deliver(reference, get_instance_id(), true, _set_target)
	_affected = next

## [param reference] 为目标弱引用；[param source_id] 为原来源 ID；[param enabled] 控制授予或撤销。
## [param receiver] 为可脱离来源节点存在的静态输出回调，目标已释放时自然跳过。
static func _deliver(reference: WeakRef, source_id: int, enabled: bool, receiver: Callable) -> void:
	var target: Plant000Base = reference.get_ref() as Plant000Base # 已释放的目标不再访问。
	if is_instance_valid(target) and receiver.is_valid():
		receiver.call(target, source_id, enabled)

## 对称撤销所有已授予来源，不清除其他光环或受益植株的自身技能。
func _clear() -> void:
	for reference: WeakRef in _affected.values(): # 即使目标已死亡，也允许接收端释放卡费等外部贡献。
		_deliver(reference, get_instance_id(), false, _set_target)
	_affected.clear()

## 承托容器重新入树后只恢复检查；首次进入由 ready 完成绑定。
func _enter_tree() -> void:
	if is_instance_valid(_game):
		_resume_monitoring.call_deferred()

## 延后区分同步重挂与真正离场；死亡信号仍立即清理。
func _exit_tree() -> void:
	_schedule_exit_cleanup()

## 重挂后恢复监控 Timer，不触碰植物自身攻击、成长或生产计时器。
func _resume_monitoring() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if is_instance_valid(_refresh_timer) and _refresh_timer.is_stopped():
		_refresh_timer.start()
	_refresh()

## 保存目标及静态回调快照，来源本帧释放后仍能回收其贡献。
func _schedule_exit_cleanup() -> void:
	if _exit_cleanup_pending:
		return
	_exit_cleanup_pending = true
	AdventureMushroomAura._finish_exit.call_deferred(
		weakref(self), get_instance_id(), _affected.duplicate(), _set_target)

## [param controller] 为可能已释放的光环；[param source_id] 是原来源身份。
## [param affected] 与 [param receiver] 保存离树快照；同帧有效回树保留效果，否则彻底撤销。
static func _finish_exit(controller: WeakRef, source_id: int, affected: Dictionary, receiver: Callable) -> void:
	var aura: AdventureMushroomAura = controller.get_ref() as AdventureMushroomAura # 控制器可在延迟前被销毁。
	if is_instance_valid(aura):
		aura._exit_cleanup_pending = false
		if aura._source_active():
			aura._resume_monitoring()
			return
		aura._clear()
	for reference: WeakRef in affected.values(): # 回收不依赖来源节点仍存活。
		_deliver(reference, source_id, false, receiver)
