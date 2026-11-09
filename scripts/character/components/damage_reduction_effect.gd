## Source-tagged percentage reduction. Separate from fixed block and armor pools.
extends RefCounted
class_name DamageReductionEffect

var _sources: Dictionary[int, float] = {}

func set_source(source_id: int, reduction: float) -> void:
    if reduction <= 0.0:
        _sources.erase(source_id)
    else:
        _sources[source_id] = clampf(reduction, 0.0, 1.0)

func effective_reduction() -> float:
    var remaining := 1.0
    for reduction: float in _sources.values():
        remaining *= 1.0 - reduction
    var raw := 1.0 - remaining
    return raw if raw <= 0.7 else minf(0.9, 0.7 + (raw - 0.7) * 0.3)

func reduce(damage: int) -> int:
    return maxi(0, roundi(float(damage) * (1.0 - effective_reduction())))
