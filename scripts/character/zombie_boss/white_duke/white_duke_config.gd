extends Resource
class_name WhiteDukeConfig
## Battle parameters and timing; 0-based lane indices are calculated from field size.
@export_range(.1,20,.1) var action_interval_phase1 := 5.0
@export_range(.1,20,.1) var action_interval_phase2 := 4.0
@export_range(10,400,.1) var lane_change_speed := 72.5
@export_range(.1,40,.1) var recent_death_window := 20.0
@export_range(.1,30,.1) var grave_auto_revive_seconds := 8.0
@export_range(.1,30,.1) var grave_boss_revive_seconds := 3.0
## 0-based: 0 and 1 are reserved for player defence, never targeted by this boss.
@export_range(0,20,1) var minimum_grave_column := 2
@export var entrance_graves := 5
@export var skill_graves := 2
@export var skill_graves_phase2_bonus := 2
@export var phase_revival_limit := 30
@export var phase_grave_columns := 3
@export var summon_release_at := .70
@export var fury_speed_multiplier := 2.0
@export var fury_seconds := 2.0
@export var immunity_seconds := .5

func action_delay(phase: int) -> float:
	return action_interval_phase2 if phase>=2 else action_interval_phase1
