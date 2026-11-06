## 冒险自然波次计划器：按波段独立抽取物种及等阶，使用原版战力预算，不负责选行或创建实体。
extends RefCounted
class_name AdventureWavePlanner

## 冒险阶段唯一战力预算算法；运行时出怪与入场校验共用这一数值定义。
static func power_budget(wave_index: int, is_big_wave: bool, multiplier: int) -> int:
	var base_power: int = wave_index / 3 + 1
	return (int(base_power * 2.5) if is_big_wave else base_power) * multiplier

## 检查整阶段每波必有可负担敌人，且任何设置正权重的物种/等阶组合至少在所处
## 波段的一波具有实际出场机会；避免配置看似有效而高等阶始终被预算过滤。
static func validate_affordability(profile: WaveProfile, multiplier: int,
		threat: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if profile == null or multiplier <= 0:
		errors.append("阶段战力预算参数无效。")
		return errors
	for band: WaveBandDefinition in profile.bands:
		if band == null:
			continue
		var reachable: Dictionary = {}
		var weighted: Array[String] = []
		for zombie_type: int in band.zombie_weights:
			if band.zombie_weights[zombie_type] <= 0:
				continue
			for tier_id: StringName in band.tier_weights:
				if band.tier_weights[tier_id] <= 0 or not threat.has(tier_id):
					continue
				var key: String = "%d/%s" % [zombie_type, tier_id]
				weighted.append(key)
				reachable[key] = false
		for wave_number: int in range(band.first_wave, mini(band.last_wave, profile.wave_count) + 1):
			var final_or_flag: bool = profile.is_flag_wave(wave_number) or wave_number == profile.wave_count
			var budget: int = power_budget(wave_number - 1, final_or_flag, multiplier)
			var any_affordable := false
			for zombie_type: int in band.zombie_weights:
				if band.zombie_weights[zombie_type] <= 0:
					continue
				for tier_id: StringName in band.tier_weights:
					if band.tier_weights[tier_id] <= 0 or not threat.has(tier_id):
						continue
					var base_cost: int = int(CharacterRegistry.ZombieSpawnPower.get(zombie_type, 0))
					var cost: int = maxi(1, ceili(float(base_cost) * float(threat[tier_id])))
					if base_cost > 0 and cost <= budget:
						reachable["%d/%s" % [zombie_type, tier_id]] = true
						any_affordable = true
			if not any_affordable:
				errors.append("第%d波没有可负担敌人。" % wave_number)
		for key: String in weighted:
			if not reachable[key]:
				errors.append("波段%s的物种/等阶组合%s永远不满足战力预算。" % [band.band_id, key])
	return errors

## 所有波次配置使用 1-based 编号；原版 ZombieWaveManager 是 0-based。
static func find_band(profile: WaveProfile, wave_number: int) -> WaveBandDefinition:
	if profile == null or wave_number < 1 or wave_number > profile.wave_count:
		return null
	for band: WaveBandDefinition in profile.bands:
		if band != null and wave_number >= band.first_wave and wave_number <= band.last_wave:
			return band
	return null

## 威胁倍率明确由调用方的已实装等阶目录提供，不推断未知等阶的战力。
static func build_plan(profile: WaveProfile, wave_number: int, power_budget: int,
		max_zombies: int, tier_threat: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var band: WaveBandDefinition = find_band(profile, wave_number)
	if band == null or rng == null or power_budget < 1 or max_zombies < 1:
		return plan
	var candidates: Array[Dictionary] = []
	for zombie_type: int in band.zombie_weights:
		var species_weight: int = band.zombie_weights[zombie_type]
		var base_power: int = int(CharacterRegistry.ZombieSpawnPower.get(zombie_type, 0))
		if species_weight <= 0 or base_power <= 0:
			continue
		for tier_id: StringName in band.tier_weights:
			var tier_weight: int = band.tier_weights[tier_id]
			if tier_weight <= 0 or not tier_threat.has(tier_id):
				continue
			var factor: float = float(tier_threat[tier_id])
			if not is_finite(factor) or factor <= 0:
				continue
			var cost: int = maxi(1, ceili(float(base_power) * factor))
			candidates.append({"zombie_type": zombie_type, "tier_id": tier_id,
				"cost": cost, "weight": float(species_weight) * float(tier_weight)})
	var used_power := 0
	while plan.size() < max_zombies:
		var weight_total := 0.0
		var remaining: int = power_budget - used_power
		for candidate: Dictionary in candidates:
			if candidate.cost <= remaining:
				weight_total += candidate.weight
		if weight_total <= 0:
			break
		var selected: float = rng.randf() * weight_total
		var choice: Dictionary = {}
		for candidate: Dictionary in candidates:
			if candidate.cost > remaining:
				continue
			choice = candidate
			selected -= candidate.weight
			if selected <= 0:
				break
		if choice.is_empty():
			break
		plan.append({"zombie_type": choice.zombie_type,
			"tier_id": choice.tier_id, "threat_cost": choice.cost})
		used_power += int(choice.cost)
	return plan
