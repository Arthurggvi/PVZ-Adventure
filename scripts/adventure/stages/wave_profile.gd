## 阶段的自然波次定义；波段使用闭区间，拒绝越界、重复 ID 和重叠。
extends Resource
class_name WaveProfile

## 自然波默认的生成上限；预排组和随机池共用容量。
const MAX_ZOMBIES_PER_WAVE: int = 50
## 已支持的单个冒险波次最高容量。
const MAX_CONFIGURED_ZOMBIES_PER_WAVE: int = 300
## 开场数量倍率与后段数量下限共用的开场波数。
const OPENING_WAVE_COUNT: int = 3
## 显式覆盖本阶段的单波容量。零沿用战场默认值。
@export_range(0, MAX_CONFIGURED_ZOMBIES_PER_WAVE, 1) var max_zombies_per_wave: int = 0
## 波次配置稳定 ID。
@export var profile_id: StringName = &""
## 阶段自然波次总数，必须至少有两波。
@export var wave_count: int = 0
## 启用初代 PC 冒险模式的首波保护、普通刷新倒计时与大波预警节奏。
@export var use_classic_spawn_timing: bool = false
## 初代节奏下是否保留首波准备时间；关闭后立即开波，后续仍沿用初代倒计时。
@export var classic_opening_protection: bool = true
## 初代首波保护开启时，从可种植到首波的游戏秒数。
@export var classic_opening_seconds: float = 18.0
## 首波之后的自然刷新间隔倍率，应用于正常倒计时和提前刷新计时。
@export var wave_interval_multiplier: float = 1.0
## 自然波次编排完成后保留的僵尸数量比例，1.0 表示按原计划生成。
@export_range(0.01, 1.0, 0.01) var spawn_count_multiplier: float = 1.0
## 第 1 至 3 波额外应用的数量倍率，与 [member spawn_count_multiplier] 相乘。
@export_range(0.01, 1.0, 0.01) var opening_spawn_count_multiplier: float = 1.0
## 后段减量的起始波次（含该波）；零表示不启用后段减量。
@export_range(0, 300, 1, "or_greater") var late_spawn_count_start_wave: int = 0
## 后段常规出怪在阶段基础数量上再保留的比例，最低保留前三波最少的常规出怪数。
@export_range(0.01, 1.0, 0.01) var late_spawn_count_multiplier: float = 1.0
## 缩减常规出怪时依战力提高保留概率；关闭时所有可移除项等概率。
@export var prefer_high_threat_spawns: bool = false
## 可选的大波波次（1-based）；末波始终为 Final，默认具备最终大波表现。
@export var flag_waves: Array[int] = []
## 在对应波次先于随机池生成的出怪组，顺序由资源数组决定。
@export var scheduled_spawns: Array[WaveSpawnGroup] = []
## 不进入自然波战力及权重池的特殊物种；空值不启用额外出怪。
@export var bonus_zombie_type: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Null
## 特殊物种第 1 波的保证配额，不受常规计划缩减影响。
@export_range(0, 30, 1) var bonus_first_wave_count: int = 0
## 特殊物种最后一波的保证配额；各波按线性进度递增。
@export_range(0, 30, 1) var bonus_final_wave_count: int = 0
## 该特殊物种的全场实际存活上限；超出配额等待死亡后补刷。
@export_range(0, 60, 1) var bonus_live_cap: int = 0

func is_flag_wave(wave_number: int) -> bool:
	return flag_waves.has(wave_number)

## 返回按实际刷怪顺序排列的旗帜波次，末波始终有旗帜。
func flag_wave_numbers() -> Array[int]:
	var marks: Array[int] = flag_waves.duplicate() # 不改动资源里的自定义旗帜顺序。
	if not marks.has(wave_count):
		marks.append(wave_count)
	marks.sort()
	return marks
## 可编辑的波段资源列表，不在校验期间排序或改写。
@export var bands: Array[WaveBandDefinition] = []

## 返回本阶段的配置值。没有配置时由 [param fallback] 提供战场容量。
func resolve_capacity(fallback: int = MAX_ZOMBIES_PER_WAVE) -> int:
	return max_zombies_per_wave if max_zombies_per_wave > 0 else fallback


## [param known_tier_ids] 为已实现等阶的显式目录；本类不加载任何配置或场景。
func validate(known_tier_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 每次返回全新的错误列表。
	if str(profile_id).strip_edges().is_empty():
		errors.append("波次配置缺少稳定 ID。")
	if wave_count < 2:
		errors.append("自然波次总数至少为 2。")
	if max_zombies_per_wave < 0 or max_zombies_per_wave > MAX_CONFIGURED_ZOMBIES_PER_WAVE:
		errors.append("单波僵尸容量超出支持范围。")
	if not is_finite(classic_opening_seconds) or classic_opening_seconds <= 0.0:
		errors.append("初代首波保护时间必须为正数。")
	if not is_finite(wave_interval_multiplier) or wave_interval_multiplier <= 0.0:
		errors.append("波次刷新间隔倍率必须为正数。")
	if not is_finite(spawn_count_multiplier) or spawn_count_multiplier <= 0.0 or spawn_count_multiplier > 1.0:
		errors.append("自然波次出怪数量倍率必须大于 0 且不超过 1。")
	if not is_finite(opening_spawn_count_multiplier) or opening_spawn_count_multiplier <= 0.0 or opening_spawn_count_multiplier > 1.0:
		errors.append("前 3 波出怪数量倍率必须大于 0 且不超过 1。")
	if late_spawn_count_start_wave != 0 and (late_spawn_count_start_wave <= OPENING_WAVE_COUNT \
			or late_spawn_count_start_wave > wave_count):
		errors.append("后段出怪减量必须从开场波之后的有效波次开始。")
	if not is_finite(late_spawn_count_multiplier) or late_spawn_count_multiplier <= 0.0 or late_spawn_count_multiplier > 1.0:
		errors.append("后段出怪数量倍率必须大于 0 且不超过 1。")
	var flag_seen: Dictionary = {}
	for number: int in flag_waves:
		if number < 2 or number > wave_count or flag_seen.has(number):
			errors.append("特殊大波编号越界或重复：" + str(number))
		flag_seen[number] = true
	if bonus_zombie_type != CharacterRegistry.ZombieType.Null:
		if not CharacterRegistry.ZombieType.values().has(bonus_zombie_type) \
				or int(CharacterRegistry.ZombieSpawnPower.get(bonus_zombie_type, 0)) <= 0 \
				or bonus_first_wave_count < 1 or bonus_final_wave_count < bonus_first_wave_count \
				or bonus_live_cap < 1:
			errors.append("特殊出怪物种、成长配额或存活上限无效。")
	elif bonus_first_wave_count != 0 or bonus_final_wave_count != 0 or bonus_live_cap != 0:
		errors.append("未设置特殊出怪物种时不能保留配额。")
	if bands.is_empty():
		errors.append("自然波次配置缺少波段。")
	var ids: Dictionary = {} # 本配置内的稳定波段 ID。
	for index: int in range(bands.size()): # 不依赖 Inspector 列表是否按波次排序。
		var band: WaveBandDefinition = bands[index] # 当前波段资源。
		if band == null:
			errors.append("波次配置包含空波段。")
			continue
		errors.append_array(band.validate(known_tier_ids))
		if ids.has(band.band_id):
			errors.append("波段 ID 重复：%s。" % band.band_id)
		ids[band.band_id] = true
		if band.last_wave > wave_count:
			errors.append("波段[%s]超出阶段波次数。" % band.band_id)
		for previous_index: int in range(index): # 两个区间共用任何一波都视为重叠。
			var previous: WaveBandDefinition = bands[previous_index] # 仅检查此前的非空资源。
			if previous != null and maxi(previous.first_wave, band.first_wave) <= mini(previous.last_wave, band.last_wave):
				errors.append("波段[%s]与[%s]重叠。" % [previous.band_id, band.band_id])
	var intervals: Array[Vector2i] = []
	for band: WaveBandDefinition in bands:
		if band != null and band.first_wave >= 1 and band.last_wave >= band.first_wave:
			intervals.append(Vector2i(band.first_wave, band.last_wave))
	intervals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	var next_uncovered := 1
	for interval: Vector2i in intervals:
		if interval.x > next_uncovered:
			errors.append("自然波次[%d..%d]没有波段配置。" % [next_uncovered, interval.x - 1])
		next_uncovered = maxi(next_uncovered, interval.y + 1)
	if next_uncovered <= wave_count:
		errors.append("自然波次[%d..%d]没有波段配置。" % [next_uncovered, wave_count])
	var scheduled_caps: Dictionary[int, int] = {} # 每波预排组可能占用的最大出怪数。
	for group: WaveSpawnGroup in scheduled_spawns: # 按目标波验证预排配置。
		if group == null:
			errors.append("自然波次包含空的预排出怪组。")
			continue
		errors.append_array(group.validate(wave_count, known_tier_ids))
		if group.wave < 1 or group.end_wave() > wave_count:
			continue
		for wave_number: int in range(group.wave, group.end_wave() + 1): # 逐波统计可能重叠的预排组。
			scheduled_caps[wave_number] = scheduled_caps.get(wave_number, 0) + group.count_range.y
	var scheduled_limit: int = resolve_capacity() # 显式容量允许完整指定整波阵容。
	if max_zombies_per_wave == 0:
		scheduled_limit -= 1 # 沿用默认预排波给随机池留出一个名额的规则。
	for wave_number: int in scheduled_caps: # 按最大抽取数量校验。
		if scheduled_caps[wave_number] > scheduled_limit:
			errors.append("第%d波的预排出怪超过单波配置容量。" % wave_number)
	return errors
