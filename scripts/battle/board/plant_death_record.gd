## 同一次真实死亡的不可变快照；多格植物的所有格子共用本令牌，最多成功复生一次。
extends RefCounted
class_name PlantDeathRecord

## 原物种身份，模仿者以被模仿物种复生。
var species: int
## 原卡牌的冻结配方；不会重新读取库存、星级或转职分支。
var profile: PlantSpawnProfile
## 原战场和冒险阶段，防止旧场景或普通/噩梦切换后沿用尸体。
var game_ref: WeakRef
## 死亡时所属空间，拓扑重建后不能复用原记录。
var board: BoardRuntime
## 冒险阶段资源身份，普通关为 null。
var phase: StagePhaseDefinition
## 唯一出生原点；多格的任一覆盖格都可引用同一个来源。
var origin_ref: WeakRef
## 冻结的真实占用范围，弱引用不延长地块生命周期。
var footprint_refs: Array[WeakRef] = []
## 已成功消费或正在同步提交的标志，阻止回调重入。
var consumed: bool = false
## 同一记录的提交锁；失败会释放而不会丢失记录。
var committing: bool = false
## 仅保存永久属性与物种阶段，不保留死亡尸体或临时光环引用。
var _state: Dictionary = {}

## 从 [param plant] 和 [param cells] 捕获死亡前状态；[param game] 是调用方已核验的正式战场。
func capture(plant: Plant000Base, cells: Array[PlantCell], game: MainGameManager) -> void:
	species = plant.spawn_species_id()
	profile = plant.plant_spawn_profile
	game_ref = weakref(game)
	board = plant.plant_cell.board
	phase = AdventureSession.get_active_phase(game.game_para)
	origin_ref = weakref(plant.plant_cell)
	for cell: PlantCell in cells: # 同一记录在全部覆盖格共享，不复制成多具尸体。
		footprint_refs.append(weakref(cell))
	_state = plant.gat_save_game_data_plant().duplicate(true)
	_state["plant_type"] = species
	if plant is Plant999Imitater:
		_state["is_imitater_material"] = true

## 状态副本供离树恢复预检修改血量，不暴露原快照。
func state() -> Dictionary:
	return _state.duplicate(true)

## 返回完整原占用；任一地块失效即拒绝缩小多格植物。
func footprint() -> Array[PlantCell]:
	var cells: Array[PlantCell] = [] # 无效时返回类型明确的空结果。
	for reference: WeakRef in footprint_refs:
		var cell: PlantCell = reference.get_ref() as PlantCell # 弱引用已失效时为 null。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			return []
		cells.append(cell)
	return cells
