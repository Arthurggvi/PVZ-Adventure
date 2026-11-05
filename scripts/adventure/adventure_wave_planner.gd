## 冒险自然波次计划器：按波段独立抽取物种及等阶，使用原版战力预算，不负责选行或创建实体。
extends RefCounted
class_name AdventureWavePlanner

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

## 进入场景树前写入本次战斗等阶属性；组件 _ready 会使用新最大生命与攻击值。
static func bind_tier(zombie: Zombie000Base, tier_id: StringName) -> void:
	if not AdventureZombieTierBinding.bind(zombie, tier_id):
		push_error("未能应用僵尸冒险等阶：" + str(tier_id))
