## Boss 遭遇元数据，与普通僵尸池分离；不实例化 Boss、不暂停波次、不执行召唤。
extends Resource
class_name BossEncounterDefinition

## 遭遇时机；EVENT_ONLY 只允许由静态事件引用，不猜测默认波次。
enum Timing { UNSET, PHASE_START, WAVE_BEFORE, WAVE_STARTED, WAVE_CLEARED, EVENT_ONLY }
## 自然波次暂停策略；恢复边界明确为 Boss 离场。
enum NaturalWaves { UNSET, CONTINUE, PAUSE_UNTIL_BOSS_EXIT }
## 是否持续周期召唤，NONE 与未配置不同。
enum SummonRule { UNSET, NONE, PERIODIC }
## 自然波次暂停时周期召唤是否继续，必须显式决定。
enum SummonWhilePaused { UNSET, CONTINUE, PAUSE_WITH_WAVES }
## 周期召唤生命周期终点。
enum SummonEnd { UNSET, BOSS_EXIT, PHASE_END }
## 遭遇稳定 ID，供阶段事件引用。
@export var encounter_id: StringName = &""
## Boss 专用枚举，不以普通僵尸物种池代替。
@export var boss_type: CharacterRegistry.ZombieBossType = CharacterRegistry.ZombieBossType.Null
## 显式遭遇触发时机。
@export var timing: Timing = Timing.UNSET
## 波次型触发的目标波次；非波次型必须为 0。
@export var wave: int = 0
## 自然波次在遭遇期间的行为。
@export var natural_waves: NaturalWaves = NaturalWaves.UNSET
## 周期召唤规则，不沿用 Boss AI 内部默认值。
@export var summon_rule: SummonRule = SummonRule.UNSET
## 是否等死亡演出结束后才结束遭遇；默认保持旧 Boss 的死亡即结束行为。
@export var wait_for_death_presentation: bool = false
## 自然波次暂停期间是否继续召唤。
@export var summon_while_paused: SummonWhilePaused = SummonWhilePaused.UNSET
## 召唤终止边界。
@export var summon_end: SummonEnd = SummonEnd.UNSET
## 周期秒数，-1 表示未配置或未启用周期召唤。
@export var summon_interval_seconds: float = -1.0
## 每批召唤数量，启用周期召唤时必须为正整数。
@export var summon_count: int = 0
## 仅本遭遇控制器周期援军的存活上限；Boss AI 的技能召唤由 Boss 技能资源独立管理。
@export var max_alive_periodic_summons: int = 0
## 召唤物只使用普通僵尸物种，不混入 Boss。
@export var summon_zombie_weights: Dictionary[CharacterRegistry.ZombieType, int] = {}
## 召唤物等阶需由调用方提供已定义 ID 目录。
@export var summon_tier_weights: Dictionary[StringName, int] = {}

## [param wave_count] 为阶段总波数，[param known_tier_ids] 为真实存在的等阶目录；只返回错误。
func validate(wave_count: int = 0, known_tier_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 遭遇本身与召唤池的静态错误。
	if str(encounter_id).strip_edges().is_empty():
		errors.append("Boss 遭遇缺少稳定 ID。")
	if boss_type == CharacterRegistry.ZombieBossType.Null or not CharacterRegistry.ZombieBossType.values().has(boss_type):
		errors.append("Boss 遭遇类型未配置或无效。")
	if timing == Timing.UNSET or not Timing.values().has(timing):
		errors.append("Boss 遭遇触发时机未配置或无效。")
	if timing in [Timing.WAVE_BEFORE, Timing.WAVE_STARTED, Timing.WAVE_CLEARED]:
		if wave < 1 or wave > wave_count:
			errors.append("Boss 遭遇触发波次越界。")
	elif wave != 0:
		errors.append("非波次 Boss 遭遇不能填写 wave。")
	if natural_waves != NaturalWaves.PAUSE_UNTIL_BOSS_EXIT:
		errors.append("冒险 Boss 出现后必须挂起自然波次，离场后恢复。")
	if summon_rule not in [SummonRule.PERIODIC, SummonRule.NONE]:
		errors.append("Boss 必须显式配置周期援军或仅由自身技能召唤。")
	if summon_rule == SummonRule.PERIODIC:
		if not is_finite(summon_interval_seconds) or summon_interval_seconds <= 0.0 or summon_count < 1 or max_alive_periodic_summons < summon_count:
			errors.append("周期召唤的间隔、批量或存活上限无效。")
		if summon_while_paused != SummonWhilePaused.CONTINUE:
			errors.append("Boss 存活时援军必须独立于自然波次持续刷新。")
		if summon_end != SummonEnd.BOSS_EXIT:
			errors.append("Boss 死亡或撤退后必须终止援军刷新。")
		errors.append_array(WaveBandDefinition.validate_pool(summon_zombie_weights, summon_tier_weights, known_tier_ids))
	elif summon_rule == SummonRule.NONE:
		if summon_interval_seconds != -1.0 or summon_count != 0 or max_alive_periodic_summons != 0 \
			or not summon_zombie_weights.is_empty() or not summon_tier_weights.is_empty() \
			or summon_while_paused != SummonWhilePaused.UNSET or summon_end != SummonEnd.UNSET:
			errors.append("不召唤的遭遇不能残留周期召唤参数。")
	return errors
