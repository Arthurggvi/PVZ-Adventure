extends Control
class_name PlantCell

## 唯一种植空间索引；独立预览/花园不借用战斗空间。
var board: BoardRuntime
## 战斗私有的静态地块声明，身份和逻辑地址不由画面位置反推。
var board_definition: BoardCellDefinition
## 当前地形能力，只有统一地形入口可以替换。
var board_terrain: BoardTerrainDefinition
## 旧屋顶沿用场景局部坡面修正，自定义坐标不自动当作高度。
var legacy_ground_height: bool = false
## 地形实例层，切换时统一释放行为和水体。
var _terrain_layer: BoardTerrainLayer
## 具名禁种来源；特殊地形无需扩展原有固定枚举。
var _planting_blocks: Dictionary[StringName, bool] = {}
## 稳定身份直接读取定义，禁止保存第二份可变 ID。
var cell_id: StringName:
	get:
		return board_definition.cell_id if board_definition != null else &""


## 植物的父节点为对应位置的容器节点 plant_container_node
## 底部植物会上下移动
## 如果使用tween控制移动，每帧计算差值控制中间植物上下移动会卡#
## 因此放置底部植物时：
## 将中间植物（norm和shell）的容器节点放到底部植物的容器（底部植物自带的子节点，与植物格子的底部植物容器无关）中
## 底部植物容器会上下移动，从而带动中间植物上下移动
## 中间植物的位置与底部植物的容器位置无关

signal click_cell
signal cell_mouse_enter
signal cell_mouse_exit
## 删除墓碑信号
signal signal_cell_delete_tombstone(plant_cell:PlantCell, tombstone:TombStone)

@onready var button: Button = $Button
## 植物碰撞器位置节点
@onready var plant_area_2d_position: Control = $PlantArea2dPosition
## 场景默认普通植物锚点到格子底边的距离，单位像素。
@onready var _default_plant_inset: float = -$PlantNormContainer.offset_top
## 当前应用到各层锚点的纵向位移，阶段调整时据此只移动差量。
var _ground_anchor_shift: float = 0.0

## 植物格子类型
enum PlantCellType{
	Grass,		## 草地
	Pool,		## 水池
	Roof,		## 屋顶/裸地
}
## 当前格子类型
@export var plant_cell_type :PlantCellType = PlantCellType.Grass

## 逻辑攻击行/拓扑列由 BoardDefinition 唯一声明；旧场景导出仅作兼容。
@export var row_col:Vector2i:
	get:
		return board_definition.address if board_definition != null else row_col
	set(value):
		# 旧场景反序列化可赋值，运行时地址由布局声明唯一决定。
		if board_definition == null:
			row_col = value

## 当前攻防行。普通棋盘沿用稳定地址，启用脚点投影的平台由 BoardSurface 更新。
var combat_lane: int:
	get:
		return _projected_lane if _projected_lane >= 0 else row_col.x
## 当前平台脚点投影的行号，-1 表示使用原逻辑行。
var _projected_lane: int = -1

@export_group("当前格子的条件")
@export_subgroup("植物种植")
#@export_flags("1 无", "2 草地", "4 花盆", "8 水", "16 睡莲", "32 屋顶/裸地")
var ori_condition:int = 3
## 植物种植地形条件（满足一个即可），默认（无1 + 草地2 = 3）
var curr_condition:int = 3

## 在当前格子中对应位置的植物
@export var plant_in_cell:Dictionary[CharacterRegistry.PlacePlantInCell, Plant000Base] =  {
	CharacterRegistry.PlacePlantInCell.Norm: null,
	CharacterRegistry.PlacePlantInCell.Float: null,
	CharacterRegistry.PlacePlantInCell.Down: null,
	CharacterRegistry.PlacePlantInCell.Shell: null,
	#CharacterRegistry.PlacePlantInCell.Imitater: null,
}

## 每个物种最多一株不占种植位的伴生植物；不进入普通层或升级前置。
var _companion_plants: Dictionary[int, Plant000Base] = {}
## 本格最近一次真实死亡的完整记录；多格植物共享一枚成功消费令牌。
var latest_plant_death: PlantDeathRecord

## 在当前格子中对应位置的容器节点
@onready var plant_container_node:Dictionary =  {
	CharacterRegistry.PlacePlantInCell.Norm: $PlantNormContainer/Content,
	CharacterRegistry.PlacePlantInCell.Shell: $PlantShellContainer/Content,
	CharacterRegistry.PlacePlantInCell.Float: $PlantFloatContainer,
	CharacterRegistry.PlacePlantInCell.Down: $PlantDownContainer,
	CharacterRegistry.PlacePlantInCell.Imitater: $PlantImitaterContainer,
}

## UI 定位节点始终留在格子中；移动的只有实际植物 Node2D，不再重挂带锚点的 Control。
@onready var _support_slot_anchors: Dictionary = {
	CharacterRegistry.PlacePlantInCell.Norm: $PlantNormContainer,
	CharacterRegistry.PlacePlantInCell.Shell: $PlantShellContainer,
}

@export_subgroup("特殊状态，特殊状态下无法种植")
## 是否可以种植普通植物
@export var can_common_plant := true
#var is_can_common_plant
enum E_SpecialStatePlant {
	IsTombstone,	# 墓碑
	IsCrater,		# 坑洞
	IsIceRoad,		# 冰道
	IsPot,			# 罐子
	IsNoPlantBowling,		# 不能种植（保龄球红线模式不能种植）
}

## 当前特殊状态
@export var curr_special_state_plant:Dictionary[E_SpecialStatePlant, bool]

## 当前格子冰道
var curr_ice_roads:Array[IceRoad] = []
## 当前cell的墓碑
var tombstone:TombStone
## 当前cell的坑洞
var crater:DoomShroomCrater

@export_subgroup("特殊状态，特殊状态下无法种植僵尸")
## 是否可以种植僵尸
@export var can_common_zombie := true
enum E_SpecialStateZombie {
	IsNoPlantBowling,		## 不能种植（保龄球红线模式不能种植）
}
## 当前特殊状态
@export var curr_special_state_zombie:Dictionary[E_SpecialStateZombie, bool]

## 梯子
var ladder:Ladder

## 植物种植和死亡信号
signal signal_plant_create(plant_cell:PlantCell, plant_type:CharacterRegistry.PlantType)
signal signal_plant_free(plant_cell:PlantCell, plant_type:CharacterRegistry.PlantType)

#region 植物格子初始化
func _ready() -> void:
	## 隐藏按钮样式
	var new_stylebox_normal = $Button.get_theme_stylebox("pressed").duplicate()
	$Button.add_theme_stylebox_override("normal", new_stylebox_normal)
	update_ground_anchors()

	## 统一地形能力在节点就绪后安装；旧场景不创建额外水体。
	if board_terrain == null:
		board_terrain = BoardTerrainDefinition.legacy(plant_cell_type)
	apply_board_terrain(board_terrain)

## 从当前地形能力初始化种植条件；承托层只投影 supported_flags。
func init_condition():
	if board == null:
		board_terrain = BoardTerrainDefinition.legacy(plant_cell_type)
	ori_condition = board_terrain.planting_flags
	_sync_support_terrain_condition()
	_update_state_plant()

#endregion


#region 伽刚特尔攻击当前植物格子
func be_gargantuar_attack(zombie_gargantuar:Zombie000Base):
	for reference: Variant in living_plants(): # 巨人攻击包括同格伴生，但每个实例只结算一次。
		if not is_instance_valid(reference):
			continue
		var plant := reference as Plant000Base # 前一个死亡回调后重新确认当前引用。
		if is_instance_valid(plant) and not plant.is_death and not plant.is_cold_frozen() \
				and plant.hurt_box_component.is_enabling:
			plant.be_flattened_from_enemy(zombie_gargantuar)
	if is_instance_valid(pot):
		pot.open_pot_be_gargantuar()


func plant_be_flattened():
	for reference: Variant in living_plants(): # 压平扫描真实植物，不依赖是否占种植位。
		if not is_instance_valid(reference):
			continue
		var plant := reference as Plant000Base # 前一个死亡回调后重新确认当前引用。
		if is_instance_valid(plant) and not plant.is_death:
			plant.be_flattened()

#endregion

#region 植物(僵尸)种植(死亡)
## 模仿者创建植物
func imitater_create_plant(plant_type:CharacterRegistry.PlantType, is_plant_start_effect:=true,
		spawn_profile: PlantSpawnProfile = null):
	await get_tree().process_frame
	var plant = create_plant(plant_type, false, is_plant_start_effect, true, false,
		spawn_profile, PlacementOrigin.Transformation)
	return plant
## 放置来源区分玩家操作、关卡配置、恢复及转化；全部共用占格与生命周期事务。
## 技能生成使用 Spawned，仍须通过完整地形和占用资格，不能冒充玩家操作。
enum PlacementOrigin {
	Player, ## 玩家成功使用卡片的主种植。
	LevelSetup, ## 关卡声明的预种植，可绕过玩家地形限制。
	SaveRestore, ## 已整体预检的存档恢复。
	Transformation, ## 模仿者等已有占用的实体转化。
	Spawned, ## 战斗技能生成，按玩家资格校验但不消费卡片。
	Companion, ## 不占种植位的技能子株，仍遵守地形、承托及障碍限制。
	Revival, ## 原物种正常占位复生，只免除已经完成的紫卡升级前置。
}

func create_plant(plant_type: CharacterRegistry.PlantType, is_imitater := false,
		is_plant_start_effect := true, is_imitater_material := false,
		is_zombie_mode := false, spawn_profile: PlantSpawnProfile = null,
		origin: PlacementOrigin = PlacementOrigin.Player,
		use_context: PlantPlacementUseContext = null) -> Plant000Base:
	var placement: PlantPlacement = PlantPlacement.prepare(self, plant_type, is_imitater,
		is_plant_start_effect, is_imitater_material, is_zombie_mode, spawn_profile, origin, use_context) # 共享离树准备。
	return placement.commit() if placement != null else null

## 提交已完整预检的 [param placement]；读档事务用 [param notify] 延后成功通知。[br]
## 此处不构造实体、不解码存档；统一写入新生植株的真实占用与承托关系。
func commit_prepared_plant(placement: PlantPlacement, notify: bool = true) -> Plant000Base:
	assert(placement.cell == self and not placement.committed)
	var plant: Plant000Base = placement.plant # 准备阶段构造并初始化的实例。
	plant.lane = combat_lane # 读档时平台可能在准备植物之后、正式入树之前恢复位姿。
	var slot: CharacterRegistry.PlacePlantInCell = placement.slot # 使用预检并冻结的实际种植层。
	placement.committed = true
	plant.battle_placement_cells = placement.footprint.duplicate()
	for claim: Dictionary in placement.claims:
		var predecessor: Plant000Base = claim["plant"] # 升级前置是转换消费，不进入最近死亡记录。
		predecessor.death_recording_enabled = false
		predecessor.character_death_disappear()
	if placement.imitater:
		plant_container_node[CharacterRegistry.PlacePlantInCell.Imitater].add_child(plant)
	else:
		plant_container_node[slot].add_child(plant)
	if placement.origin == PlacementOrigin.Companion:
		_register_companion(plant)
	else:
		for cell: PlantCell in placement.footprint: # 普通放置才写入独占层及承托状态。
			cell.plant_in_cell[slot] = plant
			plant.signal_character_death.connect(cell.one_plant_free.bind(plant))
			cell._sync_support_terrain_condition()

	if placement.play_effect:
		## 种植特效
		var plant_start_effect_scene:Node2D
		## 当前地形为水或者睡莲
		if curr_condition & 8 or curr_condition & 16:
			plant_start_effect_scene = SceneRegistry.PLANT_START_EFFECT_WATER.instantiate()
		else:
			plant_start_effect_scene = SceneRegistry.PLANT_START_EFFECT.instantiate()
		plant.body.add_child(plant_start_effect_scene)

	if not placement.imitater and slot == CharacterRegistry.PlacePlantInCell.Down:
		_attach_support_layers(plant as Plant000DownBase)

	if not placement.saved_state.is_empty():
		plant.load_game_data_plant(placement.saved_state)
	if placement.origin != PlacementOrigin.SaveRestore:
		plant.commit_placement_action()
	if notify:
		signal_plant_create.emit(self, plant.plant_type)

	return plant

## 登记同格 [param plant] 的伴生身份及生命周期；种植和手套换格共用。
func _register_companion(plant: Plant000Base) -> void:
	var species: int = int(plant.plant_type) # 伴生已经完成物种解析，不能是模仿者中间体。
	_companion_plants[species] = plant
	plant.signal_character_death.connect(one_companion_free.bind(plant), CONNECT_ONE_SHOT)
	plant.tree_exited.connect(_on_companion_tree_exited.bind(species, plant.get_instance_id()))

## [param plant] 必须是本格登记的活株；绑定原格的临时动作、梯子和正在承托的底座无法移动。
func can_lift_plant(plant: Plant000Base) -> bool:
	if board == null or not board.allows_mutation() or not is_instance_valid(plant) \
			or plant.is_queued_for_deletion() or not plant.is_inside_tree() or plant.is_death \
			or plant.is_being_relocated or plant.plant_cell != self or not plant_entities().has(plant) \
			or plant.battle_placement_cells.is_empty() or not plant.can_relocate():
		return false
	if plant is Plant999Imitater or plant is Plant012GraveBuster or plant is Plant036CoffeeBean:
		return false
	for source: PlantCell in plant.battle_placement_cells: # 断离地块或梯子都会锁住整株多格植物。
		if not is_instance_valid(source) or source.is_queued_for_deletion() \
				or source.process_mode == Node.PROCESS_MODE_DISABLED or is_instance_valid(source.ladder):
			return false
	return not plant is Plant000DownBase or not _support_layers_occupied()

## 返回 [param plant] 移到 [param destination] 所需的合法占格；空数组表示松手失败，原株保持在原处。
func relocation_footprint(plant: Plant000Base, destination: PlantCell) -> Array[PlantCell]:
	if not can_lift_plant(plant) or not is_instance_valid(destination) or destination == self \
			or destination.board != board or not destination.is_visible_in_tree():
		return []
	var condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
		plant.spawn_species_id(), CharacterRegistry.PlantInfoAttribute.PlantConditionResource) # 复用现有物种占格和种植限制。
	if condition != null and plant.plant_spawn_profile != null:
		condition = plant.plant_spawn_profile.placement_condition(condition)
	if condition == null:
		return []
	var slot: CharacterRegistry.PlacePlantInCell = condition.place_plant_in_cell # 已有实例落在同一种植层。
	var companion: bool = _companion_plants.get(int(plant.plant_type)) == plant # 伴生使用独立名额。
	if companion and not destination.can_host_companion(int(plant.plant_type)):
		return []
	if not companion and plant_in_cell.get(slot) != plant:
		return []
	if plant is Plant000DownBase and destination._support_layers_occupied():
		return []
	var footprint: Array[PlantCell] = condition.placement_cells(destination) # 多格植物由棋盘查实际相邻格。
	if footprint.size() != plant.battle_placement_cells.size() or not footprint.has(destination):
		return []
	for target: PlantCell in footprint: # 每个目标格都要仍在棋盘上，且未绑定梯子。
		if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_visible_in_tree() \
				or is_instance_valid(target.ladder):
			return []
	if not condition.judge_relocation_allowed(destination, footprint, plant, companion):
		return [] # 直接返回空数组，让 GDScript 按函数返回类型推断元素类型。
	return footprint

## 把 [param plant] 原实例换到 [param destination]；只在完整预检后改占格，成功返回 true。
## 不调用种植或死亡结算，血量、卡牌归属、动画和计时器随原实例保留。
func relocate_plant(plant: Plant000Base, destination: PlantCell) -> bool:
	var footprint: Array[PlantCell] = relocation_footprint(plant, destination) # 点击时复核，预览结果不能直接提交。
	if footprint.is_empty():
		return false
	_commit_plant_relocation(plant, destination, footprint)
	board.plant_relocated.emit()
	return true

## 将本格的承托、普通、壳层及伴生整体搬到同地形的空格 [param destination]。
## 已继承的承托与植株保持原实例和计时；任一成员被动作锁定或属于多格植物时整组拒绝。
func relocate_supported_stack(destination: PlantCell) -> bool:
	if board == null or not board.allows_mutation() or not is_instance_valid(destination) \
			or destination == self or destination.board != board or not destination.is_visible_in_tree() \
			or destination.row_col.x != row_col.x or destination.board_definition.surface_id != board_definition.surface_id \
			or board_terrain == null or destination.board_terrain == null \
			or destination.board_terrain.terrain_id != board_terrain.terrain_id or not destination.can_common_plant \
			or not destination.is_terrain_planting_allowed() or not destination.plant_entities().is_empty() \
			or is_instance_valid(ladder) or is_instance_valid(destination.ladder):
		return false
	var support: Plant000DownBase = get_support_plant() # 先搬底座，让目标内容节点附着在其承托位置。
	if not is_instance_valid(support):
		return false
	var plants: Array[Plant000Base] = living_plants() # 对全栈预检，避免底座与承托物分离。
	for plant: Plant000Base in plants: # 多格、在途种植和临时动作保留原有约束。
		if plant.plant_cell != self or plant.battle_placement_cells.size() != 1 or plant.is_being_relocated \
				or not plant.can_relocate() or plant is Plant999Imitater or plant is Plant012GraveBuster or plant is Plant036CoffeeBean:
			return false
	plants.erase(support)
	plants.push_front(support)
	var footprint: Array[PlantCell] = [destination] # 每个承托成员保留自己在同一格中的种植层。
	for plant: Plant000Base in plants: # 承托容器重挂时，其他成员也处于迁移状态。
		plant.is_being_relocated = true
	for plant: Plant000Base in plants: # 底座先于核心与保护壳提交，格位不重复占用。
		_commit_plant_relocation(plant, destination, footprint)
	board.plant_relocated.emit()
	return true

## 把已通过预检的 [param plant] 迁入 [param destination] 的 [param footprint]，由外层发送完成信号。
func _commit_plant_relocation(plant: Plant000Base, destination: PlantCell, footprint: Array[PlantCell]) -> void:
	var species: int = int(plant.plant_type) # 用于解绑原格的伴生登记。
	var companion: bool = _companion_plants.get(species) == plant # 普通层与伴生层各自移交原身份。
	var slot: CharacterRegistry.PlacePlantInCell = CharacterRegistry.PlacePlantInCell.Norm \
		if companion else plant_in_cell.find_key(plant) as CharacterRegistry.PlacePlantInCell # 对应目标容器。
	var support: Plant000DownBase = plant as Plant000DownBase # 非承托植物不改底层投影。
	plant.is_being_relocated = true
	if support != null:
		_detach_support_layers()
	if companion:
		_companion_plants.erase(species)
		plant.signal_character_death.disconnect(one_companion_free.bind(plant))
		plant.tree_exited.disconnect(_on_companion_tree_exited.bind(species, plant.get_instance_id()))
	else:
		for source: PlantCell in plant.battle_placement_cells: # 清空整株原占格，重叠部分也一起重接死亡信号。
			source.plant_in_cell[slot] = null
			plant.signal_character_death.disconnect(source.one_plant_free.bind(plant))
		for target: PlantCell in footprint: # 重挂前登记新占格，入树回调读到的是新位置。
			target.plant_in_cell[slot] = plant
			plant.signal_character_death.connect(target.one_plant_free.bind(plant))
	plant.battle_placement_cells = footprint
	plant.update_battle_cell(destination)
	_reparent_plant_content(plant, destination.plant_container_node[slot], false)
	if companion:
		destination._register_companion(plant)
	if support != null:
		_sync_support_terrain_condition()
		destination._sync_support_terrain_condition()
		destination._attach_support_layers(support)
	plant.is_being_relocated = false

## 普通层、壳层和伴生都可依附在底座上；允许单独移动空底座。
func _support_layers_occupied() -> bool:
	for slot: CharacterRegistry.PlacePlantInCell in _support_slot_anchors: # 直接检查真正挂载的内容容器。
		if plant_container_node[slot].get_child_count() > 0:
			return true
	return false

## [param species] 在本格有独立伴生名额；排队释放期间仍保留名额，避免重复计数。
func can_host_companion(species: int) -> bool:
	return not _companion_plants.has(species)

## 返回本格尚未释放的全部实体；恢复预检与数量查询不能忽略排队删除的植物。
func plant_entities() -> Array[Plant000Base]:
	var result: Array[Plant000Base] = [] # 保持占位层原顺序，同时按实例去重。
	for reference: Variant in plant_in_cell.values() + _companion_plants.values(): # 枚举副本不改权威集合。
		if not is_instance_valid(reference):
			continue
		var plant := reference as Plant000Base # 通过引用校验后才转换类型。
		if plant != null and not result.has(plant):
			result.append(plant)
	return result

## 返回本格全部存活实体的副本；占位层与伴生层统一供攻击、光环和清理查询。
func living_plants() -> Array[Plant000Base]:
	var result: Array[Plant000Base] = [] # 排除退场和已经结算死亡的实体。
	for plant: Plant000Base in plant_entities(): # 此只读遍历不会触发删除回调。
		if plant.is_inside_tree() and not plant.is_death and not plant.is_queued_for_deletion():
			result.append(plant)
	return result

## 返回满足 [param accept] 条件的第一个活体伴生；空条件保留选取和铲除使用的原有顺序。
func first_companion_plant(accept: Callable = Callable()) -> Plant000Base:
	for reference: Variant in _companion_plants.values(): # 暂时离树或延迟释放的引用不能成为目标。
		if not is_instance_valid(reference):
			continue
		var plant := reference as Plant000Base # 当前候选的真实植株。
		if plant.is_inside_tree() and not plant.is_death and not plant.is_queued_for_deletion() \
				and (not accept.is_valid() or accept.call(plant)):
			return plant
	return null

## [param species] 与 [param instance_id] 冻结离树身份；承托容器搬迁也会触发此通知。
func _on_companion_tree_exited(species: int, instance_id: int) -> void:
	_release_departed_companion.call_deferred(species, instance_id)

## 延后区分容器搬迁与真正释放；[param species] 的新实例不会被旧 [param instance_id] 清除。
func _release_departed_companion(species: int, instance_id: int) -> void:
	if not _companion_plants.has(species):
		return
	var reference: Variant = _companion_plants[species] # 可能已释放，只能先按Variant校验。
	if is_instance_valid(reference):
		if reference.get_instance_id() != instance_id or reference.is_inside_tree():
			return
	_companion_plants.erase(species)
	if is_inside_tree() and not is_queued_for_deletion():
		signal_plant_free.emit(self, species as CharacterRegistry.PlantType)

## [param plant] 死亡或直接离树时只释放自己的伴生记录；不会清除普通种植层。
func one_companion_free(plant: Plant000Base) -> void:
	if not is_instance_valid(plant) or _companion_plants.get(int(plant.plant_type)) != plant:
		return
	_companion_plants.erase(int(plant.plant_type))
	signal_plant_free.emit(self, plant.plant_type)
	if is_inside_tree() and is_instance_valid(button) and is_mouse_in_ui(button):
		_on_button_mouse_entered()

## 承托物消失后，清除确实失去地形支持的伴生实体，不改变普通植物的既有规则。
func _clear_unsupported_companions() -> void:
	for reference: Variant in _companion_plants.values(): # 保存副本，死亡回调可以安全移除记录。
		if not is_instance_valid(reference):
			continue
		var plant := reference as Plant000Base # 有效引用才进入地形资格检查。
		if plant.is_death or plant.is_queued_for_deletion():
			continue
		var condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
			plant.spawn_species_id(), CharacterRegistry.PlantInfoAttribute.PlantConditionResource) # 原物种地形契约。
		if condition != null and not (condition.plant_condition & curr_condition):
			plant.character_death_disappear()

## 检查 [param footprint] 的 [param slot] 是否空闲；[param claims] 中的前置占用允许升级。
func _placement_is_available(slot: CharacterRegistry.PlacePlantInCell,
		footprint: Array[PlantCell], claims: Array[Dictionary]) -> bool:
	for cell: PlantCell in footprint:
		if not is_instance_valid(cell):
			return false
		if board != cell.board or (board_definition != null and (cell.board_definition == null
			or board_definition.surface_id != cell.board_definition.surface_id)):
			return false
		var occupant: Plant000Base = cell.plant_in_cell.get(slot) # 只检查本次放置实际占用的槽。
		if not is_instance_valid(occupant) or occupant.is_queued_for_deletion():
			continue
		var expected := false
		for claim: Dictionary in claims:
			if claim["cell"] == cell and claim["plant"] == occupant:
				expected = true
				break
		if not expected:
			return false
	return true

## 返回本格可被咖啡豆唤醒的真实植物，普通层优先，伴生同样可成为目标。
func sleeping_plant() -> Plant000Base:
	for plant: Plant000Base in living_plants(): # 资格与实际唤醒使用同一集合和睡眠状态。
		if plant.is_sleeping:
			return plant
	return null

## 咖啡豆生效时重新确认睡眠目标，死亡或已清醒的植物不会收到重复唤醒。
func coffee_bean_awake_up() -> void:
	var target: Plant000Base = sleeping_plant() # 可能与种植时不同，沿用原版生效时查询语义。
	if target != null:
		target.coffee_bean_awake_up()

## 植物锚点始终由格子 Control 管理；只有稳定的 Node2D 内容容器挂入承托物。
## [param support] 底层承托植物，移动偏移使用其已有资源参数。
func _attach_support_layers(support: Plant000DownBase) -> void:
	assert(support != null)
	for slot: CharacterRegistry.PlacePlantInCell in _support_slot_anchors:
		var anchor: Control = _support_slot_anchors[slot]
		var content: Node2D = plant_container_node[slot]
		_reparent_plant_content(content, support.down_plant_container, true)
		content.global_position = anchor.global_position - support.plant_up_position

## 承托物死亡/铲除时恢复原锚点，避免缓存世界坐标造成跨行漂移。
func _detach_support_layers() -> void:
	for slot: CharacterRegistry.PlacePlantInCell in _support_slot_anchors:
		var anchor: Control = _support_slot_anchors[slot]
		var content: Node2D = plant_container_node[slot]
		_reparent_plant_content(content, anchor, false)
		content.position = Vector2.ZERO

## 将 [param content] 搬到 [param target]，按 [param keep_global] 保留世界变换；不重置植物动作进度。
## SpeedTimer 真实离树仍终止任务；同步换格和承托重挂恢复原活动任务。
func _reparent_plant_content(content: Node2D, target: Node, keep_global: bool) -> void:
	var clocks: Array[Dictionary] = [] # 原生秒数保留零速冻结时的剩余量，无需再次除以速度。
	for node: Node in content.find_children("*", "Timer", true, false): # 只捕获声明了离树停止的变速计时器。
		var timer := node as SpeedTimer # 普通Timer不改变其原有生命周期。
		if timer != null and not timer.is_stopped() and timer.time_left > 0.0:
			clocks.append({"timer": weakref(timer), "left": timer.time_left, "period": timer.wait_time,
				"speed": timer.speed_scale, "base": timer.base_wait_time})
	content.reparent(target, keep_global)
	for clock: Dictionary in clocks: # 某些迁移回调可能释放植物，恢复前逐个核验。
		var timer: SpeedTimer = clock["timer"].get_ref() as SpeedTimer # 弱引用不延长已经死亡的植物寿命。
		if not is_instance_valid(timer) or not timer.is_inside_tree() or timer.is_queued_for_deletion() \
				or not content.is_ancestor_of(timer) or not timer.is_stopped():
			continue
		var character := timer.owner as Character000Base # 死亡或退场不能被搬迁恢复旧动作。
		var component := timer.get_parent() as ComponentNormBase # 外部状态已禁用的生产或攻击继续保持停止。
		if (is_instance_valid(character) and (character.is_death or character.is_queued_for_deletion())) \
				or (component != null and not component.is_enabling) \
				or not is_equal_approx(timer.speed_scale, float(clock["speed"])) \
				or not is_equal_approx(timer.base_wait_time, float(clock["base"])):
			continue
		# 还原原生剩余时间后恢复完整周期，保留SpeedTimer内部倍率和手动暂停状态。
		timer.start(float(clock["left"]))
		timer.wait_time = float(clock["period"])

## 获取种植新植物时植物虚影的位置
func get_new_plant_static_shadow_global_position(place_plant_in_cell:CharacterRegistry.PlacePlantInCell):
	return plant_container_node[place_plant_in_cell].global_position

## 将 [param next_lane] 发布给本格占用和绘制层级，跨越行中线时才触发更新。
func update_combat_lane(next_lane: int) -> void:
	if next_lane < 0 or next_lane == combat_lane:
		return
	_projected_lane = next_lane
	z_index = next_lane * 50 + 10
	for plant: Plant000Base in living_plants(): # 多格植物只由真正持有其节点的种植点更新。
		if plant.plant_cell == self:
			plant.sync_combat_lane()

## Release cell ownership by actual occupant identity, not by exported scene ID.
## Shared-footprint plants notify every occupied cell but update global counts once.
func one_plant_free(plant: Plant000Base) -> void:
	var slots: Array[CharacterRegistry.PlacePlantInCell] = []
	for place: CharacterRegistry.PlacePlantInCell in plant_in_cell:
		if plant_in_cell[place] == plant:
			slots.append(place)
	if slots.is_empty():
		return
	if is_instance_valid(ladder):
		for place: CharacterRegistry.PlacePlantInCell in slots:
			if place in [CharacterRegistry.PlacePlantInCell.Down,
					CharacterRegistry.PlacePlantInCell.Norm,
					CharacterRegistry.PlacePlantInCell.Shell]:
				ladder.ladder_death()
				break
	if plant.plant_cell == self and slots.has(CharacterRegistry.PlacePlantInCell.Down):
		_detach_support_layers()
	for place: CharacterRegistry.PlacePlantInCell in slots:
		plant_in_cell[place] = null
	# 植物死亡释放同样从实际占用推导地形，无需对 8/16 等位进行异或翻转。
	_sync_support_terrain_condition()
	if slots.has(CharacterRegistry.PlacePlantInCell.Down):
		_clear_unsupported_companions()
	if plant.plant_cell == self:
		signal_plant_free.emit(self, plant.plant_type)
	if is_mouse_in_ui(button):
		await get_tree().process_frame
		_on_button_mouse_entered()

## 改变特殊状态(植物)
func update_special_state_plant(value:bool, change_specila_state:E_SpecialStatePlant):
	curr_special_state_plant[change_specila_state] = value
	_update_state_plant()

## 改变特殊状态(僵尸)
func update_special_state_zombie(value:bool, change_specila_state:E_SpecialStateZombie):
	curr_special_state_zombie[change_specila_state] = value
	_update_state_zombie()

## 更新状态
func _update_state_plant():
	##是否全为false(无特殊状态，可以种植)
	can_common_plant = is_terrain_planting_allowed() and curr_special_state_plant.values().all(func(v): return not v)
	##如果更新状态时鼠标在当前植物格子中，重新发射鼠标进入格子信号检测种植
	if is_mouse_in_ui(button):
		_on_button_mouse_entered()

## 更新状态
func _update_state_zombie():
	##是否全为false(无特殊状态，可以种植)
	can_common_zombie = curr_special_state_zombie.values().all(func(v): return not v)
	##如果更新状态时鼠标在当前植物格子中，重新发射鼠标进入格子信号检测种植
	if is_mouse_in_ui(button):
		_on_button_mouse_entered()

## 返回实际承托植物；正常种植与复生均占据同一个 Down 位置。
func get_support_plant() -> Plant000DownBase:
	var reference: Variant = plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Down) # 先检查失效节点引用。
	if not is_instance_valid(reference):
		return null
	var support: Plant000DownBase = reference as Plant000DownBase # 普通植物不能冒充承托层。
	return support if support != null and not support.is_death and not support.is_queued_for_deletion() else null

## 地形由底层槽位的实际占用推导，禁止在实例初始化或失败回滚时提前变更。
## 承托能力由 BoardTerrainDefinition 声明，新地形无需扩展这里的分支。
func _sync_support_terrain_condition() -> void:
	var support: Plant000DownBase = get_support_plant() # 承托查询与支援技能共享同一真实占用。
	if not is_instance_valid(support) or support.is_queued_for_deletion() \
			or board_terrain == null or board_terrain.supported_flags == 0:
		curr_condition = ori_condition
	else:
		curr_condition = board_terrain.supported_flags

#endregion

#region 蹦极僵尸偷植物
## 返回当前可偷取的第一层植物；选择目标与实际偷取共用此顺序，失效或死亡实例不参与。
func get_bungi_target() -> Plant000Base:
	var can_steal: Callable = func(plant: Plant000Base) -> bool: return not plant.battle_hidden_from_zombies # 主动偷取跳过隐蔽层。
	# 各种植层的偷取优先级；一次只取一株，不连带移除整格植物。
	for place in [
		CharacterRegistry.PlacePlantInCell.Norm,
		CharacterRegistry.PlacePlantInCell.Shell,
		CharacterRegistry.PlacePlantInCell.Down,
		CharacterRegistry.PlacePlantInCell.Float
	]:
		if place == CharacterRegistry.PlacePlantInCell.Down:
			var companion: Plant000Base = first_companion_plant(can_steal) # 伴生先于其下方的承托物被偷取。
			if companion != null:
				return companion
		# 先以 Variant 检查可能已释放的引用，再转换植物类型。
		var plant_reference: Variant = plant_in_cell[place]
		if not is_instance_valid(plant_reference):
			continue
		# 只有仍在场景中的存活植物才能成为偷取目标。
		var plant := plant_reference as Plant000Base
		if plant != null and plant.is_inside_tree() and not plant.is_queued_for_deletion() and not plant.is_death \
				and can_steal.call(plant):
			return plant
	return first_companion_plant(can_steal)


## 偷取当前有效植物并返回其表现复制体；目标消失时返回 null。
func be_bungi() -> Node2D:
	# 执行时重新读取格内植物，避免使用准备阶段已死亡的植物引用。
	var plant: Plant000Base = get_bungi_target()
	return plant.be_bungi() if plant != null else null
#endregion

#region 特殊状态
#region 墓碑相关
## 创建墓碑：默认保留一代版本，显式传入场景时使用新墓碑实体。
func create_tombstone(tombstone_scene: PackedScene = null) -> TombStone:
	if (board != null and not board.allows_mutation()) or is_instance_valid(tombstone):
		return null
	var prepared: TombStone = prepare_tombstone(tombstone_scene) # 失败在清除植物之前返回。
	if prepared == null:
		return null
	# 墓碑清除所有真实植物，伴生不会因缺少种植位而幸存。
	for reference: Variant in living_plants(): # 实体副本允许死亡回调释放占用。
		if not is_instance_valid(reference):
			continue
		var plant := reference as Plant000Base # 前一个死亡回调后重新确认当前引用。
		if is_instance_valid(plant) and not plant.is_death:
			plant.character_death()

	install_prepared_tombstone(prepared)
	return prepared

## 为本格离树构造墓碑；失败不清除植物，不更新障碍状态。
func prepare_tombstone(source: PackedScene = null) -> TombStone:
	var scene: PackedScene = source if source != null else SceneRegistry.TOMBSTONE # 原有实体模板。
	if scene == null or not scene.can_instantiate():
		return null
	var instance: Node = scene.instantiate() # 尚未进入战场的节点。
	if not instance is TombStone:
		if is_instance_valid(instance):
			instance.free()
		return null
	var result := instance as TombStone # 正式类型契约。
	result.init_tombstone(self)
	return result

## 普通生成与存档统一挂载 [param prepared]；恢复计划提前排除占用冲突。
func install_prepared_tombstone(prepared: TombStone) -> void:
	assert(prepared != null and prepared.plant_cell == self and prepared.get_parent() == null)
	tombstone = prepared
	tombstone.position = Vector2(size.x / 2, size.y)
	add_child(tombstone)
	update_special_state_plant(true, E_SpecialStatePlant.IsTombstone)
	Global.main_game.plant_cell_manager.tombstone_list.append(tombstone)

## 刪除墓碑，墓碑死亡时调用该函数
func tombstone_death_update_plant_cell_data():
	var removed: TombStone = tombstone # 保存死亡实例，不等待已释放引用。
	if not is_instance_valid(removed):
		return
	tombstone = null
	signal_cell_delete_tombstone.emit(self, removed)
	Global.main_game.plant_cell_manager.tombstone_list.erase(removed)
	await get_tree().process_frame
	if not is_instance_valid(tombstone):
		update_special_state_plant(false, E_SpecialStatePlant.IsTombstone)


#endregion

#region 坑洞相关
## 按背景和格子地形创建毁灭菇坑洞并清空同格植物。
## 先禁种，避免死亡回调刷新种植虚影时短暂允许种植。
func create_crater():
	update_special_state_plant(true, E_SpecialStatePlant.IsCrater)
	_clear_plants_for_crater()

	self.crater = SceneRegistry.DOOM_SHROOM_CRATER.instantiate()
	add_child(crater)
	crater.init_crater(_get_crater_type(), self)


## 根据实际背景与原始格子地形返回坑洞图片组索引，不受睡莲或花盆改变种植条件的影响。[br]
## 0/1 为陆地白天/黑夜，2/3 为水池白天/黑夜，4/5 为屋顶平面/斜面。[br]
## 屋顶按实际地面高度判断斜面，不再依赖标准九列的固定列号。
func _get_crater_type() -> int:
	var night: bool = Global.main_game.game_para.game_BG in [ # 美术明暗使用环境表现，不改蘑菇睡眠规则。
		ConstLevelData.GameBg.FrontNight, ConstLevelData.GameBg.Fog, ConstLevelData.GameBg.RoofNight]
	match plant_cell_type:
		PlantCellType.Pool:
			return 3 if night else 2
		PlantCellType.Roof:
			return 5 if not is_zero_approx(get_ground_height()) else 4
	return 1 if night else 0



## 清空坑洞所在格子的各层植物，不触发连带亡语；底层植物最后死亡以恢复地形和容器结构。
## 已死亡或等待释放的实例不重复结算，毁灭菇自身由原来的死亡流程释放。
func _clear_plants_for_crater() -> void:
	# 保存各层植物引用，避免死亡回调修改格子数据后影响本次清理目标。
	var plants_to_clear: Dictionary = plant_in_cell.duplicate()
	for reference: Variant in _companion_plants.values(): # 伴生先于承托层清理，保留其正常死亡通知。
		if not is_instance_valid(reference):
			continue
		var companion := reference as Plant000Base # 死亡回调可能移除后续候选。
		if not companion.is_death and not companion.is_queued_for_deletion():
			companion.is_can_death_language = false
			companion.character_death_disappear()
	# 当前清理的种植层；底层植物最后处理，模仿者层不存在时会被跳过。
	for place: CharacterRegistry.PlacePlantInCell in [
		CharacterRegistry.PlacePlantInCell.Norm,
		CharacterRegistry.PlacePlantInCell.Shell,
		CharacterRegistry.PlacePlantInCell.Float,
		CharacterRegistry.PlacePlantInCell.Imitater,
		CharacterRegistry.PlacePlantInCell.Down
	]:
		# 先检查原始引用，前一个植物的死亡回调可能已经释放后续目标。
		var plant_reference: Variant = plants_to_clear.get(place)
		if not is_instance_valid(plant_reference):
			continue
		# 有效的待清理植物；正在执行亡语的毁灭菇尚未排队释放，但已经标记死亡。
		var plant := plant_reference as Plant000Base
		if plant == null or plant.is_death or plant.is_queued_for_deletion():
			continue

		plant.is_can_death_language = false
		# 沿用死亡通知、数量更新和底层植物地形恢复，不直接释放节点。
		plant.character_death_disappear()
		# 只清空仍指向原目标的种植层，避免覆盖死亡回调新写入的植物引用。
		if plant_in_cell.get(place) == plant_reference:
			plant_in_cell[place] = null

## 坑洞调用该函数，坑洞是自己消失后调用该函数
func delete_crater_update_plant_cell_data():
	update_special_state_plant(false, E_SpecialStatePlant.IsCrater)

#endregion

#region 冰道相关
func add_new_ice_road(new_ice_road:IceRoad):
	curr_ice_roads.append(new_ice_road)
	update_special_state_plant(true, E_SpecialStatePlant.IsIceRoad)
	new_ice_road.signal_ice_road_disappear.connect(del_new_ice_road_update_plant_cell_data.bind(new_ice_road))

## 删除冰道
func del_new_ice_road_update_plant_cell_data(new_ice_road):
	curr_ice_roads.erase(new_ice_road)
	if curr_ice_roads.is_empty():
		update_special_state_plant(false, E_SpecialStatePlant.IsIceRoad)

#endregion

#region 保龄球种植限制
## 设置保龄球不能种植
func set_bowling_no_plant():
	update_special_state_plant(true, E_SpecialStatePlant.IsNoPlantBowling)

## 设置保龄球不能僵尸
func set_bowling_no_zombie():
	update_special_state_zombie(true, E_SpecialStateZombie.IsNoPlantBowling)
#endregion

#region 罐子
var pot:ScaryPot
const SCARY_POT = preload("uid://bfhjvru3xr23t")

## 生成一个罐子
func create_pot(pot_para:Dictionary) -> ScaryPot:
	if is_instance_valid(pot):
		return
	pot = SCARY_POT.instantiate()
	pot.init_pot(pot_para)
	add_child(pot)
	pot.position = Vector2(size.x / 2, size.y)

	update_special_state_plant(true, E_SpecialStatePlant.IsPot)

	return pot

## 打开罐子后更新数据
func open_pot_update_plant_cell_data():
	update_special_state_plant(false, E_SpecialStatePlant.IsPot)
#endregion

#endregion

#region 鼠标交互相关
func _on_button_pressed() -> void:
	click_cell.emit(self)

func _on_button_mouse_entered() -> void:
	cell_mouse_enter.emit(self)

func _on_button_mouse_exited() -> void:
	cell_mouse_exit.emit(self)


func is_mouse_in_ui(control_node: Control) -> bool:
	return control_node.get_rect().has_point(BattleEnvironmentLens.mouse_position(control_node, false))

## 返回当前被铲子威胁的植物
func return_plant_be_shovel_look():
	## 如果当前格子有植物,根据位置选择植物，若位置没有植物，选择别的植物
	if get_curr_plant_num() > 0:
		var plant_place_be_shovel = get_plant_place_from_mouse_pos()
		return return_plant_null_res(plant_place_be_shovel)
	else:
		return null

## 按 [param plant_place_be_shovel] 优先查找普通层，再查伴生；[param _is_loop] 兼容旧调用。
## 使用有限顺序，避免只有伴生植物时在空的普通层间无限递归。
func return_plant_null_res(plant_place_be_shovel: CharacterRegistry.PlacePlantInCell, _is_loop := false):
	var slots: Array = [] # 按鼠标高度保留原有普通层优先级。
	match plant_place_be_shovel:
		CharacterRegistry.PlacePlantInCell.Norm:
			slots = [CharacterRegistry.PlacePlantInCell.Norm, CharacterRegistry.PlacePlantInCell.Shell,
				CharacterRegistry.PlacePlantInCell.Down, CharacterRegistry.PlacePlantInCell.Float]
		CharacterRegistry.PlacePlantInCell.Shell:
			slots = [CharacterRegistry.PlacePlantInCell.Shell, CharacterRegistry.PlacePlantInCell.Norm,
				CharacterRegistry.PlacePlantInCell.Down, CharacterRegistry.PlacePlantInCell.Float]
		CharacterRegistry.PlacePlantInCell.Float:
			slots = [CharacterRegistry.PlacePlantInCell.Float, CharacterRegistry.PlacePlantInCell.Norm,
				CharacterRegistry.PlacePlantInCell.Shell, CharacterRegistry.PlacePlantInCell.Down]
		_:
			slots = [CharacterRegistry.PlacePlantInCell.Down, CharacterRegistry.PlacePlantInCell.Float,
				CharacterRegistry.PlacePlantInCell.Norm, CharacterRegistry.PlacePlantInCell.Shell]
	for slot: CharacterRegistry.PlacePlantInCell in slots: # 普通层仍可准确单独铲除。
		if slot == CharacterRegistry.PlacePlantInCell.Down and plant_place_be_shovel != slot:
			var companion: Plant000Base = first_companion_plant() # 中上部点击优先选中承托物上方的伴生。
			if companion != null:
				return companion
		var plant: Plant000Base = plant_in_cell.get(slot) # 当前优先层的真实占用。
		if is_instance_valid(plant) and not plant.is_death and not plant.is_queued_for_deletion():
			return plant
	return first_companion_plant()

## 铲子进入该shell时，判断当前格子是否有多个植物,蹦极僵尸判断是否有植物
## 有多个植物时，会随鼠标移动更新当前被铲子看的植物
func get_curr_plant_num()->int:
	return plant_entities().size()

## 鼠标移动检测
#func _input(event):
	#if event is InputEventMouseMotion:
		#_check_mouse_panel_region(event.position)
#
## 根据鼠标在当前格子中的位置，返回应该被铲除的植物
func get_plant_place_from_mouse_pos():
	var local_pos: Vector2 = BattleEnvironmentLens.mouse_position(button, false) # 铲除层位与变形后看到的位置一致。
	var height = button.size.y
	if local_pos.y < height / 3:
		return CharacterRegistry.PlacePlantInCell.Float
	elif local_pos.y < height * 2 / 3:
		return CharacterRegistry.PlacePlantInCell.Norm
	else:
		return CharacterRegistry.PlacePlantInCell.Shell

#endregion

#region 梯子
## 被挂载梯子
## global_pos:挂载梯子精灵节点的全局位置
func be_ladder(tier_id: StringName = &"", target: Plant000Base = null) -> Ladder:
	if (board != null and not board.allows_mutation()) or is_instance_valid(ladder):
		return null
	var prepared: Ladder = prepare_ladder() # 同一构造边界用于读档预留。
	if prepared == null:
		return null
	install_prepared_ladder(prepared, tier_id, target)
	return prepared

## 梯子消失
func ladder_loss(source: Ladder = null):
	if source == null or ladder == source:
		ladder = null
	for p in plant_in_cell:
		if is_instance_valid(plant_in_cell[p]):
			plant_in_cell[p].signal_ladder_update.emit()


## 获取当前植物格子可以挂载梯子的植物
func get_plant_ladder() -> Plant000Base:
	## 如果有壳类植物
	if is_instance_valid(plant_in_cell[CharacterRegistry.PlacePlantInCell.Shell]):
		return plant_in_cell[CharacterRegistry.PlacePlantInCell.Shell]
	## 如果Norm植物
	if is_instance_valid(plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm]) and plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm].is_can_ladder:
		return plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm]

	return null


#endregion


## 获取周围一圈(包括本身格子)的某个植物
func get_plant_surrounding(p_t:CharacterRegistry.PlantType) -> Array[Plant000Base]:
	var result: Array[Plant000Base] = [] # 按实际占用去重。
	var condition: ResourcePlantCondition = Global.character_registry.get_plant_info(p_t,
		CharacterRegistry.PlantInfoAttribute.PlantConditionResource) # 物种占用层。
	for cell: PlantCell in get_plant_cell_surrounding(): # 同一空间查询用于所有邻接技能。
		var plant: Plant000Base = cell.plant_in_cell.get(condition.place_plant_in_cell) # 实际占用。
		if is_instance_valid(plant) and plant.plant_type == p_t and not result.has(plant):
			result.append(plant)
	return result


## 获取周围一圈的植物格子，包括本身
func get_plant_cell_surrounding() -> Array[PlantCell]:
	return board.neighbors(self) if board != null else [self]


#region 存档
## 植物格子存档
func get_save_game_data_plant_cell() -> ResourceSaveGamePlantCell:
	var save_game_data_plant_cell:ResourceSaveGamePlantCell = ResourceSaveGamePlantCell.new()
	save_game_data_plant_cell.cell_id = cell_id
	save_game_data_plant_cell.row_col = row_col
	for place_plant_in_cell in plant_in_cell:
		var plant: Plant000Base = plant_in_cell[place_plant_in_cell]
		# Shared-footprint instances have exactly one save authority: origin cell.
		if is_instance_valid(plant) and not plant.is_queued_for_deletion() \
				and plant.plant_cell == self:
			save_game_data_plant_cell.plant_type_in_cell[place_plant_in_cell] = \
				plant.gat_save_game_data_plant()

	if is_instance_valid(ladder):
		save_game_data_plant_cell.is_ladder = true
		save_game_data_plant_cell.ladder_tier_id = ladder.adventure_tier_id

	return save_game_data_plant_cell

## 整体读档由 BoardRestoreTransaction 统一准备，禁止逐格解码后立即写入。
## 清除当前植物格子数据
func clear_data_plant_cell():
	PlantRevivalArchive.clear(self)
	var clearing: Array[Plant000Base] = living_plants() # 先标记全部目标，承托死亡连带清理也不会伪造尸体。
	for plant: Plant000Base in clearing:
		plant.death_recording_enabled = false
	for reference: Variant in clearing: # 清场也覆盖不占位实体，死亡回调只移除自己的记录。
		if not is_instance_valid(reference):
			continue
		var plant := reference as Plant000Base # 前一个死亡回调后重新确认当前引用。
		if is_instance_valid(plant) and not plant.is_death:
			plant.character_death_disappear()


# 已移除逐条吞错恢复路径；植物创建仍由上方共享放置事务负责。
#endregion


## [param point] 为格子局部像素坐标；命中几何同时供按钮和移动拾取使用。
func contains_local_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	return board_definition == null or board_definition.hit_polygon.is_empty() \
		or Geometry2D.is_point_in_polygon(point, board_definition.hit_polygon)

## 即时转换 [param point] 的世界坐标，不保存运动前的矩形。
func contains_world_point(point: Vector2) -> bool:
	return contains_local_point(get_global_transform().affine_inverse() * point)

## 原始种植锚点即时查询；[param slot] 不包含承托物的动画偏移。
func get_slot_anchor_global_position(slot: CharacterRegistry.PlacePlantInCell) -> Vector2:
	var anchor: CanvasItem = _support_slot_anchors.get(slot, plant_container_node.get(slot)) # 固定于格子的锚点。
	return anchor.get_global_transform().origin if is_instance_valid(anchor) else global_position

## 自定义坐标的 Y 值不是坡面高度；只应用声明的检测高度。
func get_ground_height() -> float:
	return position.y if legacy_ground_height or board_definition == null else board_definition.ground_height

## 将各层锚点平移到显式地面脚点，保留承托层与普通层的固有相对高度。
func update_ground_anchors() -> void:
	var shift: float = 0.0 # 无显式脚点时恢复场景默认锚点。
	if board_definition != null and board_definition.ground_anchor_y >= 0.0:
		shift = board_definition.ground_anchor_y - (size.y - _default_plant_inset)
	var delta_y: float = shift - _ground_anchor_shift # 只应用变化量，防止阶段复用时重复偏移。
	if is_zero_approx(delta_y):
		return
	_ground_anchor_shift = shift
	for anchor: Control in [$PlantNormContainer, $PlantShellContainer, $PlantFloatContainer,
			$PlantDownContainer, $PlantImitaterContainer, plant_area_2d_position]: # 保持所有层和定位标记同向移动。
		anchor.offset_top += delta_y
		anchor.offset_bottom += delta_y

## 仅包含地形固有限制和具名来源；墓碑吞噬者等仍可按原规则处理障碍。
func is_terrain_planting_allowed() -> bool:
	return not has_planting_block() and (board_terrain == null or not board_terrain.blocks_planting)

## 具名禁种来源阻止所有放置事务，保留已占据各层的活株。
func has_planting_block() -> bool:
	return not _planting_blocks.is_empty()

## 按 [param source] 独立开关禁种；撤销一个来源不能清除其他地形效果。
func set_planting_block(source: StringName, blocked: bool) -> void:
	if source == &"":
		return
	if blocked:
		_planting_blocks[source] = true
	else:
		_planting_blocks.erase(source)
	_update_state_plant()

## 安装 [param terrain] 的能力和独立行为；失败保留原地形。
func apply_board_terrain(terrain: BoardTerrainDefinition) -> bool:
	if board != null and not board.allows_mutation():
		return false
	var prepared: BoardTerrainLayer = BoardTerrainLayer.prepare(self, terrain) # 先构造全部资源。
	if prepared == null:
		return false
	install_prepared_terrain(prepared)
	return true

## 返回当前地形行为的可序列化状态。
func capture_terrain_state() -> Dictionary:
	return _terrain_layer.behavior.capture_state() if _terrain_layer != null \
		and is_instance_valid(_terrain_layer.behavior) else {}

## 恢复已由空间存档预检的 [param state]，不重新执行种植。
func restore_terrain_state(state: Dictionary) -> void:
	if _terrain_layer != null and is_instance_valid(_terrain_layer.behavior):
		_terrain_layer.behavior.restore_state(state)


## 格子自身的水陆生成条件；与固定攻击行是否允许该物种分开判断。
func get_spawn_terrain_type() -> CharacterRegistry.ZombieRowType:
	if board_terrain != null:
		return board_terrain.spawn_type
	return CharacterRegistry.ZombieRowType.Pool if plant_cell_type == PlantCellType.Pool \
		else CharacterRegistry.ZombieRowType.Land



## 当前种植点的僵尸/墓碑生成基线；斜坡在角色入场时再应用一次表现高度。
func get_spawn_global_position() -> Vector2:
	if board != null and board.definition != null:
		var foot_y: float = size.y if board_definition.ground_anchor_y < 0.0 else board_definition.ground_anchor_y # 未声明脚点时沿用格底。
		return get_global_transform() * Vector2(size.x * 0.5, foot_y - get_ground_height())
	var game: MainGameManager = Global.main_game # 旧固定行出生坐标协议。
	return Vector2(global_position.x + size.x * 0.5,
		game.zombie_manager.all_zombie_rows[row_col.x].zombie_create_position.global_position.y)


## 仅安装已准备好的 [param layer]；资源构造与校验必须发生在旧层释放之前。
func install_prepared_terrain(layer: BoardTerrainLayer) -> void:
	assert(layer != null and layer.cell == self and layer.get_parent() == null)
	if is_instance_valid(_terrain_layer):
		remove_child(_terrain_layer)
		_terrain_layer.queue_free()
	_terrain_layer = layer
	board_terrain = layer.terrain
	plant_cell_type = board_terrain.presentation_kind as PlantCellType
	init_condition()
	add_child(layer)
	layer.restore_prepared_state()


## 离树准备梯子；初始化对植物的影响留到正式提交，失败不产生负面效果。
func prepare_ladder() -> Ladder:
	if SceneRegistry.LADDER == null or not SceneRegistry.LADDER.can_instantiate():
		return null
	var instance: Node = SceneRegistry.LADDER.instantiate() # 未接入战场的梯子。
	if not instance is Ladder:
		if is_instance_valid(instance):
			instance.free()
		return null
	return instance as Ladder

## 挂载已构造的 [param prepared] 并沿用原梯子初始化/通知协议。
func install_prepared_ladder(prepared: Ladder, tier_id: StringName, target: Plant000Base = null) -> void:
	assert(prepared != null and prepared.get_parent() == null)
	ladder = prepared
	ladder.init_ladder(self, tier_id, target)
	add_child(ladder)
	for slot: CharacterRegistry.PlacePlantInCell in plant_in_cell: # 通知实际在场植物。
		if is_instance_valid(plant_in_cell[slot]):
			plant_in_cell[slot].signal_ladder_update.emit()
