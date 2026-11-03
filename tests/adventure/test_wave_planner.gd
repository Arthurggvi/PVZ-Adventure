## 纯计划器验收：两波段、物种权重、等阶配比、战力预算与随机可复现。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile := WaveProfile.new()
	profile.profile_id = &"test_waves"
	profile.wave_count = 10
	var first := WaveBandDefinition.new()
	first.band_id = &"first"
	first.first_wave = 1
	first.last_wave = 3
	first.zombie_weights[CharacterRegistry.ZombieType.Z001Norm] = 5
	first.tier_weights[&"base"] = 1
	first.tier_weights[&"veteran"] = 2
	var second := WaveBandDefinition.new()
	second.band_id = &"second"
	second.first_wave = 4
	second.last_wave = 10
	second.zombie_weights[CharacterRegistry.ZombieType.Z003Cone] = 1
	second.tier_weights[&"base"] = 1
	profile.bands = [first, second]
	var known: Array[StringName] = [&"base", &"veteran"]
	assert(profile.validate(known).is_empty())
	var factors := {&"base": 1.0, &"veteran": 2.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1922
	var seen_veteran := false
	for _try: int in range(20):
		var plan: Array[Dictionary] = AdventureWavePlanner.build_plan(profile, 1, 20, 20, factors, rng)
		assert(not plan.is_empty())
		var used := 0
		for entry: Dictionary in plan:
			assert(entry.zombie_type == CharacterRegistry.ZombieType.Z001Norm)
			assert(entry.tier_id in known)
			if entry.tier_id == &"veteran":
				seen_veteran = true
			used += int(entry.threat_cost)
		assert(used <= 20 and plan.size() <= 20)
	assert(seen_veteran)
	var final_plan: Array[Dictionary] = AdventureWavePlanner.build_plan(profile, 10, 50, 20, factors, rng)
	assert(not final_plan.is_empty())
	for entry: Dictionary in final_plan:
		assert(entry.zombie_type == CharacterRegistry.ZombieType.Z003Cone)
		assert(entry.tier_id == &"base")
	assert(AdventureWavePlanner.find_band(profile, 3) == first)
	assert(AdventureWavePlanner.find_band(profile, 4) == second)
	assert(AdventureWavePlanner.build_plan(profile, 0, 20, 20, factors, rng).is_empty())
	assert(AdventureWavePlanner.build_plan(profile, 11, 20, 20, factors, rng).is_empty())
	assert(AdventureWavePlanner.build_plan(profile, 1, 0, 20, factors, rng).is_empty())
	assert(AdventureWavePlanner.build_plan(profile, 1, 20, 0, factors, rng).is_empty())
	assert(AdventureWavePlanner.build_plan(profile, 1, 20, 20, {&"unknown": 1.0}, rng).is_empty())
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 91
	b.seed = 91
	assert(AdventureWavePlanner.build_plan(profile, 1, 14, 15, factors, a) ==
		AdventureWavePlanner.build_plan(profile, 1, 14, 15, factors, b))
	print("PASS: multi-band weighted species/tier wave planning, budgets and RNG")
	get_tree().quit(0)
