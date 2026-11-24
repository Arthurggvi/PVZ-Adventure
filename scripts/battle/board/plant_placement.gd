## 植物放置的离树准备对象；占位与伴生共用构造、资格校验和生命周期提交。
extends RefCounted
class_name PlantPlacement

## 唯一拥有该植物的原点格子。
var cell: PlantCell
## 准备的真实植物实例，提交前由计划拥有。
var plant: Plant000Base
## 物种种植契约与冻结占用范围。
var condition: ResourcePlantCondition
## 请求的注册物种，不受模仿者表现类型影响。
var species: CharacterRegistry.PlantType
## 本次准备的实际种植槽；预检通过后冻结，提交前再确认。
var slot: CharacterRegistry.PlacePlantInCell
## 共享占用的全部地块。
var footprint: Array[PlantCell] = []
## 升级前置的显式消耗声明；读档不消费前置。
var claims: Array[Dictionary] = []
## 区分玩家、关卡和恢复规则。
var origin: PlantCell.PlacementOrigin
## 是否播放正常种植效果。
var play_effect: bool = false
## 模仿者准备期挂载到独立表现槽。
var imitater: bool = false
## 已预检且复制的读档数据，空值表示普通放置。
var saved_state: Dictionary = {}
## 应用永久生命比例前的正常配方上限；重复预检始终从同一基值计算。
var _normal_max_health: int = 0
## 转移实例所有权后不能再次提交。
var committed: bool = false

## 准备 [param target] 的 [param species]，所有参数沿用 PlantCell.create_plant 协议。
## 无副作用构造；失败计划析构时释放尚未入树的植物。
static func prepare(target: PlantCell, species: CharacterRegistry.PlantType,
		is_imitater: bool, effect: bool, material: bool, zombie_mode: bool,
		profile: PlantSpawnProfile, placement_origin: PlantCell.PlacementOrigin,
		use_context: PlantPlacementUseContext = null) -> PlantPlacement:
	if not is_instance_valid(target) or (target.board != null and not target.board.allows_mutation()) \
			or not Global.character_registry.PlantInfo.has(species):
		return null
	if profile != null and not profile.matches_plant_type(int(species)):
		return null
	if placement_origin in [PlantCell.PlacementOrigin.Companion, PlantCell.PlacementOrigin.Revival] \
			and (is_imitater or zombie_mode):
		return null
	var plan := PlantPlacement.new() # 仅持有准备结果，不写入占用字典。
	plan.cell = target
	plan.origin = placement_origin
	plan.species = species
	plan.imitater = is_imitater
	plan.play_effect = effect
	plan.condition = Global.character_registry.get_plant_info(species,
		CharacterRegistry.PlantInfoAttribute.PlantConditionResource)
	if profile != null and plan.condition != null:
		plan.condition = profile.placement_condition(plan.condition)
	if plan.condition == null:
		return null
	plan.slot = plan.condition.place_plant_in_cell
	if placement_origin in [PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.Spawned]:
		plan.slot = plan.condition.placement_slot(target)
	plan.footprint = plan.condition.placement_cells(target)
	if plan.footprint.is_empty() or not plan._valid_geometry():
		return null
	if placement_origin in [PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.Spawned, PlantCell.PlacementOrigin.Companion] \
			and not plan.condition.judge_is_can_plant(target, species, placement_origin == PlantCell.PlacementOrigin.Companion):
		return null
	if placement_origin == PlantCell.PlacementOrigin.Revival \
			and not plan.condition.judge_revival_allowed(target, species):
		return null
	if plan.condition.is_purple_card and placement_origin in [PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.LevelSetup]:
		plan.claims = plan.condition.get_upgrade_claims(target, species)
	if placement_origin != PlantCell.PlacementOrigin.SaveRestore \
			and not plan._placement_is_available():
		return null
	plan.plant = PlantSceneFactory.create(CharacterRegistry.PlantType.P999Imitater if is_imitater else species)
	if plan.plant == null:
		return null
	if is_imitater:
		if not plan.plant is Plant999Imitater:
			return null
		(plan.plant as Plant999Imitater).imitater_plant_type = species
	if plan.slot == CharacterRegistry.PlacePlantInCell.Down \
			and not is_imitater and not plan.plant is Plant000DownBase:
		return null
	plan.plant.init_plant({Plant000Base.E_PInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Plant000Base.E_PInitAttr.PlantCell: target, Plant000Base.E_PInitAttr.IsImitaterMaterial: material,
		Plant000Base.E_PInitAttr.IsZombieMode: zombie_mode})
	if profile != null and not profile.apply(plan.plant, int(species)):
		return null
	plan.plant.plant_spawn_profile = profile
	plan.plant.placement_use_context = use_context
	if placement_origin != PlantCell.PlacementOrigin.SaveRestore and not plan.plant.prepare_placement_action(placement_origin):
		return null
	return plan

## [param data] 通过物种自有离树校验后冻结；先恢复永久上限，不写当前 HP 或触发睡眠回调。
func prepare_saved_state(data: Dictionary) -> bool:
	if plant == null or committed or plant.get_parent() != null or not plant.accepts_save_state(data):
		return false
	var health: HpComponent = plant.get_node_or_null("HpComponent") as HpComponent # 原属性已经全部应用的离树生命组件。
	if health == null or health.max_hp <= 0:
		return false
	if _normal_max_health <= 0:
		_normal_max_health = health.max_hp
	var scale: float = float(data.get("revival_health_scale", 1.0)) # 缺少字段的旧存档保持正常上限。
	var maximum: int = maxi(1, roundi(float(_normal_max_health) * scale)) # 重复预检不在半血上限上再次乘半。
	if origin == PlantCell.PlacementOrigin.SaveRestore and scale < 1.0 and data.has("revival_max_health"):
		maximum = int(data["revival_max_health"]) # 原版恢复不携带冒险配方，保存的实际上限保留其既有星级修饰。
	if scale < 1.0 and int(data["curr_hp"]) > maximum:
		return false
	if health.max_hp != maximum:
		var stages: HpStageChangeComponent = plant.get_node_or_null("HpStageChangeComponent") as HpStageChangeComponent # 破损阈值也按上限重标定。
		if stages != null:
			stages.set_spawn_max_health(maximum)
		else:
			health.set_spawn_max_health(maximum)
	plant.revival_health_scale = scale
	saved_state = data.duplicate(true)
	return true

## 提交前复核占用与前置身份；期间不得跨帧。
func can_commit() -> bool:
	if committed or not is_instance_valid(plant) or plant.get_parent() != null \
			or not _valid_geometry() or condition.placement_cells(cell) != footprint:
		return false
	if origin in [PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.Spawned] \
			and condition.placement_slot(cell) != slot:
		return false
	if origin in [PlantCell.PlacementOrigin.Player, PlantCell.PlacementOrigin.Spawned, PlantCell.PlacementOrigin.Companion] \
			and not condition.judge_is_can_plant(cell, species, origin == PlantCell.PlacementOrigin.Companion):
		return false
	if origin == PlantCell.PlacementOrigin.Revival and not condition.judge_revival_allowed(cell, species):
		return false
	if not claims.is_empty():
		var current: Array[Dictionary] = condition.get_upgrade_claims(cell,
			species) # 防止准备后前置被替换。
		if current != claims:
			return false
	if not _placement_is_available():
		return false
	return origin == PlantCell.PlacementOrigin.SaveRestore or plant.prepare_placement_action(origin)

## 普通植物独占种植位；伴生植物只保留同格同物种的唯一实例。
func _placement_is_available() -> bool:
	if origin == PlantCell.PlacementOrigin.Companion:
		return footprint.size() == 1 and cell.can_host_companion(int(species))
	return cell._placement_is_available(slot, footprint, claims)

## 检查地块身份、去重与平台边界，不依赖临时矩阵。
func _valid_geometry() -> bool:
	if not is_instance_valid(cell) or cell.is_queued_for_deletion():
		return false
	var seen: Array[PlantCell] = [] # 一个植物不能重复声明同一地块。
	for target: PlantCell in footprint: # 只接受当前空间中的实际节点。
		if not is_instance_valid(target) or target.is_queued_for_deletion() or target.board != cell.board \
				or target.has_planting_block() or seen.has(target):
			return false
		if cell.board_definition != null and (target.board_definition == null \
				or target.board_definition.surface_id != cell.board_definition.surface_id):
			return false
		seen.append(target)
	return seen.has(cell)

## 最终复核后交给格子提交；[param notify] 允许账本先消费令牌再通知，失败不扣费或消耗前置。
func commit(notify: bool = true) -> Plant000Base:
	if (cell.board != null and not cell.board.allows_mutation()) or not can_commit():
		return null
	return cell.commit_prepared_plant(self, notify)

## 放弃计划只释放未提交的离树实体。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not committed and is_instance_valid(plant) and plant.get_parent() == null:
		plant.free()
