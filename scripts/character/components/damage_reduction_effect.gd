## Source-tagged percentage reduction. Separate from fixed block and armor pools.
extends RefCounted
class_name DamageReductionEffect

var _sources: Dictionary[int, float] = {}
## 穿透软上限的特殊光场来源；普通减伤仍继续受原本体软上限约束。
var _uncapped_sources: Dictionary[int, float] = {}
## 最近一次合成的原始减伤值；来源不变时，同一帧的命中共享该值。
var _raw_reduction := 0.0
## 普通本体使用的软上限减伤，只在原始乘积改变时重新计算。
var _effective_reduction := 0.0
## 来源发生变化后，首次结算重新计算原始乘积。
var _needs_reduction_update := false

## 为 [param source_id] 写入 [param reduction] 减伤比例。零或负值撤销来源。
func set_source(source_id: int, reduction: float) -> void:
    if reduction <= 0.0:
        if _sources.erase(source_id):
            _needs_reduction_update = true
    else:
        var bounded: float = clampf(reduction, 0.0, 1.0) # 一次来源最多承担百分之百减伤。
        if _sources.get(source_id, 0.0) != bounded:
            _sources[source_id] = bounded
            _needs_reduction_update = true

## 独立光场专用减伤来源。先让普通减伤按软上限结算，再叠加无软上限的剩余伤害倍率。
## [param source_id] 是效果实例 ID；[param reduction] 为0到1的额外比例，0撤销。
func set_uncapped_source(source_id: int, reduction: float) -> void:
    var bounded: float = clampf(reduction, 0.0, 1.0)
    if bounded <= 0.0:
        if _uncapped_sources.erase(source_id):
            _needs_reduction_update = true
    elif _uncapped_sources.get(source_id, 0.0) != bounded:
        _uncapped_sources[source_id] = bounded
        _needs_reduction_update = true


## Raw multiplicative reduction is used by gear-only resistance. The soft cap
## is reserved for normal body damage and must never weaken a 80%-DR door.
func raw_reduction() -> float:
    if _needs_reduction_update:
        _update_reduction()
    return _raw_reduction

func effective_reduction() -> float:
    if _needs_reduction_update:
        _update_reduction()
    return _effective_reduction

## 对 [param damage] 应用当前本体减伤；[param independent] 为另有上限的独立免伤。
func reduce(damage: int, independent: float = 0.0) -> int:
    if _needs_reduction_update:
        _update_reduction()
    return maxi(0, roundi(float(damage) * (1.0 - _effective_reduction) * (1.0 - independent)))

func reduce_gear(damage: int) -> int:
    return maxi(0, roundi(float(damage) * (1.0 - raw_reduction())))

## 按原顺序合成各来源，同时刷新防具和本体使用的两个减伤值。
func _update_reduction() -> void:
    var remaining := 1.0 # 各减伤来源依次乘入剩余伤害比例。
    for reduction: float in _sources.values(): # 保留原乘积顺序及浮点取整边界。
        remaining *= 1.0 - reduction
    _raw_reduction = 1.0 - remaining
    _effective_reduction = _raw_reduction if _raw_reduction <= 0.7 else minf(0.9, 0.7 + (_raw_reduction - 0.7) * 0.3)
    # 例如光束的90%减伤应真正使250点变为25点，不被70%后软上限降格。
    # 不覆盖普通来源的既有保护，只对剩余伤害额外乘入该来源。
    var special_remaining: float = 1.0
    for special_reduction: float in _uncapped_sources.values():
        special_remaining *= 1.0 - special_reduction
    _effective_reduction = 1.0 - (1.0 - _effective_reduction) * special_remaining
    _raw_reduction = 1.0 - (1.0 - _raw_reduction) * special_remaining
    _needs_reduction_update = false
