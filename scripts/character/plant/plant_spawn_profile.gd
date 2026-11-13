## An immutable battle spawn recipe, created by the owning game mode.
## Generic planting and transformations consume it without inspecting research.
extends RefCounted
class_name PlantSpawnProfile

var _snapshot: Dictionary = {}
var _modifier: PlantSpawnModifier

static func create(card_snapshot: Dictionary, modifier: PlantSpawnModifier) -> PlantSpawnProfile:
	if modifier == null or not _has_plant_identity(card_snapshot):
		return null
	return PlantSpawnProfile.new(card_snapshot, modifier)

static func _has_plant_identity(card_snapshot: Dictionary) -> bool:
	var plant_id: Variant = card_snapshot.get("plant_type", null)
	return (
		not card_snapshot.is_empty()
		and (typeof(plant_id) == TYPE_INT or typeof(plant_id) == TYPE_FLOAT)
		and int(plant_id) > 0
		and float(plant_id) == float(int(plant_id))
	)

func _init(card_snapshot: Dictionary, modifier: PlantSpawnModifier) -> void:
	if modifier == null or not _has_plant_identity(card_snapshot):
		push_error("PlantSpawnProfile requires a valid species and modifier")
		return
	_snapshot = card_snapshot.duplicate(true)
	_modifier = modifier

func is_valid_profile() -> bool:
	return _modifier != null and _has_plant_identity(_snapshot)

func matches_plant_type(plant_type: int) -> bool:
	return is_valid_profile() and int(_snapshot["plant_type"]) == plant_type

func snapshot() -> Dictionary:
	return _snapshot.duplicate(true) if is_valid_profile() else {}

## 返回快照已完成的最高转职次数。零表示原始外观，阶级显示在此值上加一。
func promotion_tier() -> int:
	# 从最高转职开始找，取已选分支所在的阶数，与星级无关。
	for rank: int in range(4, 0, -1):
		if not str(_snapshot.get("promotion_%d" % rank, "")).is_empty():
			return rank
	return 0

func card_stats(base_sun_cost: int, base_cooldown: float) -> Dictionary:
	if not is_valid_profile():
		return {}
	return _modifier.card_stats(_snapshot.duplicate(true), base_sun_cost, base_cooldown)

## 返回当前冻结卡片消耗的选卡名额；无有效配方时按普通卡处理。
func selection_slot_cost() -> int:
	return maxi(0, _modifier.selection_slot_cost(_snapshot.duplicate(true))) if is_valid_profile() else 1

## 为预览和种植事务投影 [param base_condition]；修改器不得改写共享条件资源。
func placement_condition(base_condition: ResourcePlantCondition) -> ResourcePlantCondition:
	return _modifier.placement_condition(_snapshot.duplicate(true), base_condition) if is_valid_profile() else base_condition

## 将玩家已成功种植的 [param cell] 交给所属模式；仅手持卡确认入口调用一次。
## 技能生成、转化、预种植和读档不会调用此通知，也不会再次扣费。
func player_placement_committed(cell: PlantCell) -> void:
	if is_valid_profile() and is_instance_valid(cell):
		_modifier.player_placement_committed(cell, self)

func apply(plant: Plant000Base, plant_type: int) -> bool:
	if plant == null or not matches_plant_type(plant_type):
		return false
	if plant.spawn_species_id() != plant_type:
		return false
	if plant.spawn_attributes_applied:
		return false
	if not _modifier.apply(plant, _snapshot.duplicate(true)):
		return false
	plant.spawn_attributes_applied = true
	return true
