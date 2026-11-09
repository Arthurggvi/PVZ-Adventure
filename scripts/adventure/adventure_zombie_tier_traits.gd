## Authoritative species-tier rules and future Almanac prose.
## Behavior dispatch reads rule data; UI must read description_for(), not parse scripts.
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
}

const DESCRIPTIONS: Dictionary = {
    CharacterRegistry.ZombieType.Z001Norm: {},
    CharacterRegistry.ZombieType.Z002Flag: {
        &"veteran": "在场时为全场友方僵尸提供可叠加的10点固定格挡。",
        &"elite": "在场时提供可叠加的10点格挡；每2秒使全场友军啃咬伤害提高50%，持续0.5秒。",
        &"tier4": "在场时提供可叠加的15点格挡；每2秒使全场友军啃咬伤害提高100%，持续1秒。",
        &"tier5": "继承四阶能力；入场时额外使全场友军获得100%加速与无敌，持续1秒。",
    },
    CharacterRegistry.ZombieType.Z003Cone: {
        &"elite": "路障脱落后自身速度提高20%，持续0.5秒。",
        &"tier4": "路障脱落后自身速度提高50%，持续0.8秒。",
        &"tier5": "路障脱落后自身及周围八向一格友军速度提高50%，持续0.8秒。",
    },
    CharacterRegistry.ZombieType.Z004PoleVaulter: {
        &"veteran": "失去撑杆后永久提高10%移动速度。",
        &"elite": "持杆时减少20%所受伤害并提高30%速度；失杆后速度提高10%。",
        &"tier4": "持杆时减少40%所受伤害、提高50%速度，可连续跳跃两次；失杆后速度提高15%。",
        &"tier5": "继承四阶持杆与失杆强化；可连续跳跃三次，每次跨越两格距离。",
    },
    CharacterRegistry.ZombieType.Z005Bucket: {
        &"veteran": "自身获得10%伤害减免。",
        &"elite": "自身及周围八向一格友军获得20%伤害减免。",
        &"tier4": "自身及周围八向一格友军获得35%伤害减免；铁桶脱落时向该范围友军各授予200点额外护甲。",
        &"tier5": "自身伤害减免提升至50%，周围一格友军仍获35%；铁桶存在期间代替附近友军承受来袭伤害，脱桶时授予200点额外护甲。",
    },
}

static func for_spawn(zombie_type: int, tier_id: StringName) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var species: Dictionary = DEFINITIONS.get(zombie_type, {})
    for rule: Dictionary in species.get(tier_id, []):
        result.append(rule.duplicate(true))
    return result

## Public Almanac API: empty means no species-specific ability.
static func description_for(zombie_type: int, tier_id: StringName) -> String:
    var species: Dictionary = DESCRIPTIONS.get(zombie_type, {})
    return str(species.get(tier_id, ""))
