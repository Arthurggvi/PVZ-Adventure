## 一次手持卡点击共用的放置上下文；只缓存查询和实际提交，不进入卡牌或战斗存档。
extends RefCounted
class_name PlantPlacementUseContext

## 效果族到已消费的实体身份；列种植与范围重叠共用同一集合。
var _claimed: Dictionary[StringName, Dictionary] = {}
## 地格实例身份到首次死亡记录；必须保存 null，不能在付血后改认新死者。
var _death_records: Dictionary[int, PlantDeathRecord] = {}
## 已整体冻结的空间，确保同杯造成的跨格死亡也不会成为后来中心格的新目标。
var _death_boards: Dictionary[int, bool] = {}

## 查询 [param family] 是否已作用于 [param target]；预览与提交前复核不会消费身份。
func has_target(family: StringName, target: Node) -> bool:
	return is_instance_valid(target) and _claimed.get(family, {}).has(target.get_instance_id())

## 在真正执行 [param family] 前认领 [param target]；返回 false 表示本次点击已处理过它。
func claim_target(family: StringName, target: Node) -> bool:
	if not is_instance_valid(target) or has_target(family, target):
		return false
	var identities: Dictionary = _claimed.get(family, {}) # 每族共享身份，避免同株在多格重复付血。
	identities[target.get_instance_id()] = true
	_claimed[family] = identities
	return true

## 首次查询 [param cell] 时先冻结整个空间，包含不存在尸体的格子。
## 此方法不产生游戏效果；重复资格查询只能复用第一次记录，不能换成同杯新死者。
func snapshot_death_record(cell: PlantCell) -> PlantDeathRecord:
	if not is_instance_valid(cell) or cell.board == null:
		return null
	var board_id: int = cell.board.get_instance_id() # 相同逻辑坐标在不同空间不共享尸体记录。
	if not _death_boards.has(board_id):
		_death_boards[board_id] = true
		for target: PlantCell in cell.board.cells(): # 在任何目标付血前批量捕获，含多格占位的原点。
			_death_records[target.get_instance_id()] = PlantRevivalArchive.snapshot_record(target)
	return _death_records.get(cell.get_instance_id()) as PlantDeathRecord
