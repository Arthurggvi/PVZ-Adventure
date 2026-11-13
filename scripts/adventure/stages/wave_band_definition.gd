## 闭区间自然波段；仅描述普通僵尸物种和已定义等阶的相对权重。
extends Resource
class_name WaveBandDefinition

## 波段稳定 ID，不依赖数组下标。
@export var band_id: StringName = &""
## 首波，波次从 1 开始，0 表示尚未配置。
@export var first_wave: int = 0
## 包含在波段内的末波。
@export var last_wave: int = 0
## 随机池的基础战力下限；0 沿用自然波预算，大波和战场倍率仍按规则叠加。
@export var minimum_regular_power: int = 0
## 普通僵尸专用物种池，不使用 Boss 类型字段。
@export var zombie_weights: Dictionary[CharacterRegistry.ZombieType, int] = {}
## 等阶 ID 必须存在于调用方明确提供的已定义目录，零权重也不能引用不存在的等阶。
@export var tier_weights: Dictionary[StringName, int] = {}
## 可选：按物种覆盖等阶权重，键为 ZombieType，值为 {tier_id: 权重}。
## 未列出的物种沿用 [member tier_weights]；用于同一波段内不同物种需要不同等阶比例时。
@export var species_tier_weights: Dictionary = {}

## [param known_tier_ids] 是已定义等阶目录；空目录不会隐式创建基础或高级等阶。
func validate(known_tier_ids: Array[StringName] = []) -> PackedStringArray:
	var errors := PackedStringArray() # 本次独立错误列表，不改动配置。
	if str(band_id).strip_edges().is_empty():
		errors.append("波段缺少稳定 ID。")
	if first_wave < 1 or last_wave < first_wave:
		errors.append("波段[%s]的波次闭区间无效。" % band_id)
	if minimum_regular_power < 0:
		errors.append("波段[%s]的基础战力下限不能为负数。" % band_id)
	errors.append_array(validate_pool(zombie_weights, tier_weights, known_tier_ids))
	errors.append_array(validate_species_tier_weights(zombie_weights, species_tier_weights, known_tier_ids))
	return errors

## 校验 [param zombies] 与 [param tiers]；[param known_tier_ids] 来自实际定义方，不读取单例。
static func validate_pool(zombies: Dictionary[CharacterRegistry.ZombieType, int], tiers: Dictionary[StringName, int], known_tier_ids: Array[StringName]) -> PackedStringArray:
	var errors := PackedStringArray() # 自然波次与 Boss 持续召唤共用同一池契约。
	var has_zombie := false # 至少一个正物种权重。
	for zombie_type: int in zombies: # 只承认普通僵尸枚举中的非空物种。
		if zombie_type == CharacterRegistry.ZombieType.Null or not CharacterRegistry.ZombieType.values().has(zombie_type):
			errors.append("普通僵尸池引用了无效物种：%s。" % zombie_type)
		if zombies[zombie_type] < 0:
			errors.append("普通僵尸权重不能为负数。")
		has_zombie = has_zombie or zombies[zombie_type] > 0
	if not has_zombie:
		errors.append("普通僵尸池为空或没有正权重。")
	errors.append_array(validate_tier_weights(tiers, known_tier_ids))
	return errors

## 校验 [param overrides_by_species] 中每个物种的等阶覆盖；覆盖键必须是同池已启用的物种。
static func validate_species_tier_weights(zombies: Dictionary, overrides_by_species: Dictionary,
		known_tier_ids: Array[StringName]) -> PackedStringArray:
	var errors := PackedStringArray() # 每个覆盖独立校验，避免一个坏条目掩盖其他错误。
	for zombie_type: int in overrides_by_species: # 覆盖只对同池正权重物种生效。
		if not zombies.has(zombie_type) or int(zombies[zombie_type]) <= 0:
			errors.append("物种等阶覆盖引用了未启用的物种：%s。" % zombie_type)
			continue
		var tiers: Variant = overrides_by_species[zombie_type] # 每个物种对应一份等阶权重字典。
		if not tiers is Dictionary:
			errors.append("物种%d的等阶覆盖必须是字典。" % zombie_type)
			continue
		errors.append_array(validate_tier_weights(tiers, known_tier_ids))
	return errors

## 校验 [param tiers] 的等阶 ID 与权重；[param known_tier_ids] 由调用方提供，不读取单例。
static func validate_tier_weights(tiers: Dictionary, known_tier_ids: Array[StringName]) -> PackedStringArray:
	var errors := PackedStringArray() # 不从数值大小、名称或其他字段猜测等阶是否存在。
	var has_tier := false # 至少一个正等阶权重。
	for tier_id: StringName in tiers: # 零权重也不能引用未定义等阶。
		if str(tier_id).strip_edges().is_empty() or not known_tier_ids.has(tier_id):
			errors.append("等阶池引用了未定义的等阶：%s。" % tier_id)
		if int(tiers[tier_id]) < 0:
			errors.append("等阶权重不能为负数。")
		has_tier = has_tier or int(tiers[tier_id]) > 0
	if not has_tier:
		errors.append("等阶池为空或没有正权重。")
	return errors
