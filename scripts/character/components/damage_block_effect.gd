## Ordinary sources take their maximum; explicitly stackable flag sources add.
extends RefCounted
class_name DamageBlockEffect

signal changed(value: int)
var _sources: Dictionary[int, int] = {}
var _stackable_sources: Dictionary[int, int] = {}
var value: int = 0
## 所有可叠加旗帜来源的当前总和。
var _stacked_total := 0
## 普通来源中的最大值，和旗帜总和分别更新。
var _highest := 0

## 设置 [param source_id] 的普通格挡。[param amount] 小于等于零时撤销。
func set_source(source_id: int, amount: int) -> void:
    if _sources.get(source_id, 0) == maxi(0, amount):
        return
    if amount > 0:
        _sources[source_id] = amount
    else:
        _sources.erase(source_id)
    _highest = 0
    for amount_value: int in _sources.values(): # 只在普通来源改变时重算其最大值。
        _highest = maxi(_highest, amount_value)
    _publish()

## 按 [param source_id] 差量更新旗帜格挡。[param amount] 小于等于零时撤销。
func set_stackable_source(source_id: int, amount: int) -> void:
    var previous: int = _stackable_sources.get(source_id, 0) # 撤销或替换仅需扣除自己的旧值。
    var next: int = maxi(0, amount) # 缺失来源和清零均为中性值。
    if previous == next:
        return
    if amount > 0:
        _stackable_sources[source_id] = next
    else:
        _stackable_sources.erase(source_id)
    _stacked_total += next - previous
    _publish()

## 只在最终格挡真的发生变化时，通知生命组件与着色器。
func _publish() -> void:
    var combined: int = _highest + _stacked_total # 普通最高值加可叠加来源总和。
    if combined != value:
        value = combined
        changed.emit(value)

func reduce(damage: int) -> int:
    return maxi(0, damage - value)
