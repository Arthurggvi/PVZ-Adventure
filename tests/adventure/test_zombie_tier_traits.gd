extends Node
## Focused integration: cone armor-loss event, timed speed composition and 3x3 query.
const CONE: PackedScene = preload("res://scenes/character/zombie/zombie_003_cone.tscn")
const FACTOR: int = Character000Base.E_Influence_Speed_Factor.AdventureTierBoost
var _failed := false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_require(AdventureZombieTierTraits.for_spawn(
		CharacterRegistry.ZombieType.Z001Norm, &"tier5").is_empty(), "normal zombie has no trait")
	_require(AdventureZombieTierTraits.for_spawn(
		CharacterRegistry.ZombieType.Z003Cone, &"base").is_empty(), "cone tier1 no trait")
	# spec 是当前等阶脱盔后的速度倍率、持续秒数和友军影响范围。
	for spec in [
		{"tier": &"veteran", "multiplier": 1.3, "duration": 0.5, "radius": 0},
		{"tier": &"elite", "multiplier": 1.6, "duration": 0.5, "radius": 0},
		{"tier": &"tier4", "multiplier": 2.0, "duration": 0.8, "radius": 0},
		{"tier": &"tier5", "multiplier": 2.0, "duration": 0.8, "radius": 1},
	]:
		var tier: StringName = spec["tier"]
		var configured: Array[Dictionary] = AdventureZombieTierTraits.for_spawn(
			CharacterRegistry.ZombieType.Z003Cone, tier)
		_require(configured.size() == 1 and int(configured[0]["radius_cells"]) == spec["radius"],
			"cone rules " + str(tier))
		var zombie: Zombie000Base = CONE.instantiate() as Zombie000Base
		zombie.character_init_type = Character000Base.E_CharacterInitType.IsShow
		_require(AdventureZombieTierBinding.new(tier).apply(zombie), "bind cone " + str(tier))
		add_child(zombie)
		await get_tree().process_frame
		var hp: HpComponentZombie = zombie.get_node("HpComponent") as HpComponentZombie
		_require(hp.max_hp_armor1 > 0, "cone armor exists " + str(tier))
		hp.curr_hp_armor1 = 0
		await get_tree().process_frame
		await get_tree().process_frame
		_require(is_equal_approx(float(zombie.influence_speed_factors.get(FACTOR, 1.0)),
			float(spec["multiplier"])), "cone armor event boost " + str(tier))
		var boost: AdventureZombieTimedSpeedBoost = zombie.get_node_or_null(
			"AdventureTimedSpeedBoost") as AdventureZombieTimedSpeedBoost
		_require(boost != null, "boost component attached " + str(tier))
		if boost != null:
			boost.set_process(false)
			boost._process(float(spec["duration"]) * 0.4)
			_require(is_equal_approx(float(zombie.influence_speed_factors[FACTOR]),
				float(spec["multiplier"])), "duration retained " + str(tier))
			boost._process(float(spec["duration"]) * 1.1)
			_require(is_equal_approx(float(zombie.influence_speed_factors[FACTOR]), 1.0),
				"expires to neutral " + str(tier))
		zombie.queue_free()
		await get_tree().process_frame

	var target := CONE.instantiate() as Zombie000Base
	target.character_init_type = Character000Base.E_CharacterInitType.IsShow
	add_child(target)
	await get_tree().process_frame
	AdventureZombieTimedSpeedBoost.apply_to(target, 1.2, 1.0)
	AdventureZombieTimedSpeedBoost.apply_to(target, 1.5, 0.4)
	var merged := target.get_node("AdventureTimedSpeedBoost") as AdventureZombieTimedSpeedBoost
	_require(is_equal_approx(float(target.influence_speed_factors[FACTOR]), 1.5),
		"boosts choose strongest")
	merged.set_process(false)
	merged._process(0.5)
	_require(is_equal_approx(float(target.influence_speed_factors[FACTOR]), 1.2),
		"weaker active boost remains")
	merged._process(0.51)
	_require(is_equal_approx(float(target.influence_speed_factors[FACTOR]), 1.0),
		"all boosts expire")
	target.queue_free()
	await get_tree().process_frame

	var source := Zombie000Base.new()
	source.lane = 2
	source.position = Vector2(400, 0)
	var nearby := Zombie000Base.new()
	nearby.lane = 2
	nearby.position = Vector2(480, 0)
	var diagonal := Zombie000Base.new()
	diagonal.lane = 3
	diagonal.position = Vector2(320, 0)
	var too_far := Zombie000Base.new()
	too_far.lane = 4
	too_far.position = Vector2(410, 0)
	var charmed := Zombie000Base.new()
	charmed.lane = 2
	charmed.position = Vector2(430, 0)
	charmed.is_hypno = true
	var pool: Array[Zombie000Base] = [source, nearby, diagonal, too_far, charmed]
	var around: Array[Zombie000Base] = AdventureZombieTierNeighbors.allied_in_range(
		source, pool, 80.0, 1)
	_require(around.size() == 2 and around.has(nearby) and around.has(diagonal),
		"3x3 neighbor query includes row and diagonal only")
	for candidate: Zombie000Base in pool:
		candidate.free()

	if not _failed:
		print("ZOMBIE_TIER_TRAITS_PASS")
	get_tree().quit(1 if _failed else 0)

func _require(condition: bool, description: String) -> void:
	if not condition:
		_failed = true
		push_error("ZOMBIE_TIER_TRAITS_FAIL: " + description)
