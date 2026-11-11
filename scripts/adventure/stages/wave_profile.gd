## 阶段的自然波次定义；波段使用闭区间，拒绝越界、重复 ID 和重叠。
extends Resource
class_name WaveProfile

## 自然波默认的生成上限；预排组和随机池共用容量。
const MAX_ZOMBIES_PER_WAVE: int = 50
## 波次配置稳定 ID。
@export var profile_id: StringName = &""
## 阶段自然波次总数，必须至少有两波。
@export var wave_count: int = 0
## 启用初代 PC 冒险模式的首波保护、普通刷新倒计时与大波预警节奏。
@export var use_classic_spawn_timing: bool = false
## 可选的大波波次（1-based）；末波始终为 Final，默认具备最终大波表现。
@export var flag_waves: Array[int] = []
## 在对应波次先于随机池生成的出怪组，顺序由资源数组决定。
@export var scheduled_spawns: Array[WaveSpawnGroup] = []

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

## [param known_tier_ids] 为已实现等阶的显式目录；本类不加载任何配置或场景。
func validate(known_tier_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 每次返回全新的错误列表。
	if str(profile_id).strip_edges().is_empty():
		errors.append("波次配置缺少稳定 ID。")
	if wave_count < 2:
		errors.append("自然波次总数至少为 2。")
	var flag_seen: Dictionary = {}
	for number: int in flag_waves:
		if number < 2 or number > wave_count or flag_seen.has(number):
			errors.append("特殊大波编号越界或重复：" + str(number))
		flag_seen[number] = true
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
	for wave_number: int in scheduled_caps: # 每波必须给随机池至少留一个位置。
		if scheduled_caps[wave_number] >= MAX_ZOMBIES_PER_WAVE:
			errors.append("第%d波的预排出怪占满了随机池容量。" % wave_number)
	return errors
