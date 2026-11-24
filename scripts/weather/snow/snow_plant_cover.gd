## 雪山植株的表现登记。只从 BoardRuntime 观察占位，不复制棋盘索引。
extends Node2D
class_name SnowPlantCover

## 植物与僵尸共用的环境色和抖雪记录。
const ActorCover = preload("res://scripts/weather/snow/snow_actor_cover.gd")
## 当前局天气样本与接触画布。
const Presentation = preload("res://scripts/weather/snow/snow_actor_presentation.gd")
## 棋盘活植株扫描间隔，单位游戏秒。
const SCAN_INTERVAL: float = 0.25

## 拥有权威 BoardRuntime 的场景管理器。
var _game: MainGameManager
## 已登记的视觉实例，以角色实例编号为键。
var _covers: Dictionary[int, ActorCover] = {}
## 已积累的扫描时间，首帧读取已有占位。
var _scan_elapsed: float = SCAN_INTERVAL

## 绑定 [param game] 的棋盘，天气控制器组装时调用一次。
func configure(game: MainGameManager) -> void:
	_game = game

## 推进 [param delta] 游戏秒。用 [param presentation] 给正式植株应用天气和足缘。
func advance(delta: float, presentation: Presentation) -> void:
	if not is_instance_valid(_game):
		return
	if _game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		for cover: ActorCover in _covers.values(): # 预览和结算期间停用环境色与抖雪触发。
			cover.suspend()
		_scan_elapsed = SCAN_INTERVAL
		return
	_scan_elapsed += delta
	if _scan_elapsed >= SCAN_INTERVAL:
		_scan_elapsed = 0.0
		_scan_occupants()
	for cover: ActorCover in _covers.values(): # 多格植株只更新一次天气表现。
		var plant: Plant000Base = cover.actor as Plant000Base # 当前活植株。
		if not is_instance_valid(plant) or not plant.is_inside_tree() or plant.is_queued_for_deletion() \
				or plant.is_death or plant.is_show or plant.is_being_relocated:
			cover.suspend()
			continue
		cover.advance(presentation)
		_add_root_contact(plant, presentation)

## 从现有占位读取存活植株，兼容多格植物、伴生、搬运和替换。
func _scan_occupants() -> void:
	var board: BoardRuntime = _game.board # 当前已有的棋盘索引。
	var seen: Dictionary[int, bool] = {} # 此次扫描中处理过的实例编号。
	if board != null and board.configured:
		for cell: PlantCell in board.cells(): # 只有正式战场包含的格子。
			if not is_instance_valid(cell) or not cell.is_inside_tree():
				continue
			for plant: Plant000Base in cell.living_plants(): # 排除已移除占位的单位。
				var id: int = plant.get_instance_id() # 多格占位仍只有一个视觉记录。
				if seen.has(id) or plant.is_show or plant.is_being_relocated or not is_instance_valid(plant.body):
					continue
				seen[id] = true
				if not _covers.has(id):
					_register_cover(plant, id)
	for id: int in _covers.keys(): # 用快照释放已退场或被替换的植株。
		if not seen.has(id):
			_remove_cover(id)

## 从 [param plant] 的真实美术登记扬雪源，以 [param id] 绑定死亡和离树信号。
func _register_cover(plant: Plant000Base, id: int) -> void:
	var cover: ActorCover = ActorCover.new(plant) # 没有扬雪源的植株也可接收淡环境色。
	var sources: Array[StringName] = SnowPlantProfiles.for_species(plant.spawn_species_id()) # 真实枝叶和主体的节点名。
	if not sources.is_empty():
		for child: Node in plant.body.find_children("*", "CanvasItem", true, false): # 仅登记时查找有效美术。
			if sources.has(child.name) and (child is Sprite2D or child is AnimatedSprite2D):
				cover.add_shed_source(child as Node2D)
	_covers[id] = cover
	plant.signal_character_death.connect(_remove_cover.bind(id))
	plant.tree_exited.connect(_on_plant_exit.bind(id), CONNECT_DEFERRED)

## [param id] 可能只是格内承托或搬运换父节点；在重挂结束后区分真正退场。
func _on_plant_exit(id: int) -> void:
	var cover: ActorCover = _covers.get(id) # 同一帧的死亡清理可能已经移除了此记录。
	if cover == null:
		return
	var plant: Character000Base = cover.actor # 引用可能已随队列删除失效。
	if not is_instance_valid(plant) or not plant.is_inside_tree() or not is_instance_valid(_game) \
			or not _game.is_ancestor_of(plant):
		_remove_cover(id)

## 给有明确近地叶片的 [param plant] 提交 [param presentation] 的栽种脚点。
func _add_root_contact(plant: Plant000Base, presentation: Presentation) -> void:
	var cell: PlantCell = plant.plant_cell # 主格的固定种植锚点。
	var slot: CharacterRegistry.PlacePlantInCell = CharacterRegistry.PlacePlantInCell.Norm # 根部与雪直接接触的原生槽。
	if not is_instance_valid(cell) or cell.plant_in_cell.get(slot) != plant or not plant.body.is_visible_in_tree() \
			or is_instance_valid(cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Down)):
		return
	var width: float # 低叶冠在世界坐标中的接触全宽。
	match plant.spawn_species_id():
		CharacterRegistry.PlantType.P001PeaShooterSingle: width = 36.0
		CharacterRegistry.PlantType.P002SunFlower: width = 29.0
		_: return
	var point: Vector2 = cell.get_slot_anchor_global_position(slot) # 槽锚点已纳入雪山坡度。
	if plant.global_position.distance_squared_to(point) <= 16.0:
		presentation.footing.add_contact(point, cell.row_col.x, width * plant.global_transform.x.length(),
			plant.modulate.a * plant.body.modulate.a)

## 移除 [param id] 的天气表现和连接；死亡与退场均可重复通知。
func _remove_cover(id: int) -> void:
	var cover: ActorCover = _covers.get(id) # 对已经清理的编号无需操作。
	if cover == null:
		return
	_covers.erase(id)
	var plant: Plant000Base = cover.actor as Plant000Base # 释放仍可能活着的植物上的信号。
	if is_instance_valid(plant):
		plant.signal_character_death.disconnect(_remove_cover.bind(id))
		plant.tree_exited.disconnect(_on_plant_exit.bind(id))
	cover.release()

## 独立卸载天气时也恢复仍在树上的植株。
func _exit_tree() -> void:
	for id: int in _covers.keys(): # 以快照清空所有视觉登记。
		_remove_cover(id)
