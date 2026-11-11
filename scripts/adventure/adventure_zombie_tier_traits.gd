## Authoritative species-tier combat rules; no UI prose is stored here.
## UI reads description_for(), backed by a separate Almanac description catalog.
extends RefCounted
class_name AdventureZombieTierTraits

const DEFINITIONS: Dictionary = {
    CharacterRegistry.ZombieType.Z002Flag: {
        &"veteran": [
            {"effect": &"flag_command", "block": 10},
        ],
        &"elite": [
            {"effect": &"flag_command", "block": 10,
                "bite_multiplier": 1.5, "bite_duration": 0.5, "interval": 2.0},
        ],
        &"tier4": [
            {"effect": &"flag_command", "block": 15,
                "bite_multiplier": 2.0, "bite_duration": 1.0, "interval": 2.0},
        ],
        &"tier5": [
            {"effect": &"flag_command", "block": 15,
                "bite_multiplier": 2.0, "bite_duration": 1.0, "interval": 2.0,
                "spawn_speed": 2.0, "spawn_immunity": 1.0},
        ],
    },
    CharacterRegistry.ZombieType.Z003Cone: {
        &"veteran": [
            {"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
                "multiplier": 1.3, "duration": 0.5, "radius_cells": 0},
        ],
        &"elite": [
            {"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
                "multiplier": 1.6, "duration": 0.5, "radius_cells": 0},
        ],
        &"tier4": [
            {"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
                "multiplier": 2.0, "duration": 0.8, "radius_cells": 0},
        ],
        &"tier5": [
            {"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
                "multiplier": 2.0, "duration": 0.8, "radius_cells": 1},
        ],
    },
    CharacterRegistry.ZombieType.Z004PoleVaulter: {
        &"veteran": [
            {"effect": &"pole_stance", "pole_speed": 1.0,
                "after_speed": 1.1, "jumps": 1},
        ],
        &"elite": [
            {"effect": &"pole_stance", "pole_speed": 1.3,
                "pole_dr": 0.2, "after_speed": 1.1, "jumps": 1},
        ],
        &"tier4": [
            {"effect": &"pole_stance", "pole_speed": 1.5,
                "pole_dr": 0.4, "after_speed": 1.15, "jumps": 2},
        ],
        &"tier5": [
            {"effect": &"pole_stance", "pole_speed": 1.5,
                "pole_dr": 0.4, "after_speed": 1.15,
                "jumps": 3, "jump_distance_cells": 2},
        ],
    },
    CharacterRegistry.ZombieType.Z005Bucket: {
        &"veteran": [
            {"effect": &"self_reduction", "reduction": 0.1},
        ],
        &"elite": [
            {"effect": &"local_protection", "reduction": 0.2},
        ],
        &"tier4": [
            {"effect": &"local_protection", "reduction": 0.35},
            {"effect": &"grant_armor_on_drop", "trigger": &"armor1_lost", "amount": 200},
        ],
        &"tier5": [
            {"effect": &"local_protection", "reduction": 0.35,
                "self_reduction": 0.5, "redirect": true},
            {"effect": &"grant_armor_on_drop", "trigger": &"armor1_lost", "amount": 200},
        ],
    },

    CharacterRegistry.ZombieType.Z006Paper: {
        &"veteran": [{"effect": &"paper_rage", "immunity": 1.0}],
        &"elite": [{"effect": &"paper_rage", "immunity": 1.0, "speed": 1.3, "bite": 1.8}],
        &"tier4": [{"effect": &"paper_rage", "immunity": 1.0, "speed": 1.5, "bite": 2.5, "armor": 500}],
        &"tier5": [{"effect": &"paper_rage", "immunity": 1.0, "speed": 1.5, "bite": 2.5,
            "armor": 500, "normal_bite": 4.0}],
    },
    CharacterRegistry.ZombieType.Z007ScreenDoor: {
        &"veteran": [{"effect": &"armor2_reduction", "reduction": 0.1}],
        &"elite": [{"effect": &"armor2_reduction", "reduction": 0.3}],
        &"tier4": [{"effect": &"armor2_reduction", "reduction": 0.5}],
        &"tier5": [{"effect": &"armor2_reduction", "reduction": 0.8}],
    },
    CharacterRegistry.ZombieType.Z008Football: {
        &"veteran": [{"effect": &"football_growth", "base_speed": 1.05, "reduction": 0.05}],
        &"elite": [{"effect": &"football_growth", "base_speed": 1.05, "reduction": 0.05,
            "hit_speed_step": 0.01, "bite_step": 0.01, "degradation_step": 0.01,
            "bite_interval": 0.2, "initial_degradation": 0.01}],
        &"tier4": [{"effect": &"football_growth", "base_speed": 1.05, "reduction": 0.05,
            "hit_speed_step": 0.005, "bite_step": 0.02, "degradation_step": 0.02,
            "bite_interval": 0.2, "initial_degradation": 0.01, "armor_per_second": 20}],
        &"tier5": [{"effect": &"football_growth", "base_speed": 1.05, "reduction": 0.05,
            "hit_speed_step": 0.005, "bite_step": 0.02, "degradation_step": 0.04,
            "bite_interval": 0.2, "initial_degradation": 0.01, "armor_per_second": 60,
            "keep_degradation_counter": true}],
    },
    CharacterRegistry.ZombieType.Z009Jackson: {
        &"veteran": [{"effect": &"jackson_command", "pre_summon_dr": 0.5}],
        &"elite": [{"effect": &"jackson_command", "pre_summon_dr": 0.5,
            "spawn_armor": 200, "repeat_summon": true, "repeat_summon_interval_multiplier": 2}],
        &"tier4": [{"effect": &"jackson_command", "pre_summon_dr": 0.5,
            "spawn_armor": 400, "repeat_summon": true,
            "repeat_summon_interval_multiplier": 2,
            "heal_per_second": 30, "death_dancer": true}],
        &"tier5": [{"effect": &"jackson_command", "pre_summon_dr": 0.5,
            "spawn_armor": 400, "repeat_summon": true,
            "repeat_summon_interval_multiplier": 2,
            "heal_per_second": 30, "death_dancer": true,
            "replacement_type": CharacterRegistry.ZombieType.Z009Jackson,
            "replacement_tier": &"tier4"}],
    },
    CharacterRegistry.ZombieType.Z010Dancer: {
        &"veteran": [{"effect": &"dancer_death_burst", "entry_immunity": 0.5}],
        &"elite": [{"effect": &"dancer_death_burst",
            "entry_immunity": 0.5, "death_explosion": 1800}],
        &"tier4": [{"effect": &"dancer_death_burst",
            "entry_immunity": 0.5, "death_explosion": 3000}],
        &"tier5": [{"effect": &"dancer_death_burst",
            "entry_immunity": 0.5, "death_explosion": 3000}],
    },

    CharacterRegistry.ZombieType.Z012Snorkle: {
        &"veteran": [{"effect": &"snorkel_dive", "dive_speed": 1.3}],
        &"elite": [{"effect": &"snorkel_dive", "dive_speed": 1.5, "armor_per_second": 50}],
        &"tier4": [{"effect": &"snorkel_dive", "dive_speed": 1.5, "armor_per_second": 100}],
        &"tier5": [{"effect": &"snorkel_dive", "dive_speed": 1.5, "armor_per_second": 200}],
    },
    CharacterRegistry.ZombieType.Z013Zamboni: {
        &"veteran": [{"effect": &"zamboni_pressure", "speed_bonus": 0.2, "hit_decay": 0.01}],
        &"elite": [{"effect": &"zamboni_pressure", "speed_bonus": 0.3, "hit_decay": 0.01,
            "reduction": 0.2}],
        &"tier4": [{"effect": &"zamboni_pressure", "speed_bonus": 0.5, "hit_decay": 0.01,
            "reduction": 0.5}],
        &"tier5": [{"effect": &"zamboni_pressure", "speed_bonus": 1.0, "hit_decay": 0.01,
            "reduction": 0.5, "death_blast": 1800}],
    },
    CharacterRegistry.ZombieType.Z014Bobsled: {
        &"veteran": [{"effect": &"bobsled_upgrade", "speed": 1.1}],
        &"elite": [{"effect": &"bobsled_upgrade", "speed": 1.1,
            "degrade_time_scale": 2.0, "crush": true}],
        &"tier4": [{"effect": &"bobsled_upgrade", "speed": 1.1,
            "degrade_time_scale": 3.0, "crush": true}],
        &"tier5": [{"effect": &"bobsled_upgrade", "speed": 1.1,
            "degrade_time_scale": 0.0, "crush": true}],
    },
    CharacterRegistry.ZombieType.Z015Dolphinrider: {
        &"veteran": [{"effect": &"dolphin_leap", "ride_reduction": 0.2}],
        &"elite": [{"effect": &"dolphin_leap", "ride_reduction": 0.3,
            "jump_distance_cells": 2}],
        &"tier4": [{"effect": &"dolphin_leap", "ride_reduction": 0.5,
            "jump_distance_cells": 2, "crush_damage": 300, "ride_speed": 1.1}],
        &"tier5": [{"effect": &"dolphin_leap", "ride_reduction": 0.5,
            "jump_distance_cells": 3, "crush_damage": 1800, "ride_speed": 1.1}],
    },
    CharacterRegistry.ZombieType.Z016Jackbox: {
        &"veteran": [{"effect": &"jackbox_tier", "bite_fuse": 2.0, "blast": 8000}],
        &"elite": [{"effect": &"jackbox_tier", "on_plant_contact": true, "blast": 8000}],
        &"tier4": [{"effect": &"jackbox_tier", "on_plant_contact": true,
            "blast": 8000, "speed": 1.1, "survive_first": true}],
        &"tier5": [{"effect": &"jackbox_tier", "on_plant_contact": true,
            "blast": 16000, "speed": 1.1, "survive_first": true}],
    },
    CharacterRegistry.ZombieType.Z017Balloon: {
        &"veteran": [{"effect": &"balloon_tier", "balloon_hits": 2, "fly_speed": 1.2}],
        &"elite": [{"effect": &"balloon_tier", "balloon_hits": 2, "fly_speed": 1.2,
            "landing_blast": 1800}],
        &"tier4": [{"effect": &"balloon_tier", "balloon_hits": 3, "fly_speed": 1.2,
            "landing_blast": 3000}],
        &"tier5": [{"effect": &"balloon_tier", "balloon_hits": 5, "fly_speed": 1.2,
            "landing_blast": 5000}],
    },
    CharacterRegistry.ZombieType.Z018Digger: {
        &"veteran": [{"effect": &"digger_tier", "dig_speed": 2.0}],
        &"elite": [{"effect": &"digger_tier", "dig_speed": 2.0, "instant_walk": true}],
        &"tier4": [{"effect": &"digger_tier", "dig_speed": 2.0,
            "instant_walk": true, "walk_speed": 1.5}],
        &"tier5": [{"effect": &"digger_tier", "dig_speed": 2.0,
            "instant_walk": true, "walk_speed": 1.5, "death_blast": 1800,
            "blast_radius_cells": 1}],
    },
    CharacterRegistry.ZombieType.Z019Pogo: {
        &"veteran": [{"effect": &"pogo_tier", "jump_damage": 300}],
        &"elite": [{"effect": &"pogo_tier", "jump_damage": 600, "jump_cells": 2}],
        &"tier4": [{"effect": &"pogo_tier", "jump_damage": 600, "jump_cells": 2,
            "spawn_armor": 300}],
        &"tier5": [{"effect": &"pogo_tier", "jump_damage": 600, "jump_cells": 2,
            "spawn_armor": 300, "speed": 1.3}],
    },
    CharacterRegistry.ZombieType.Z020Yeti: {
        &"veteran": [{"effect": &"yeti_tier", "hit_speed": 0.02}],
        &"elite": [{"effect": &"yeti_tier", "hit_speed": 0.04,
            "bite_factor": 4.0, "heal": 40}],
        &"tier4": [{"effect": &"yeti_tier", "hit_speed": 0.04,
            "bite_factor": 4.0, "heal": 80}],
        &"tier5": [{"effect": &"yeti_tier", "hit_speed": 0.04,
            "bite_factor": 4.0, "heal": 120, "spawn_armor": 500}],
    },
    CharacterRegistry.ZombieType.Z021Bungi: {
        &"veteran": [{"effect": &"bungee_tier", "linger": 1.0}],
        &"elite": [{"effect": &"bungee_tier", "linger": 0.5, "block": 20}],
        &"tier4": [{"effect": &"bungee_tier", "linger": 0.0, "block": 20,
            "steal_blast": 1800}],
        &"tier5": [{"effect": &"bungee_tier", "linger": 0.0, "block": 20,
            "landing_blast": 3000}],
    },
    CharacterRegistry.ZombieType.Z022Ladder: {
        &"veteran": [{"effect": &"ladder_tier", "gear_reduction": 0.2,
            "ladder_hp": 2000}],
        &"elite": [{"effect": &"ladder_tier", "gear_reduction": 0.5,
            "ladder_hp": 2000, "all_plants": true, "nullify": true}],
        &"tier4": [{"effect": &"ladder_tier", "gear_reduction": 0.5,
            "ladder_hp": 4000, "all_plants": true, "nullify": true,
            "aura_speed": 1.5, "aura_seconds": 1.0}],
        &"tier5": [{"effect": &"ladder_tier", "gear_reduction": 0.8,
            "ladder_hp": 4000, "all_plants": true, "nullify": true,
            "nullify_persistent": true, "aura_speed": 1.5, "aura_seconds": 1.0}],
    },
    CharacterRegistry.ZombieType.Z023Catapult: {
        &"veteran": [{"effect": &"catapult_tier", "basket_multiplier": 2.0,
            "aura_dr": 0.1}],
        &"elite": [{"effect": &"catapult_tier", "basket_multiplier": 4.0,
            "aura_dr": 0.1, "shoot_moving": true}],
        &"tier4": [{"effect": &"catapult_tier", "basket_multiplier": 4.0,
            "aura_dr": 0.1, "shoot_moving": true, "blast": 1800}],
        &"tier5": [{"effect": &"catapult_tier", "basket_multiplier": 4.0,
            "aura_dr": 0.1, "shoot_moving": true, "blast": 3600,
            "volley": true, "speed": 1.5}],
    },
    CharacterRegistry.ZombieType.Z024Gargantuar: {
        &"veteran": [{"effect": &"gargantuar_tier", "speed": 1.2}],
        &"elite": [{"effect": &"gargantuar_tier", "speed": 1.2,
            "spawn_armor": 1000, "imp_each_smash": 1, "fallback_col": 2}],
        &"tier4": [{"effect": &"gargantuar_tier", "speed": 1.2,
            "spawn_armor": 1000, "imp_each_smash": 1, "fallback_col": 2,
            "smash_blast": 1800, "smash_anim_speed": 2.0}],
        &"tier5": [{"effect": &"gargantuar_tier", "speed": 1.2,
            "spawn_armor": 1000, "imp_each_smash": 1, "fallback_col": 2,
            "smash_blast": 1800, "smash_anim_speed": 2.0,
            "death_crush": true, "imp_per_throw": 3}],
    },
    CharacterRegistry.ZombieType.Z025Imp: {
        &"veteran": [{"effect": &"imp_tier", "degradation": 0.5}],
        &"elite": [{"effect": &"imp_tier", "degradation": 0.5, "death_blast": 600}],
        &"tier4": [{"effect": &"imp_tier", "degradation": 0.5, "death_blast": 1800}],
        &"tier5": [{"effect": &"imp_tier", "degradation": 0.5,
            "death_blast": 1800, "death_imps": 2, "child_tier": &"tier4"}],
    },
    CharacterRegistry.ZombieType.Z1001BobsledSingle: {
        &"veteran": [{"effect": &"permanent_species_speed", "multiplier": 1.1}],
        &"elite": [{"effect": &"permanent_species_speed", "multiplier": 1.1}],
        &"tier4": [{"effect": &"permanent_species_speed", "multiplier": 1.1}],
        &"tier5": [{"effect": &"permanent_species_speed", "multiplier": 1.1}],
    },
}

static func for_spawn(zombie_type: int, tier_id: StringName) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var species: Dictionary = DEFINITIONS.get(zombie_type, {})
    for rule: Dictionary in species.get(tier_id, []):
        result.append(rule.duplicate(true))
    return result

## Public Almanac API: empty means no species-specific ability.
const DescriptionCatalog = preload("res://scripts/adventure/adventure_zombie_tier_descriptions.gd")

static func description_for(zombie_type: int, tier_id: StringName) -> String:
    return DescriptionCatalog.get_description(zombie_type, tier_id)
