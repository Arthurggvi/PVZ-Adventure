## Ordinary sources take their maximum; explicitly stackable flag sources add.
extends RefCounted
class_name DamageBlockEffect

signal changed(value: int)
var _sources: Dictionary[int, int] = {}
var _stackable_sources: Dictionary[int, int] = {}
var value: int = 0

func set_source(source_id: int, amount: int) -> void:
    _update_source(_sources, source_id, amount)

func set_stackable_source(source_id: int, amount: int) -> void:
    _update_source(_stackable_sources, source_id, amount)

func _update_source(bucket: Dictionary, source_id: int, amount: int) -> void:
    if amount > 0:
        bucket[source_id] = amount
    else:
        bucket.erase(source_id)
    var highest := 0
    for amount_value: int in _sources.values():
        highest = maxi(highest, amount_value)
    var combined := highest
    for amount_value: int in _stackable_sources.values():
        combined += amount_value
    if combined != value:
        value = combined
        changed.emit(value)

func reduce(damage: int) -> int:
    return maxi(0, damage - value)
