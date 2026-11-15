## 生成冒险自然波的预排组和随机池结果；只记录指定行，不创建实体。
extends RefCounted
class_name AdventureWavePlanner

## 计算零起始 [param wave_index] 的预算；[param minimum_regular_power] 为大波加成和战场倍率应用前的下限。
## [param is_big_wave] 加成先取整，再乘战场 [param multiplier]。
static func power_budget(wave_index: int, is_big_wave: bool, multiplier: int,
		minimum_regular_power: int = 0) -> int:
	var base_power: int = maxi(floori(float(wave_index) / 3.0) + 1, minimum_regular_power) # 自然增长与波段下限取较大者。
	return (int(base_power * 2.5) if is_big_wave else base_power) * multiplier

## 计算 [param profile] 第 [param wave_number] 波的随机池预算，按战场 [param multiplier] 缩放。
## 无波段返回零；入场校验与战场共用该入口。
static func wave_budget(profile: WaveProfile, wave_number: int, multiplier: int) -> int:
	var band: WaveBandDefinition = find_band(profile, wave_number) # 预算下限由对应的波段提供。
	if band == null:
		return 0
	var is_big_wave: bool = profile.is_flag_wave(wave_number) or wave_number == profile.wave_count # 末波总是大波。
	return power_budget(wave_number - 1, is_big_wave, multiplier, band.minimum_regular_power)

## 检查整阶段每波必有可负担敌人，且任何设置正权重的物种/等阶组合至少在所处
## 波段的一波具有实际出场机会；避免配置看似有效而高等阶始终被预算过滤。
static func validate_affordability(profile: WaveProfile, multiplier: int,
		threat: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray() # 同时报告随机池和预排组中的无效候选。
	if profile == null or multiplier <= 0:
		errors.append("阶段战力预算参数无效。")
		return errors
	for band: WaveBandDefinition in profile.bands: # 同一波段共用物种和等阶。
		if band == null:
			continue
		var candidates: Array[Dictionary] = _build_candidates(band.zombie_weights, band.tier_weights, threat,
			band.species_tier_weights) # 与实际抽样共用战力计算。
		var lowest_cost: int = 0 # 零表示还没有有效候选。
		for candidate: Dictionary in candidates: # 找到能够填充每一波的最便宜组合。
			lowest_cost = candidate.cost if lowest_cost == 0 else mini(lowest_cost, candidate.cost)
		var highest_budget: int = 0 # 任何组合至少应在波段的最大预算下可用。
		for wave_number: int in range(band.first_wave, mini(band.last_wave, profile.wave_count) + 1): # 遍历本波段合法波次。
			var budget: int = wave_budget(profile, wave_number, multiplier) # 本波真正分给随机池的预算。
			highest_budget = maxi(highest_budget, budget)
			if lowest_cost == 0 or lowest_cost > budget:
				errors.append("第%d波没有可负担敌人。" % wave_number)
		for candidate: Dictionary in candidates: # 组合不能因为预算过低而永久失效。
			if candidate.cost > highest_budget:
				errors.append("波段%s的物种/等阶组合%d/%s永远不满足战力预算。" % [
					band.band_id, candidate.zombie_type, candidate.tier_id])
		errors.append_array(_validate_spawn_power(band.zombie_weights))
	for group: WaveSpawnGroup in profile.scheduled_spawns: # 预排组不消耗随机池预算，但必须有可生成的组合。
		if group != null:
			errors.append_array(_validate_spawn_power(group.zombie_weights))
			if _build_candidates(group.zombie_weights, group.tier_weights, threat).is_empty():
				errors.append("第%d波的预排出怪没有可用的物种和等阶。" % group.wave)
	return errors

## [param species_weights] 中的正权重物种必须在战力目录里有可用定义。
static func _validate_spawn_power(species_weights: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray() # 单个池的未注册战力错误。
	for zombie_type: int in species_weights: # 零权重的物种不会被抽取。
		if species_weights[zombie_type] > 0 and CharacterRegistry.ZombieSpawnPower.get(zombie_type, 0) <= 0:
			errors.append("物种%d没有有效的生成战力。" % zombie_type)
	return errors

## 所有波次配置使用 1-based 编号；原版 ZombieWaveManager 是 0-based。
static func find_band(profile: WaveProfile, wave_number: int) -> WaveBandDefinition:
	if profile == null or wave_number < 1 or wave_number > profile.wave_count:
		return null
	for band: WaveBandDefinition in profile.bands:
		if band != null and wave_number >= band.first_wave and wave_number <= band.last_wave:
			return band
	return null

## 先计划 [param profile] 第 [param wave_number] 波的预排组，再用 [param power_budget] 填充随机池。
## [param max_zombies] 限制两部分总数；[param tier_threat] 提供等阶战力，[param rng] 驱动数量和组合抽样。
static func build_plan(profile: WaveProfile, wave_number: int, wave_power_limit: int,
		max_zombies: int, tier_threat: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var plan: Array[Dictionary] = [] # 顺序即波次实例化顺序。
	var band: WaveBandDefinition = find_band(profile, wave_number) # 本波的随机池。
	if band == null or rng == null or wave_power_limit < 1 or max_zombies < 1:
		return plan
	for group: WaveSpawnGroup in profile.scheduled_spawns: # 预排组可以覆盖一个波段。
		if group == null or wave_number < group.wave or wave_number > group.end_wave():
			continue
		var scheduled_candidates: Array[Dictionary] = _build_candidates(group.zombie_weights, group.tier_weights, tier_threat) # 预排组独立于随机池。
		var count: int = rng.randi_range(group.count_range.x, group.count_range.y) # 本组实例数量。
		if scheduled_candidates.is_empty() or plan.size() + count > max_zombies:
			return []
		for _index: int in range(count): # 每个名额分别抽取物种与等阶。
			var choice: Dictionary = _pick_candidate(scheduled_candidates, rng) # 预排组无需竞争随机池预算。
			plan.append({"zombie_type": choice.zombie_type, "tier_id": choice.tier_id,
				"threat_cost": choice.cost, "row": group.row})
	var candidates: Array[Dictionary] = _build_candidates(band.zombie_weights, band.tier_weights, tier_threat,
		band.species_tier_weights) # 随机池组合。
	var remaining: int = wave_power_limit # 预排组只占用数量容量。
	while plan.size() < max_zombies:
		var choice: Dictionary = _pick_candidate(candidates, rng, remaining) # 在剩余预算内抽取。
		if choice.is_empty():
			break
		plan.append({"zombie_type": choice.zombie_type, "tier_id": choice.tier_id, "threat_cost": choice.cost})
		remaining -= int(choice.cost)
	return plan

## 从 [param species_weights] 与 [param tier_weights] 构造组合，[param tier_threat] 为等阶战力倍率。
## [param species_tier_weights] 可按物种覆盖等阶权重；未列出的物种沿用 [param tier_weights]。
static func _build_candidates(species_weights: Dictionary, tier_weights: Dictionary,
		tier_threat: Dictionary, species_tier_weights: Dictionary = {}) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = [] # 仅包含有正权重和合法战力的组合。
	for zombie_type: int in species_weights: # 遍历待加入的物种。
		var species_weight: int = species_weights[zombie_type] # 独立物种权重。
		var base_power: int = int(CharacterRegistry.ZombieSpawnPower.get(zombie_type, 0)) # 未注册时不生成。
		if species_weight <= 0 or base_power <= 0:
			continue
		var species_tiers: Dictionary = tier_weights # 默认与同池其他物种共享等阶权重。
		if species_tier_weights.has(zombie_type): # 单物种覆盖用于同波段内不同 1/2 阶比例。
			var override: Variant = species_tier_weights[zombie_type]
			if override is Dictionary:
				species_tiers = override
		for tier_id: StringName in species_tiers: # 为该物种枚举启用的等阶。
			var tier_weight: int = int(species_tiers[tier_id]) # 独立等阶权重。
			if tier_weight <= 0 or not tier_threat.has(tier_id):
				continue
			var factor: float = float(tier_threat[tier_id]) # 此等阶的预算倍率。
			if not is_finite(factor) or factor <= 0:
				continue
			var cost: int = maxi(1, ceili(float(base_power) * factor)) # 向上取整为本次出怪战力。
			candidates.append({"zombie_type": zombie_type, "tier_id": tier_id,
				"cost": cost, "weight": float(species_weight) * float(tier_weight)})
	return candidates

## 用 [param rng] 按权重抽取 [param candidates]；[param budget] 为负时不限制战力，无候选返回空字典。
static func _pick_candidate(candidates: Array[Dictionary], rng: RandomNumberGenerator,
		budget: int = -1) -> Dictionary:
	var weight_total := 0.0 # 只累加本次可抽组合的权重。
	for candidate: Dictionary in candidates: # 统计抽样区间。
		if budget < 0 or candidate.cost <= budget:
			weight_total += candidate.weight
	if weight_total <= 0:
		return {}
	var selected: float = rng.randf() * weight_total # 从累计权重中选择。
	var choice: Dictionary = {} # 浮点末位的兜底候选。
	for candidate: Dictionary in candidates: # 按候选顺序累计到抽样点。
		if budget >= 0 and candidate.cost > budget:
			continue
		choice = candidate
		selected -= candidate.weight
		if selected <= 0:
			break
	return choice
