## Isolated progression math contract. No scene, global session or save writes.
extends Node

const Tiers = preload("res://scripts/adventure/adventure_zombie_tier_catalog.gd")
const Growth = preload("res://scripts/adventure/adventure_plant_growth_catalog.gd")
## 断言失败时退出的计时器；正常完成后显式停止。
var _watchdog: Timer

func _ready() -> void:
	_watchdog = Timer.new()
	_watchdog.one_shot = true
	_watchdog.ignore_time_scale = true
	_watchdog.timeout.connect(func(): get_tree().quit(1))
	add_child(_watchdog)
	_watchdog.start(6.0)
	_run.call_deferred()

func _run() -> void:
	assert(OS.get_user_data_dir().contains("growth-curves-test"))
	var tiers := [&"base", &"veteran", &"elite", &"tier4", &"tier5"]
	var hp_rates := [1.0, 1.5, 3.0, 5.0, 10.0]
	var bite_rates := [1.0, 1.2, 2.0, 3.0, 5.0]
	assert(Tiers.tier_ids().size() == 5)
	for i in range(tiers.size()):
		var tier: Dictionary = Tiers.get_tier(tiers[i])
		assert(is_equal_approx(float(tier.hp), hp_rates[i]))
		assert(is_equal_approx(float(tier.armor), hp_rates[i]))
		assert(is_equal_approx(float(tier.attack), bite_rates[i]))
		assert(Tiers.scaled(270, float(tier.hp)) == roundi(270.0 * hp_rates[i]))
		assert(Tiers.scaled(370, float(tier.armor)) == roundi(370.0 * hp_rates[i]))
		assert(Tiers.scaled(1100, float(tier.armor)) == roundi(1100.0 * hp_rates[i]))
		assert(Tiers.scaled(100, float(tier.attack)) == roundi(100.0 * bite_rates[i]))
	assert(Tiers.scaled(0, 10.0) == 0)
	assert(Tiers.get_tier(&"unknown").is_empty())
	assert(Growth.modifiers(0).is_empty())
	for star in [1, 3, 6, 10]:
		var mods: Dictionary = Growth.modifiers(star)
		assert(is_equal_approx(1.0 + float(mods.damage.percent), pow(1.20, star)))
		assert(is_equal_approx(1.0 + float(mods.max_health.percent), pow(1.12, star)))
		assert(is_equal_approx(1.0 + float(mods.sun_production_rate.percent),
			1.0 + 0.015 * float(star)))
	assert(roundi(20.0 * (1.0 + float(Growth.modifiers(6).damage.percent))) == 60)
	assert(roundi(1800.0 * (1.0 + float(Growth.modifiers(6).damage.percent))) == 5375)
	assert(roundi(300.0 * (1.0 + float(Growth.modifiers(6).max_health.percent))) == 592)
	assert(is_equal_approx(24.0 / (1.0 + float(Growth.modifiers(10).sun_production_rate.percent)),
		24.0 / 1.15))
	assert(Growth.modifiers(11).is_empty())
	print("GROWTH_CURVES_PASS 5 tiers, HP/armor/bite and stars 0/1/3/6/10")
	_watchdog.stop()
	get_tree().quit(0)
