## 按来源管理固定格挡；同类来源取最大值，在护甲分流前每次伤害仅结算一次。
extends RefCounted
class_name DamageBlockEffect

## 有效格挡数值改变，供身体颜色等表现订阅。
signal changed(value: int)
## 来源实例 ID 到格挡值；来源离树时由施加者移除。
var _sources: Dictionary[int, int] = {}
## 当前最高格挡值，始终非负。
var value: int = 0

## [param source_id] 为效果来源实例 ID；[param amount] 不大于零时移除该来源。
func set_source(source_id: int, amount: int) -> void:
	if amount > 0:
		_sources[source_id] = amount
	else:
		_sources.erase(source_id)
	# 重算最高值，移除某面旗不会清除其他来源的格挡。
	var next_value: int = 0
	for amount_value: int in _sources.values(): # 每个有效来源的固定减伤。
		next_value = maxi(next_value, amount_value)
	if value != next_value:
		value = next_value
		changed.emit(value)

## [param damage] 为原始单次伤害；零伤害不能反向治疗。
func reduce(damage: int) -> int:
	return maxi(0, damage - value)
