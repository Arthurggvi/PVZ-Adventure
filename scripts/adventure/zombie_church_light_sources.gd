## 教堂的灯罩、地面垂足与出战角色标定。角色仍通过既有生命周期通知登记。
extends Node

## 教堂使用的统一光场。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 活体路灯花提供的同一份覆盖模型。
const Light = preload("res://scripts/battle/environment/battle_light_source.gd")
## 灯罩两块玻璃相接处，坐标相对于原精灵。
const LANTERN_GLASS_CENTER := Vector2(35.0, 48.0)
## 教堂单盏投影灯的可见半径，单位为平均格宽。
const LAMP_RADIUS_CELLS := 2.5

## 虚拟灯高，单位为本场平均格宽。
@export_range(1.1, 3.0) var emitter_height_cells := 1.74
## 有限灯源半径，用平均格宽换算半影。
@export_range(0.0, 0.30) var emitter_radius_cells := 0.068
## 普通僵尸的原画高度和虚拟高度，依次为 x、y，单位为平均格宽。
@export var zombie_heights := Vector2(1.66, 1.0)
## 普通植物的原画高度和虚拟高度，单位为平均格宽。
@export var plant_heights := Vector2(1.02, 0.54)
## 僵王的原画高度和虚拟高度，单位为平均格宽。
@export var boss_heights := Vector2(2.45, 1.36)
## 特殊的平面植物使用更低的标定高度。
@export var plant_overrides: Dictionary[int, Vector2] = {
	CharacterRegistry.PlantType.P022Caltrop: Vector2(0.39, 0.12),
	CharacterRegistry.PlantType.P047SpikeRock: Vector2(0.45, 0.16),
}
## 体型明显有别的僵尸可以配置自己的固定高度。
@export var zombie_overrides: Dictionary[int, Vector2] = {
	CharacterRegistry.ZombieType.Z024Gargantuar: Vector2(2.62, 1.43),
	CharacterRegistry.ZombieType.Z025Imp: Vector2(0.98, 0.60),
}

## 本次登记使用的平均格宽。
var _span: float
## 所有灯和角色都进入同一个光场。
var _field: LightField

## 绑定 [param battle] 的成功放置和出场信号到 [param field]，返回平均格宽。
func bind_battle(battle: MainGameManager, field: LightField) -> float:
	_field = field
	var cells: Array[PlantCell] = battle.board.cells() # 棋盘已在父节点的入树阶段建好。
	_span = _cell_span(cells)
	for cell: PlantCell in cells: # 只在战斗建立时绑定一次。
		cell.signal_plant_create.connect(_on_plant_created)
	var manager: ZombieManager = battle.get_node("Manager/ZombieManager") # 在父战斗开始刷怪前绑定。
	manager.signal_zombie_created.connect(_register)
	manager.signal_living_bosses_changed.connect(_register_bosses.bind(manager))
	return _span

## 无环境光场时，按 [param board] 的实际路灯花计算一次庇护范围。
static func sample_plantern_lights(board: BoardRuntime) -> Array[Light]:
	var cells: Array[PlantCell] = board.cells() # 与教堂光场使用相同格宽标定。
	var radius: float = _cell_span(cells) * LAMP_RADIUS_CELLS # 名义半径随地图格距变化。
	var lights: Array[Light] = [] # 结算结束即可丢弃，无需维护每帧的渲染灯。
	for cell: PlantCell in cells: # 按实际主格访问每盏灯一次。
		for plant: Plant000Base in cell.living_plants(): # 包含叠种，排除已死亡的灯。
			if not plant is Plant026Plantern or plant.plant_cell != cell:
				continue
			var light := Light.new() # 灯罩位置与实际暖光衰减一致。
			light.anchor = plant.lantern_face
			light.id = light.anchor.get_instance_id()
			light.offset = LANTERN_GLASS_CENTER
			light.radius = radius
			light.reach = radius * Light.EDGE_MARGIN
			light.tone = LightField.Tone.WARM
			light.seed = float(light.id % 997) / 997.0
			if light.refresh_center():
				lights.append(light)
	return lights

## 返回 [param cells] 的平均格宽，兼容不同形状的棋盘。
static func _cell_span(cells: Array[PlantCell]) -> float:
	var total := 0.0 # 格子的宽高都计入世界尺度。
	for cell: PlantCell in cells: # 累加实际棋盘格的世界尺寸。
		total += (cell.size.x + cell.size.y) * 0.5
	return total / maxi(cells.size(), 1)

## [param cell] 中成功种下 [param _species] 时登记实际植物，覆盖存档还原与复生。
func _on_plant_created(cell: PlantCell, _species: CharacterRegistry.PlantType) -> void:
	for plant: Plant000Base in cell.living_plants(): # 按实体登记，重复通知不增加灯。
		_register(plant)
		var plantern := plant as Plant026Plantern # 路灯花从真实玻璃中心发光。
		if plantern != null:
			_register_lamp(plantern, plantern.lantern_face, LANTERN_GLASS_CENTER, LightField.Tone.WARM)

## 为 [param actor] 登记随 [param anchor] 及其 [param offset] 移动的灯，死亡时撤销。
## [param tone] 区分路灯花的棋盘照明与救主的红色演出用光。
func _register_lamp(actor: Character000Base, anchor: Node2D, offset: Vector2, tone: LightField.Tone) -> void:
	if _field.register_light(anchor, tone, _span * LAMP_RADIUS_CELLS, offset,
			actor.shadow, _span * emitter_height_cells, _span * emitter_radius_cells, 1.0, tone == LightField.Tone.WARM):
		var unregister: Callable = _field.unregister_light.bind(anchor.get_instance_id()) # 保留出场光和死亡帧间的连续亮度。
		if tone == LightField.Tone.RED:
			actor.tree_exiting.connect(unregister, CONNECT_ONE_SHOT)
		else:
			actor.signal_character_death.connect(unregister, CONNECT_ONE_SHOT)

## 为 [param character] 登记稳定标定。死亡动画的身体仍留在图集的正常生命周期内。
func _register(character: Character000Base) -> void:
	var heights: Vector2 = boss_heights # 僵王与普通僵尸使用不同原画标定。
	if character is Plant000Base:
		heights = plant_overrides.get(character.plant_type, plant_heights)
	elif character is Zombie000Base:
		heights = zombie_overrides.get(character.zombie_type, zombie_heights)
		if character.is_mini_zombie:
			heights *= 0.67
	_field.shadow_projection.register_caster(character.body, character.shadow, character,
		_span * heights.x, _span * heights.y)

## 从 [param manager] 的存活名单接入独立登场的僵王。
func _register_bosses(manager: ZombieManager) -> void:
	for boss: ZB000Base in manager.get_living_bosses(): # 名单变更时才触发。
		_register(boss)
		var anchor := boss.get_node_or_null(^"Body/ChurchLight") as Marker2D # 角色场景可标定自身的演出灯。
		if anchor != null:
			_register_lamp(boss, anchor, Vector2.ZERO, LightField.Tone.RED)
