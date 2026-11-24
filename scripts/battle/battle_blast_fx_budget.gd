## 每场战斗共享的爆炸表现额度。同帧附近的同种烟焰合并，伤害不经过此处。
extends RefCounted
class_name BattleBlastFxBudget

## 每帧最多启动的粒子、烟团或碎片表演数。
const MAX_STARTS_PER_FRAME := 4
## 同时活跃的完整爆炸表演数；节点真正离树时归还额度。
const MAX_ACTIVE := 12
## 同类爆炸合并的空间单位，单位为世界像素。
const CELL_SIZE := 64.0

## 最近一次申请所处的渲染帧编号。
var _frame := -1
## 该帧实际开始的表演数。
var _started := 0
## 正在运行的带额度表演数。
var _active := 0
## 这一帧各类表演已覆盖的世界格。
var _cells: Dictionary[StringName, Dictionary] = {}


## 检查 [param kind] 在 [param origin] 是否还有表现额度。可在实例化前调用。
func can_start(kind: StringName, origin: Vector2) -> bool:
	var frame: int = Engine.get_process_frames() # 在首次申请时切换额度窗口。
	if frame != _frame:
		_frame = frame
		_started = 0
		_cells.clear()
	var covered: Dictionary = _cells.get(kind, {}) # 不合并不同种类的爆炸。
	return _started < MAX_STARTS_PER_FRAME and _active < MAX_ACTIVE \
		and not covered.has(_cell_for(origin))


## 登记已经迁移到独立层的 [param effect]，在 [param origin] 消耗一次 [param kind] 的表现额度。
## 必须在表演启用前调用，收尾由原有特效节点负责。
func track(effect: Node2D, kind: StringName, origin: Vector2) -> void:
	var covered: Dictionary = _cells.get_or_add(kind, {}) # 同类表演共享该帧的空间去重表。
	covered[_cell_for(origin)] = true
	_started += 1
	_active += 1
	effect.tree_exited.connect(_release, CONNECT_ONE_SHOT)


## 将 [param origin] 按世界坐标分格，负坐标与正坐标遵循同一边界。
func _cell_for(origin: Vector2) -> Vector2i:
	return Vector2i(floori(origin.x / CELL_SIZE), floori(origin.y / CELL_SIZE))


## 节点完成表演或随战场退出，回收一个在播名额。
func _release() -> void:
	_active -= 1
