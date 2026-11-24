## 没入福音的独立承伤实体。倒计时结束或锁定植株成功换格时，白柱立即成熟。
## 受击框朝前覆盖同格弹口，投手仍通过原生受击组件定位落点。
extends EnemyStructureBase

## 白柱成熟时发出。[param pillar] 是自然到期或由植株换格触发的设施。
signal expired(pillar: EnemyStructureBase)

## 柱体从生成到成熟的时间，单位为战斗秒。
const DURATION := 12.0
## 从左侧起受保护的列数。棋盘内部列索引从零开始。
const PROTECTED_COLUMNS := 2

## 所属战斗，用于确认锁定对象仍在同一棋盘。
var _game: MainGameManager
## 白柱锁定的单一植物实例，后续补种不会取得同一标记。
var _marked_plant: Plant000Base
## 白柱生成时的主格。格子布局移动时保留同一格子身份。
var _locked_cell: PlantCell
## 已经过的战斗秒数，最多计至成熟。
var _elapsed: float = 0.0
## 以初始格距为白柱和湮灭演出的共同缩放单位。
var visual_span: float
## 距成熟的战斗秒数，成熟后固定为零。
var remaining_seconds: float:
	get:
		return DURATION - _elapsed
## 从生成到成熟的演出进度，取值为 0 至 1。
var progress_ratio: float:
	get:
		return _elapsed / DURATION

## 设施沿用原有 4000 生命和承伤，只通过柱身反馈进度。
func ready_norm() -> void:
	super.ready_norm()
	hp_component.is_can_look_hp = false
	hp_component.hide()
	if _game != null:
		_game.board.plant_relocated.connect(_on_plant_relocated)

## [param plant] 未蛰伏且主格和实际占格均在保护区外时，允许没入福音锁定。
static func is_target_allowed(plant: Plant000Base) -> bool:
	if plant.battle_hidden_from_zombies or not is_instance_valid(plant.plant_cell) or plant.plant_cell.row_col.y < PROTECTED_COLUMNS:
		return false
	for cell: PlantCell in plant.battle_placement_cells: # 任一个实际占格进入前两列都受保护。
		if is_instance_valid(cell) and cell.row_col.y < PROTECTED_COLUMNS:
			return false
	return true

## 入树前将柱体定位到 [param game] 中 [param target] 的种植格；返回是否绑定成功。
## 绑定成功后将柱体添加到 [param game]，与正常战斗共用时钟和受击层。
func setup(game: MainGameManager, target: Plant000Base) -> bool:
	if is_inside_tree():
		return false
	_game = game
	_marked_plant = target
	var plant: Plant000Base = living_plant() # 确认初始锁定对象处于本局且拥有实际格子。
	if plant == null or not is_target_allowed(plant):
		return false
	_locked_cell = plant.plant_cell
	visual_span = maxf(1.0, minf(_locked_cell.size.x, _locked_cell.size.y))
	_position_at(_locked_cell)
	return true

## 返回当前格子的世界脚点；植株退场后保持最后的落点。
func world_foot() -> Vector2:
	return global_position

## 返回仍存活且位于原战斗内的锁定植株；已离场或死亡时返回空值。
func living_plant() -> Plant000Base:
	if not is_instance_valid(_game) or not is_instance_valid(_marked_plant) \
			or _marked_plant.is_death or _marked_plant.is_queued_for_deletion() \
			or not _game.is_ancestor_of(_marked_plant) or not is_instance_valid(_marked_plant.plant_cell):
		return null
	return _marked_plant

## [param delta] 为经过的战斗秒数；场景暂停和快进沿用引擎时钟。
func _process(delta: float) -> void:
	if is_death or is_queued_for_deletion():
		return
	if living_plant() != null:
		global_position = _cell_foot(_locked_cell) # 平台移动时跟随原格，原株离场后保留最后落点。
	_elapsed = minf(DURATION, _elapsed + delta)
	if _elapsed >= DURATION or is_equal_approx(_elapsed, DURATION):
		_mature()

## 占格和承托全部提交后检查原株，在真实落点触发湮灭。前两列保护只用于初次锁定。
func _on_plant_relocated() -> void:
	if is_death or is_queued_for_deletion():
		return
	var plant: Plant000Base = living_plant() # 其他植株的移动和同一格的布局变化不会触发结算。
	if plant == null or plant.plant_cell == _locked_cell:
		return
	_position_at(plant.plant_cell)
	_mature()

## 将 [param cell] 的普通层脚点和行绘制层级同步给白柱与结算演出。
func _position_at(cell: PlantCell) -> void:
	lane = cell.row_col.x
	z_index = lane * 50 + 35
	position = _game.to_local(_cell_foot(cell))

## 单次提交成熟结算，在同步的植物死亡等回调前关闭受击和后续触发。
func _mature() -> void:
	_elapsed = DURATION
	set_process(false)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	queue_free()
	expired.emit(self)

## 返回 [param cell] 的固定普通层锚点；柱体不会随身体、承托物或冒出地面的动画摆动。
func _cell_foot(cell: PlantCell) -> Vector2:
	return cell.get_slot_anchor_global_position(CharacterRegistry.PlacePlantInCell.Norm)
