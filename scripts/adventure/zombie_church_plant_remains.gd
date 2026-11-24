## 教堂的死亡残影占用与路灯花清除进度。剪影永远只作为世界绘制节点。
extends Node

## 冻结死前动画姿态并绘制焦黑轮廓。
const Imprint = preload("res://scripts/adventure/zombie_church_plant_imprint.gd")
## 与世界照明共用暖灯覆盖函数。
const Light = preload("res://scripts/battle/environment/battle_light_source.gd")
## 本场暖灯的注册与收集接口。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 只撤销残影自己的禁种来源。
const PLANTING_BLOCK := &"church_plant_remains"
## 连续照射清除所需的未暂停真实秒。
const CLEAR_SECONDS := 8.0
## 暖光达到一个八位遮罩色阶时视为照到该格中心。
const MIN_COVERAGE := 1.0 / 255.0

## 同一株的残影拥有完整的多格范围及连续照射进度。
class Remain:
	## 挂载定格形体的主占格，也提供复生行和脚点。
	var origin: PlantCell
	## 整株曾占用的格子，任一个未被照亮都要重新积累时间。
	var footprint: Array[PlantCell]
	## 贴在原格上的绘制节点，在瓦解期间与禁种状态分离。
	var imprint: Imprint
	## 最近一次中断之后已经连续照亮的真实秒数。
	var illuminated_seconds: float

## 本局的战场，用来拒绝退场或清盘造成的脚本通知。
var _battle: MainGameManager
## 教堂暖灯及局部光衰减的唯一来源。
var _field: LightField
## 读取灯光控制器的环境状态。
var _is_dark: Callable
## 尚未清除的残影。
var _remains: Array[Remain] = []
## 各格持有残影的数量，同格多个叠种死亡不会提前解锁。
var _blocks: Dictionary[PlantCell, int] = {}
## 全场只创建一个残影材质。
var _material: ShaderMaterial
## 救主及分身均可阻止清除，直到最后一位离场。
var _cleansing_block: Dictionary[int, WeakRef] = {}

## 绑定 [param battle] 的原生死亡通知，[param field] 提供暖灯，[param is_dark] 判断环境光是否归零。
func bind_battle(battle: MainGameManager, field: LightField, is_dark: Callable) -> void:
	_battle = battle
	_field = field
	_is_dark = is_dark
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/adventure/wonderland/zombie_church_plant_imprint.gdshader")
	battle.board.plant_dying.connect(_on_plant_dying)

## 在 [param plant] 释放碰撞、占格和动画资源之前保存死前姿态并锁格。
func _on_plant_dying(plant: Plant000Base) -> void:
	if plant is Plant026Plantern or not _is_dark.call() or not _battle.board.allows_mutation() \
			or _battle.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	var origin: PlantCell = plant.plant_cell # 只捕获通过本场空间实际放置过的实体。
	if origin.board != _battle.board or plant.battle_placement_cells.is_empty():
		return
	for cell: PlantCell in plant.battle_placement_cells: # 多格植物的每个实际占位都保留到清除。
		if not is_instance_valid(cell) or not cell.is_inside_tree() or cell.is_queued_for_deletion() \
				or cell.board != _battle.board or not cell.plant_entities().has(plant):
			return
	var entry := Remain.new() # 与活体占用独立，同格的其他层继续留在原处。
	entry.origin = origin
	entry.footprint = plant.battle_placement_cells.duplicate()
	entry.imprint = Imprint.new()
	entry.imprint.capture(plant, origin, _material)
	origin.add_child(entry.imprint)
	_remains.append(entry)
	for cell: PlantCell in entry.footprint: # 所有残影及时获得同一格的禁种来源。
		var count: int = _blocks.get(cell, 0) # 到最后一个残影清除时才解除。
		_blocks[cell] = count + 1
		if count == 0:
			cell.set_planting_block(PLANTING_BLOCK, true)

## 在未暂停的 [param seconds] 内采样路灯花照明，包含画面外的灯。
func advance(seconds: float) -> void:
	if _remains.is_empty():
		return
	var lights: Array[Light] = _field.warm_lights(true) # 同一列表供本帧全部残影采样。
	var time_step: float = 0.0 if _has_cleansing_blocker() else seconds # 暂停积累，但光线中断仍清零。
	for index: int in range(_remains.size() - 1, -1, -1): # 到期可立即解锁而不影响未处理条目。
		var entry: Remain = _remains[index] # 完整占格和计时均只在此管理。
		if not is_instance_valid(entry.imprint) or not entry.imprint.is_inside_tree():
			_release(entry)
			_remains.remove_at(index)
			continue
		var lit: bool = _lit_by_lamps(entry.footprint, lights) # 以每格中心是否有暖光作为连续条件。
		var elapsed: float = entry.illuminated_seconds + time_step if lit else 0.0 # 光照中断后从零重计。
		if elapsed >= CLEAR_SECONDS:
			_release(entry)
			_remains.remove_at(index)
			entry.imprint.disperse()
		elif elapsed != entry.illuminated_seconds:
			entry.illuminated_seconds = elapsed
			entry.imprint.set_light_wear(elapsed / CLEAR_SECONDS)

## [param boss] 存活期间停止暖光清除。保存弱引用，不延长 Boss 生命周期。
func hold_cleansing(boss: ZB000Base) -> void:
	_cleansing_block[boss.get_instance_id()] = weakref(boss)

## 回收死亡或离场的施法者。其他存活分身仍然保持亡影。
func _has_cleansing_blocker() -> bool:
	var held := false # 可与刚刚消失的分身同帧更新。
	for id: int in _cleansing_block.keys(): # 使用键快照以安全移除已失效引用。
		var boss := _cleansing_block[id].get_ref() as ZB000Base # 弱引用不延长退场动画或战斗的生命周期。
		if not is_instance_valid(boss) or boss.is_death or boss.is_queued_for_deletion():
			_cleansing_block.erase(id)
		else:
			held = true
	return held

## [param spawn_follower] 接收亡影所属行和世界脚点，返回成功生成的信徒。
func revive(spawn_follower: Callable) -> void:
	for index: int in range(_remains.size() - 1, -1, -1): # 每个亡影实体仅复生一次，多格范围统一解除。
		var entry: Remain = _remains[index] # 等创建成功再取走原有残影。
		if not _can_revive(entry):
			continue
		if not is_instance_valid(spawn_follower.call(entry.origin.row_col.x, entry.imprint.global_position)):
			continue
		_release(entry)
		_remains.remove_at(index)
		entry.imprint.disperse()

## 返回是否还有有效亡影，已经瓦解的剪影不会进入施法判定。
func has_revivable_remains() -> bool:
	return _remains.any(_can_revive)

## [param entry] 的主格与剪影都仍在棋盘中时才可复生。
func _can_revive(entry: Remain) -> bool:
	return is_instance_valid(entry.origin) and entry.origin.is_inside_tree() \
		and not entry.origin.is_queued_for_deletion() and is_instance_valid(entry.imprint) \
		and entry.imprint.is_inside_tree() and not entry.imprint.is_queued_for_deletion()

## 在 [param lights] 的有效暖光贡献中判断 [param center]。鼠标和环境光不参与。
static func lamp_covers(center: Vector2, lights: Array[Light]) -> bool:
	return lights.any(func(light: Light) -> bool: return light.coverage_at(center) >= MIN_COVERAGE)

## [param lights] 中至少一盏实际暖灯照亮 [param footprint] 的每个格心才返回 true。
func _lit_by_lamps(footprint: Array[PlantCell], lights: Array[Light]) -> bool:
	if lights.is_empty():
		return false
	for cell: PlantCell in footprint: # 真实格心随棋盘平台移动。
		if not is_instance_valid(cell) or not cell.is_inside_tree():
			return false
		var center: Vector2 = cell.get_global_transform() * (cell.size * 0.5) # 光场和占格共用世界坐标。
		if not lamp_covers(center, lights):
			return false
	return true

## 释放 [param entry] 的占格。已有固有地形和其他禁种来源仍在。
func _release(entry: Remain) -> void:
	for cell: PlantCell in entry.footprint: # 即使原格离树，也需回收同株仍存活的其他格。
		var count: int = _blocks.get(cell, 0) - 1 # 同格多个残影各自独立清除。
		if count > 0:
			_blocks[cell] = count
		else:
			_blocks.erase(cell)
			if is_instance_valid(cell) and cell.is_inside_tree():
				cell.set_planting_block(PLANTING_BLOCK, false)
