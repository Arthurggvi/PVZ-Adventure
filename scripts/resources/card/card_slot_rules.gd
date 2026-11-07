## 固定卡槽的容量与开战数量规则，不依赖界面、存档或场景节点。
extends RefCounted
class_name CardSlotRules

## 固定卡槽支持的最小配置容量。
const MIN_CAPACITY: int = 1
## 固定卡槽支持的最大配置容量。
const MAX_CAPACITY: int = 15

## [param capacity] 为有效的固定卡槽容量时返回 true。
static func is_valid_capacity(capacity: int) -> bool:
	return capacity >= MIN_CAPACITY and capacity <= MAX_CAPACITY

## [param selected_count] 至少为一且不超过 [param capacity] 时允许开战或续战。
static func can_start(capacity: int, selected_count: int) -> bool:
	return is_valid_capacity(capacity) and selected_count >= 1 and selected_count <= capacity
