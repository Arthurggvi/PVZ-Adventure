## Periodic graves and banner-wave behavior, owned by a single phase definition.
extends Resource
class_name GravestoneWaveRules

@export var regular_interval: int = 0
@export var regular_count := Vector2i.ZERO
@export var flag_count := Vector2i.ZERO
@export var flag_summons_one_per_grave := false
@export var flag_zombie_delay_seconds := 1.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if regular_interval < 0 or (regular_interval == 0 and regular_count != Vector2i.ZERO):
		errors.append("墓碑周期与数量必须一起配置")
	for counts: Vector2i in [regular_count, flag_count]:
		if counts.x < 0 or counts.y < counts.x:
			errors.append("墓碑生成范围非法")
	if flag_zombie_delay_seconds < 0.0 or not is_finite(flag_zombie_delay_seconds):
		errors.append("墓碑出怪延迟非法")
	return errors

## Every third wave and flag additions are additive if both apply.
func plan(wave_number: int, is_flag: bool, rng: RandomNumberGenerator) -> Dictionary:
	if wave_number < 1:
		return {"count": 0, "summon": false}
	var count := 0
	if regular_interval > 0 and wave_number % regular_interval == 0:
		count += rng.randi_range(regular_count.x, regular_count.y)
	if is_flag:
		count += rng.randi_range(flag_count.x, flag_count.y)
	return {"count": count, "summon": is_flag and flag_summons_one_per_grave}
