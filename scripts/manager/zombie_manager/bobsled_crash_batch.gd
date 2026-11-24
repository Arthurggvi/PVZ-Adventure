## 雪橇护甲崩坏的战场原子事务队列；只拆分不同车辆的调度帧，绝不拆散同一辆的四名队员。
extends RefCounted
class_name BobsledCrashBatch

## 一帧最多提交两辆完整雪橇，避免同帧集中产生24名独立僵尸。
const MAX_SLEDS_PER_FRAME: int = 2
## 每帧目标工作预算（微秒）；单辆雪橇已开始时必须完成原子成员交接。
const WORK_BUDGET_USEC: int = 8500

## 按触发顺序保存实例编号与弱引用，离场后仍能清除对应的排队记录。
var _queue: Array[Dictionary] = []
## 当前尚未执行的实例编号，防止同一护甲事件重复排队。
var _pending: Dictionary[int, bool] = {}

## [param sled] 已进入护甲损坏状态的原生雪橇；重复通知不重新入队。
func request(sled: Zombie014Bobsled) -> void:
	if not is_instance_valid(sled) or sled.is_queued_for_deletion() or sled.is_death:
		return
	var id: int = sled.get_instance_id() # 仅队列生命周期内有效。
	if _pending.has(id):
		return
	_pending[id] = true
	_queue.append({"id": id, "sled": weakref(sled)})

## 队列为空后由上层现有调度器自行停止逐帧处理。
func has_work() -> bool:
	return not _queue.is_empty()

## 按固定的微秒预算提交至多两辆完整雪橇；单车的创建与波次交接不会被中断。
func advance() -> void:
	var started: int = Time.get_ticks_usec() # 本帧已执行的雪橇事务耗时。
	var committed: int = 0 # 已完成的完整雪橇数。
	while not _queue.is_empty() and committed < MAX_SLEDS_PER_FRAME:
		if committed > 0 and Time.get_ticks_usec() - started >= WORK_BUDGET_USEC:
			return # 不推迟当前已开始的那辆，下一辆移至后续帧。
		var entry: Dictionary = _queue.pop_front() # 只消耗队头，保证确定性FIFO。
		_pending.erase(int(entry.id)) # 原实例已释放也必须清理排队身份。
		var reference: WeakRef = entry.sled # 不持有已死亡雪橇的强引用。
		var sled: Zombie014Bobsled = reference.get_ref() as Zombie014Bobsled
		if not is_instance_valid(sled):
			continue
		if sled.is_queued_for_deletion() or sled.is_death or not sled.is_inside_tree():
			continue
		sled.commit_queued_crash() # 原生四人队列转移及伤害语义由雪橇本身实现。
		committed += 1
