## 电磁共生仅维护本株的动态光环与局部可视连线。
extends Node2D
class_name ElectricPeaSymbiosis

## 本株共生独立于其他光环的稳定来源。
const AURA_SOURCE: StringName = &"electric_pea_symbiosis"
## 可提供共生的两种实际雷电植物ID。
const ELECTRIC_TYPES: Array[int] = [50, 52]
## 轻量连线的像素宽度和颜色使用固定表现。
const LINE_COLOR := Color(0.59, 0.87, 1.0, 0.68)

## 光环接受者；节点随此株一起离场。
var plant: Plant000Base
## 本株出手的实际口部标记，连线跟随平台和身体。
var launch: Marker2D
## 每株邻居贡献的伤害比例。
var bonus_per_plant: float = 0.0
## 上次提交给本株的共生比例，避免逐帧重算无变化的伤害倍率。
var _bonus: float = 0.0
## 当前邻居的绘制端点，相对于本画布。
var _links := PackedVector2Array()


## 为 [param owner_plant] 安装从 [param mouth] 显示的共生；未选择 [param bonus] 时返回空。
static func install(owner_plant: Plant000Base, mouth: Marker2D, bonus: float) -> ElectricPeaSymbiosis:
	if bonus <= 0.0:
		return null
	var aura := ElectricPeaSymbiosis.new() # 只有选共生的实际出战株持有此画布。
	aura.plant = owner_plant
	aura.launch = mouth
	aura.bonus_per_plant = bonus
	aura.z_index = 300
	owner_plant.add_child(aura)
	owner_plant.signal_character_death.connect(aura.clear)
	return aura


## 在有效的 [param board] 内同步本株实际邻居与光环；无效时撤销贡献。
func refresh(board: BoardRuntime) -> void:
	var endpoints := PackedVector2Array() # 重新读取动态世界位置，比较后才重绘。
	if board != null and is_instance_valid(plant.plant_cell) and plant.plant_cell.board == board \
			and not plant.plant_cell.is_queued_for_deletion() and plant.plant_cell.is_visible_in_tree() \
			and plant.plant_cell.living_plants().has(plant):
		var origin: PlantCell = plant.plant_cell # 真实占用地块可随植物迁移变更。
		var seen: Dictionary[int, bool] = {} # 同株从多个地块层返回时只贡献一次。
		for cell: PlantCell in board.neighbors(origin, 1): # 权威3×3邻接含同格承托和伴生。
			if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree() \
					or cell.board_definition.surface_id != origin.board_definition.surface_id:
				continue
			for neighbor: Plant000Base in cell.living_plants(): # 排除自身、退场对象与非雷电物种。
				if neighbor == plant or neighbor.plant_cell != cell or not ELECTRIC_TYPES.has(neighbor.plant_type) \
						or not Global.main_game.is_ancestor_of(neighbor) or not neighbor.is_visible_in_tree() \
						or seen.has(neighbor.get_instance_id()):
					continue
				seen[neighbor.get_instance_id()] = true
				var anchor: Vector2 = neighbor.body.global_position if is_instance_valid(neighbor.body) else neighbor.global_position # 从邻居的实体处显示连接。
				endpoints.append(to_local(launch.global_position))
				endpoints.append(to_local(anchor))
	_set_links(endpoints)


## 撤销本株光环并清空所有共生表现。
func clear() -> void:
	_set_links(PackedVector2Array())


## 将 [param endpoints] 的每对端点计为一株不同邻居，只有贡献变化才写入本株伤害入口。
func _set_links(endpoints: PackedVector2Array) -> void:
	var bonus: float = endpoints.size() * 0.5 * bonus_per_plant # 每对端点贡献一次。
	if bonus != _bonus:
		_bonus = bonus
		if is_instance_valid(plant):
			plant.set_battle_aura_damage_source(AURA_SOURCE, bonus)
	if _links != endpoints:
		_links = endpoints
		queue_redraw()


## 离树时对称移除共生来源。
func _exit_tree() -> void:
	clear()


## 本株只需一个绘制节点即可显示全部共生连接。
func _draw() -> void:
	if not _links.is_empty():
		draw_multiline(_links, LINE_COLOR, 1.5, true)
