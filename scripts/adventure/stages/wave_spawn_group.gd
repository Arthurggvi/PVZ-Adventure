## 某个自然波的预排出怪组，先于该波随机池生成，并参与本波清场和血量统计。
extends Resource
class_name WaveSpawnGroup

## 起始自然波编号，从 1 开始。
@export var wave: int = 1
## 末波（含）；0 表示仅在 [member wave] 生成。
@export var last_wave: int = 0
## 本组均匀抽取的数量闭区间；下限为零时允许本波不出现该组。
@export var count_range: Vector2i = Vector2i.ONE
## 固定出怪行，从 1 开始；0 使用正常的随机选行。
@export var row: int = 0
## 每只预排僵尸的物种权重。
@export var zombie_weights: Dictionary[CharacterRegistry.ZombieType, int] = {}
## 每只预排僵尸的等阶权重。
@export var tier_weights: Dictionary[StringName, int] = {}

## 返回预排组覆盖的最后一波。
func end_wave() -> int:
	return wave if last_wave == 0 else last_wave

## 按 [param wave_count] 和 [param known_tier_ids] 校验本组；实际行地形由关卡入口校验。
func validate(wave_count: int, known_tier_ids: Array[StringName]) -> PackedStringArray:
	var errors: PackedStringArray = WaveBandDefinition.validate_pool(zombie_weights, tier_weights, known_tier_ids) # 与随机波段共用权重契约。
	if wave < 1 or end_wave() < wave or end_wave() > wave_count:
		errors.append("预排出怪波次范围越界：%d–%d。" % [wave, end_wave()])
	if count_range.x < 0 or count_range.y < 1 or count_range.x > count_range.y:
		errors.append("第%d波的预排出怪数量范围无效。" % wave)
	if row < 0:
		errors.append("第%d波的预排出怪行号无效。" % wave)
	return errors
