## Protector candidates are weak references; eligibility is rechecked per attack.
extends RefCounted
class_name DamageTransferEffect

var _sources: Dictionary[int, Dictionary] = {}

func set_source(source_id: int, protector: Zombie000Base, cell_width: float = 0.0) -> void:
    if is_instance_valid(protector) and cell_width > 0.0:
        _sources[source_id] = {"ref": weakref(protector), "width": cell_width}
    else:
        _sources.erase(source_id)

func select_protector(victim: Zombie000Base) -> Zombie000Base:
    if not is_instance_valid(victim) or victim.is_death or victim.is_hypno:
        return null
    var chosen: Zombie000Base = null # 没有合格保护者时明确返回空引用。
    var closest := INF
    for entry: Dictionary in _sources.values():
        var protector: Zombie000Base = (entry["ref"] as WeakRef).get_ref() as Zombie000Base
        if not is_instance_valid(protector) or protector == victim or protector.is_death \
                or protector.is_hypno or protector.is_queued_for_deletion():
            continue
        if protector.lane < 0 or victim.lane < 0:
            continue
        var width: float = float(entry["width"])
        if absi(protector.lane - victim.lane) > 1 \
                or absf(protector.global_position.x - victim.global_position.x) > width:
            continue
        var health: HpComponentZombie = protector.get_node_or_null("HpComponent") as HpComponentZombie
        if health == null or health.curr_hp_armor1 <= 0:
            continue
        var distance: float = absf(protector.global_position.x - victim.global_position.x) + \
                float(absi(protector.lane - victim.lane)) * width
        if distance < closest or (is_equal_approx(distance, closest) \
                and (chosen == null or protector.get_instance_id() < chosen.get_instance_id())):
            chosen = protector
            closest = distance
    return chosen
