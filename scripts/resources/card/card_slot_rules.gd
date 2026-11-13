## 卡槽预算与开战数量规则；实际卡片数和普通槽消耗分别计算，不依赖界面或存档。
extends RefCounted
class_name CardSlotRules

## 固定卡槽支持的最小配置容量。
const MIN_CAPACITY: int = 1
## 固定卡槽支持的最大配置容量。
const MAX_CAPACITY: int = 15

## [param capacity] 为有效的固定卡槽容量时返回 true。
static func is_valid_capacity(capacity: int) -> bool:
	return capacity >= MIN_CAPACITY and capacity <= MAX_CAPACITY

## 至少选择一张真实卡；[param occupied_slots] 是免槽规则后的预算，省略时沿用 [param selected_count]。
## 全部卡都免槽也允许开战；[param capacity] 仍是关卡配置的普通卡上限。
static func can_start(capacity: int, selected_count: int, occupied_slots: int = -1) -> bool:
	var used: int = selected_count if occupied_slots == -1 else occupied_slots # 兼容已有普通模式调用。
	return is_valid_capacity(capacity) and selected_count >= 1 and used >= 0 and used <= capacity
