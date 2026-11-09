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
        &"elite": [
            {"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
                "multiplier": 1.2, "duration": 0.5, "radius_cells": 0},
        ],
        &"tier4": [
            {"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
                "multiplier": 1.5, "duration": 0.8, "radius_cells": 0},
        ],
        &"tier5": [
            {"trigger": &"armor1_lost", "effect": &"timed_speed_boost",
                "multiplier": 1.5, "duration": 0.8, "radius_cells": 1},
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
            "spawn_armor": 200, "repeat_summon": true}],
        &"tier4": [{"effect": &"jackson_command", "pre_summon_dr": 0.5,
            "spawn_armor": 400, "repeat_summon": true,
            "heal_per_second": 30, "death_dancer": true}],
        &"tier5": [{"effect": &"jackson_command", "pre_summon_dr": 0.5,
            "spawn_armor": 400, "repeat_summon": true,
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
