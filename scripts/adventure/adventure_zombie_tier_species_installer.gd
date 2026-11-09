## Tier ability family installer. Existing shared trigger dispatcher stays species-agnostic.
extends RefCounted
class_name AdventureZombieTierSpeciesInstaller

const EFFECTS: Array[StringName] = [
    &"paper_rage", &"armor2_reduction", &"football_growth",
    &"jackson_command", &"dancer_death_burst",
    &"snorkel_dive", &"zamboni_pressure", &"bobsled_upgrade",
    &"dolphin_leap", &"permanent_species_speed",
    &"jackbox_tier", &"balloon_tier", &"digger_tier",
    &"pogo_tier", &"yeti_tier", &"bungee_tier", &"ladder_tier",
    &"catapult_tier", &"gargantuar_tier", &"imp_tier",
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
            var burst := AdventureZombieDeathBurst.new()
            zombie.add_child(burst)
            burst.setup(dancer, int(rule.get("death_explosion", 0)),
                    preload("res://resources/combat/jackbox_explosion_profile.tres"))
            AdventureZombieTimedCombatBuff.grant_immunity(
                    dancer, float(rule.get("entry_immunity", 0.0)), true)

        &"snorkel_dive":
            var snorkel: Zombie012Snorkle = zombie as Zombie012Snorkle
            if snorkel == null:
                push_error("Snorkel tier effect on non-snorkel zombie")
                return
            var effect := AdventureZombieSnorkelDive.new()
            zombie.add_child(effect)
            effect.setup(snorkel, rule)
        &"zamboni_pressure":
            var vehicle: Zombie013Zamboni = zombie as Zombie013Zamboni
            if vehicle == null:
                push_error("Zamboni tier effect on wrong species")
                return
            var effect := AdventureZombieZamboniPressure.new()
            zombie.add_child(effect)
            effect.setup(vehicle, rule)
        &"bobsled_upgrade":
            var sled: Zombie014Bobsled = zombie as Zombie014Bobsled
            if sled == null:
                push_error("Bobsled tier effect on wrong species")
                return
            var effect := AdventureZombieBobsledUpgrade.new()
            zombie.add_child(effect)
            effect.setup(sled, rule)
        &"dolphin_leap":
            var rider: Zombie015Dolphinrider = zombie as Zombie015Dolphinrider
            if rider == null:
                push_error("Dolphin tier effect on wrong species")
                return
            var effect := AdventureZombieDolphinLeap.new()
            zombie.add_child(effect)
            effect.setup(rider, rule)
        &"permanent_species_speed":
            zombie.update_speed_factor(float(rule.get("multiplier", 1.0)),
                    Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
        &"jackbox_tier":
            var jackbox: Zombie016Jackbox = zombie as Zombie016Jackbox
            if jackbox == null:
                push_error("Jackbox tier installed on wrong species")
                return
            var ability := AdventureZombieJackboxTier.new()
            jackbox.add_child(ability)
            ability.setup(jackbox, rule)
        &"balloon_tier":
            var balloon: Zombie017Balloon = zombie as Zombie017Balloon
            if balloon == null:
                push_error("Balloon tier installed on wrong species")
                return
            var ability := AdventureZombieBalloonTier.new()
            balloon.add_child(ability)
            ability.setup(balloon, rule)
        &"digger_tier":
            var digger: Zombie018Digger = zombie as Zombie018Digger
            if digger == null:
                push_error("Digger tier installed on wrong species")
                return
            var ability := AdventureZombieDiggerTier.new()
            digger.add_child(ability)
            ability.setup(digger, rule)
        &"pogo_tier":
            var pogo: Zombie019Pogo = zombie as Zombie019Pogo
            if pogo == null:
                push_error("Pogo tier installed on wrong species")
                return
            var ability := AdventureZombiePogoTier.new()
            pogo.add_child(ability)
            ability.setup(pogo, rule)
        &"yeti_tier":
            var yeti: Zombie020Yeti = zombie as Zombie020Yeti
            if yeti == null:
                push_error("Yeti tier installed on wrong species")
                return
            var ability := AdventureZombieYetiTier.new()
            yeti.add_child(ability)
            ability.setup(yeti, rule)
        &"bungee_tier":
            var bungee: Zombie021Bungi = zombie as Zombie021Bungi
            if bungee == null:
                push_error("Bungee tier installed on wrong species")
                return
            var ability := AdventureZombieBungeeTier.new()
            bungee.add_child(ability)
            ability.setup(bungee, rule)
        &"ladder_tier":
            var ladder: Zombie022Ladder = zombie as Zombie022Ladder
            if ladder == null:
                push_error("Ladder tier installed on wrong species")
                return
            var ability := AdventureZombieLadderTier.new()
            ladder.add_child(ability)
            ability.setup(ladder, rule)
        &"catapult_tier":
            var catapult: Zombie023Catapult = zombie as Zombie023Catapult
            if catapult == null:
                push_error("Catapult tier installed on wrong species")
                return
            var ability := AdventureZombieCatapultTier.new()
            catapult.add_child(ability)
            ability.setup(catapult, rule)
        &"gargantuar_tier":
            var giant: Zombie024Gargantuar = zombie as Zombie024Gargantuar
            if giant == null:
                push_error("Gargantuar tier installed on wrong species")
                return
            var ability := AdventureZombieGargantuarTier.new()
            giant.add_child(ability)
            ability.setup(giant, rule)
        &"imp_tier":
            var imp: Zombie025Imp = zombie as Zombie025Imp
            if imp == null:
                push_error("Imp tier installed on wrong species")
                return
            var ability := AdventureZombieImpTier.new()
            imp.add_child(ability)
            ability.setup(imp, rule)
