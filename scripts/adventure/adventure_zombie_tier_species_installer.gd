## Tier ability family installer. Existing shared trigger dispatcher stays species-agnostic.
extends RefCounted
class_name AdventureZombieTierSpeciesInstaller

const EFFECTS: Array[StringName] = [
    &"paper_rage", &"armor2_reduction", &"football_growth",
    &"jackson_command", &"dancer_death_burst",
]

static func handles(effect: StringName) -> bool:
    return effect in EFFECTS

## Called after native zombie _ready: paper, dance and attack children are now initialized.
static func install(zombie: Zombie000Base, rule: Dictionary) -> void:
    if not is_instance_valid(zombie) or zombie.is_death or zombie.is_queued_for_deletion():
        return
    match StringName(rule.get("effect", &"")):
        &"paper_rage":
            var paper: Zombie006Paper = zombie as Zombie006Paper
            if paper == null:
                return
            var effect := AdventureZombiePaperRage.new()
            zombie.add_child(effect)
            effect.setup(paper, rule)
        &"armor2_reduction":
            var hp: HpComponentZombie = zombie.hp_component as HpComponentZombie
            hp.armor2_reduction.set_source(zombie.get_instance_id(),
                    float(rule.get("reduction", 0.0)))
        &"football_growth":
            var effect := AdventureZombieFootballGrowth.new()
            zombie.add_child(effect)
            effect.setup(zombie, rule)
        &"jackson_command":
            var jackson: Zombie009Jackson = zombie as Zombie009Jackson
            if jackson == null:
                return
            var effect := AdventureZombieJacksonCommand.new()
            zombie.add_child(effect)
            effect.setup(jackson, rule)
        &"dancer_death_burst":
            var dancer: Zombie010Dancer = zombie as Zombie010Dancer
            if dancer == null:
                return
            var effect := AdventureZombieDancerBurst.new()
            zombie.add_child(effect)
            effect.setup(dancer, int(rule.get("death_explosion", 0)),
                    float(rule.get("entry_immunity", 0.0)))
