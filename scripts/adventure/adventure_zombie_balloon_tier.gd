## Balloon hit points are literal number of hits, not tier-scaled normal HP.
## Fall explosion is armed only by a popped balloon landing, not by ordinary
## death, Blover off-screen exit, or other forms of elimination.
extends AdventureZombieTierAbility
class_name AdventureZombieBalloonTier

const PROFILE := preload("res://resources/combat/jackbox_explosion_profile.tres")

var _balloon: Zombie017Balloon
var _landing_burst: AdventureZombieDeathBurst

func setup(balloon: Zombie017Balloon, rule: Dictionary) -> void:
    bind_tier(balloon)
    _balloon = balloon
    (balloon.hp_component as HpComponentZombie).configure_fragile_armor1(
            int(rule.get("balloon_hits", 1)))
    set_tier_speed(float(rule.get("fly_speed", 1.0)))
    var damage: int = int(rule.get("landing_blast", 0))
    if damage > 0:
        _landing_burst = AdventureZombieDeathBurst.new()
        balloon.add_child(_landing_burst)
        _landing_burst.setup(balloon, damage, PROFILE, false)
        balloon.balloon_landed.connect(_on_landed)
    (balloon.hp_component as HpComponentZombie).signal_armor1_death.connect(_on_balloon_lost)
    _tier_state_changed(tier_enabled())

## [param active] 仅切换固定受击规则，不重建气球血量；沉默期间恢复原生一击破球。
func _tier_state_changed(active: bool) -> void:
    if is_instance_valid(_balloon):
        var hp: HpComponentZombie = _balloon.hp_component as HpComponentZombie # 保留已消耗的气球命中次数。
        hp.armor1_fixed_damage_per_hit = 1 if active else maxi(1, hp.curr_hp_armor1)

func _on_balloon_lost() -> void:
    if is_instance_valid(_balloon):
        set_tier_speed(1.0)

func _on_landed() -> void:
    if not tier_can_trigger():
        return
    if not is_instance_valid(_balloon) or _balloon.is_death or not _balloon.is_pop \
            or _landing_burst == null:
        return
    _landing_burst.trigger_once()
    _balloon.character_death_disappear()
