extends Resource
class_name WhiteDukeConfig
## 墓碑出土的移动倍率，独立于冰缓与白爵士给予的加速。
const GRAVE_ENTRY_SPEED_MULTIPLIER: float = 0.5

## Battle parameters and timing; 0-based lane indices are calculated from field size.
@export_range(.1,20,.1) var action_interval_phase1 := 5.0
@export_range(.1,20,.1) var action_interval_phase2 := 4.0
@export_range(10,400,.1) var lane_change_speed := 72.5
@export_range(.1,40,.1) var recent_death_window := 20.0
## 墓碑自主复生的常规间隔，单位为战斗秒。
@export_range(.1,30,.1) var grave_auto_revive_seconds := 16.0
## 新召墓碑首次自主复生的最短等待，单位为战斗秒。
@export_range(0.0, 30.0, 0.1) var grave_auto_revive_min_age := 4.0
## 由白爵士的墓碑能力生成的僵尸，从开始出土起减速的战斗秒数。
@export_range(0.1, 30.0, 0.1) var grave_entry_slow_seconds := 4.0
## 白爵士本体尝试复生的独立间隔，单位为战斗秒。
@export_range(.1,30,.1) var grave_boss_revive_seconds := 3.0
## 白爵士选取墓碑的最小逻辑列号，允许关卡从第 3 列起进一步缩小范围。
@export_range(TombStoneManager.FIRST_RANDOM_GRAVE_COLUMN, 20, 1)
var minimum_grave_column: int = TombStoneManager.FIRST_RANDOM_GRAVE_COLUMN:
	set(value):
		minimum_grave_column = maxi(TombStoneManager.FIRST_RANDOM_GRAVE_COLUMN, value)
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
