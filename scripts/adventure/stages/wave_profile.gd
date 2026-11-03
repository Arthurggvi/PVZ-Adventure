## 阶段的自然波次定义；波段使用闭区间，拒绝越界、重复 ID 和重叠。
extends Resource
class_name WaveProfile

## 波次配置稳定 ID。
@export var profile_id: StringName = &""
## 阶段自然波次总数，必须显式配置为正整数。
@export var wave_count: int = 0
## 可编辑的波段资源列表，不在校验期间排序或改写。
@export var bands: Array[WaveBandDefinition] = []

## [param known_tier_ids] 为已实现等阶的显式目录；本类不加载任何配置或场景。
func validate(known_tier_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 每次返回全新的错误列表。
	if str(profile_id).strip_edges().is_empty():
		errors.append("波次配置缺少稳定 ID。")
	if wave_count < 1:
		errors.append("自然波次总数必须为正整数。")
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
	return errors
