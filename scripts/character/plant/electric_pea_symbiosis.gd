## 电磁共生仅维护本株的动态光环与局部可视连线。
extends Node2D
class_name ElectricPeaSymbiosis

## 本株共生独立于其他光环的稳定来源。
const AURA_SOURCE: StringName = &"electric_pea_symbiosis"
## 可提供共生的两种实际雷电植物ID。
const ELECTRIC_TYPES: Array[int] = [50, 52]
## 共生和电球共用本物种的电青、紫白色表，不改变闪电芦苇的本体。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")

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
## 冻结的出战外观等级，仅影响光环连线，不参与增伤计算。
var _appearance_rank: int = 0
## 共生细流的有效表现秒数，暂停时不推进。
var _visual_age: float = 0.0
## 表现更新的未消费秒数，最多每秒重绘二十次。
var _visual_remainder: float = 0.0


## 为 [param owner_plant] 安装从 [param mouth] 显示的共生；未选择 [param bonus] 时返回空。
static func install(owner_plant: Plant000Base, mouth: Marker2D, bonus: float) -> ElectricPeaSymbiosis:
	if bonus <= 0.0:
		return null
	var aura := ElectricPeaSymbiosis.new() # 只有选共生的实际出战株持有此画布。
	aura.plant = owner_plant
	aura.launch = mouth
	aura.bonus_per_plant = bonus
	aura._appearance_rank = owner_plant.plant_spawn_profile.promotion_tier() if owner_plant.plant_spawn_profile != null else 0
	aura.z_index = 300
	owner_plant.add_child(aura)
	aura.set_process(false)
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
		set_process(not _links.is_empty())
		queue_redraw()


## [param delta] 只推进连接中的低亮度电流，空光环不占用逐帧处理。
func _process(delta: float) -> void:
	_visual_age += delta
	_visual_remainder += delta
	if _visual_remainder >= 0.05:
		_visual_remainder = fmod(_visual_remainder, 0.05)
		queue_redraw()


## 离树时对称移除共生来源。
func _exit_tree() -> void:
	clear()


## 共生使用低亮度细流，与伤害矩阵的连续亮芯区分；端点始终跟随真实植物。
func _draw() -> void:
	var colors: Dictionary = PromotionArt.effect_colors(_appearance_rank) # 五阶共生与电球使用相同的清亮配色。
	var phase: int = floori(_visual_age * 7.0) # 离散电流节奏避免每帧随机抖动。
	for index: int in range(0, _links.size(), 2): # 每对端点仍只代表一株邻居。
		var start: Vector2 = _links[index] # 本株枪口在画布中的位置。
		var finish: Vector2 = _links[index + 1] # 相邻植物的真实锚点。
		if start.distance_squared_to(finish) < 1.0:
			continue
		var strand: PackedVector2Array = ElectricPeaArcVisual.make_path(start, finish,
			index * 43 + phase, 1.8, 16.0, 16) # 只有微小摆动，不能表现成伤害范围。
		ElectricPeaArcVisual.draw_strand(self, strand, colors, 0.24, 0.65)
		var progress: float = fposmod(_visual_age * 0.65 + float(index) * 0.17, 1.0) # 各连线错相，能量从邻株流向本株。
		draw_circle(finish.lerp(start, progress), 1.15, Color(colors.core, 0.50), true, -1.0, true)
