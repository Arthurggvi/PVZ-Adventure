## 完整战场读档事务：先编译/构造所有恢复计划，再进行一次同步提交。
extends RefCounted
class_name BoardRestoreTransaction

## 空间准备计划，包含位姿和全部独立地形实例。
var space: BoardStateRestore
## 植物、墓碑与梯子的离树计划。
var entities: BoardRestoreEntities
## 数量派生与通知仍使用现有管理器。
var manager: PlantCellManager
## 不允许重复提交同一批实体。
var _committed: bool = false

## [param saved] 在本方法完成全部输入、资源、槽位与结构预检；失败只释放离树对象。
static func prepare(manager: PlantCellManager, saved: ResourceSaveGamePlantCellManager) -> BoardRestoreTransaction:
	if not is_instance_valid(manager) or manager.board == null or saved == null:
		return null
	var plan := BoardRestoreTransaction.new() # 一次恢复的完整所有权。
	plan.manager = manager
	plan.space = BoardStateRestore.prepare(manager.board, saved.board_state)
	if plan.space == null:
		return null
	plan.entities = BoardRestoreEntities.prepare(manager, saved)
	if plan.entities == null:
		return null
	return plan

## 所有可能正常失败的检查均在第一处状态写入之前；提交期间不跨帧、不重新实例化。
func commit() -> bool:
	if _committed or not is_instance_valid(manager) or not space.can_commit() or not entities.can_commit():
		return false
	var board: BoardRuntime = space.board # 唯一空间及其重入令牌。
	if not board.begin_restore(self):
		return false
	_committed = true
	space.apply_prepared(self)
	entities.apply_prepared()
	manager.rebuild_plant_counts()
	entities.publish()
	board.end_restore(self)
	EventBus.push_event("update_card_purple_sun_cost")
	return true
