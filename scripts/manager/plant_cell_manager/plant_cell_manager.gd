extends MainGameSubManager
class_name PlantCellManager

@onready var plant_cells_root: Node2D = %PlantCellsRoot
@onready var tomb_stone_manager: TombStoneManager = $TombStoneManager

## 当前战场的唯一空间状态，管理器不再构造或维护另一份网格。
var board: BoardRuntime:
	get:
		return main_game.board if is_instance_valid(main_game) else null
## 兼容旧枚举消费者的只读行视图；稀疏地址必须使用 board.cell_at。
var all_plant_cells: Array[Array]:
	get:
		return board.rows() if board != null else []
## 逻辑地址边界，不等同于实际地块数量。
var row_col: Vector2i:
	get:
		return board.extent if board != null else Vector2i.ZERO
## TombStoneManager(PlantCellManager子节点)初始化
## 生成的墓碑列表(一维)
var tombstone_list :Array[TombStone] = []
## 当前植物种植的信息[植物种类:植物数量]
var curr_plant_num:Dictionary[CharacterRegistry.PlantType, int]
## 当前罐子数量
var curr_pot_num = 0

## 我是僵尸模式的随机植物生成池
var plant_random_pool_on_zombie_mode:RandomPicker
## 我是僵尸模式下所有创建植物的植物格子
var all_plant_cells_create_plant_on_zombie_mode:Array[PlantCell] = []
## 我是僵尸模式必须先生成的植物
var all_must_plants_on_zombie_mode:Dictionary[CharacterRegistry.PlantType, int] = {}


func _ready() -> void:
	## 火爆辣椒爆炸特效
	EventBus.subscribe("jalapeno_bomb_effect", jalapeno_bomb_effect)
	## 火爆辣椒销毁道具[冰道和梯子]
	EventBus.subscribe("jalapeno_bomb_item_lane", jalapeno_bomb_item_lane)

	if board == null or not board.configured:
		return
	for cell: PlantCell in board.cells(): # 空间已装配，只连接种植统计，不改布局身份。
		cell.signal_plant_create.connect(update_plant_info_create)
		cell.signal_plant_free.connect(update_plant_info_free)


#region 植物信息
## 更新植物信息(创建新植物)
func update_plant_info_create(_plant_cell:PlantCell, plant_type:CharacterRegistry.PlantType):
	if board != null and not board.allows_mutation():
		return # 恢复事务已按完整占用重建计数，发布阶段不得再次累计。
	curr_plant_num[plant_type] = curr_plant_num.get(plant_type, 0) + 1
	EventBus.push_event("update_card_purple_sun_cost")

## 更新植物信息(植物死亡)
func update_plant_info_free(_plant_cell:PlantCell, plant_type:CharacterRegistry.PlantType):
	if board != null and not board.allows_mutation():
		return # 同步恢复期间的统计统一在提交结束前派生。
	curr_plant_num[plant_type] -= 1
	EventBus.push_event("update_card_purple_sun_cost")
	if curr_plant_num[plant_type] < 0:
		printerr(plant_type, ":该植物类型数量小于0")
#endregion

func init_manager() -> void:
	signal_connect_plant_cell_with_hand_manager(main_game.hand_manager)
	tomb_stone_manager.init_tomb_stone_manager(game_para)
	## 没有存档直接创建植物和创建罐子
	if not Global.main_game.is_save_game_data_on_init:
		create_pre_plant()
		init_pot()
		cerate_pot()
		if game_para.is_zombie_mode:
			init_plant_on_zombie_mode()
			create_plant_on_zombie_mode()

	## 有存档初始化罐子数据 我是僵尸数据
	else:
		init_pot()
		if game_para.is_zombie_mode:
			init_plant_on_zombie_mode()

## plant_cell与hand_manager信号连接
func signal_connect_plant_cell_with_hand_manager(hand_manager:HandManager):
	## 植物种植区域信号
	for plant_cells_row in all_plant_cells:
		for plant_cell in plant_cells_row:
			plant_cell = plant_cell as PlantCell
			plant_cell.click_cell.connect(hand_manager._on_click_cell)
			plant_cell.cell_mouse_enter.connect(hand_manager._on_cell_mouse_enter)
			plant_cell.cell_mouse_exit.connect(hand_manager._on_cell_mouse_exit)


## 预种植植物数据
func create_pre_plant():
	for data: PrePlantResource in game_para.all_pre_plant_data: # 预种植指令，无副作用地选择实际格子。
		if data == null:
			continue
		if data.cell_id != &"":
			var target: PlantCell = board.cell_by_id(data.cell_id) # 稳定身份优先，不回退错误坐标。
			if target != null:
				plant_cell_pre_plant(target, data.plant_type, data.is_imitater_plant, game_para.is_zombie_mode)
			else:
				push_error("预种植引用未知地块：%s" % data.cell_id)
			continue
		if data.plant_cell_pos.x < 0 or data.plant_cell_pos.y < 0:
			continue
		for cell: PlantCell in board.cells(): # 旧 1 起点/0 通配语义不变，缺格不参与。
			if (data.plant_cell_pos.x == 0 or data.plant_cell_pos.x == cell.row_col.x + 1) \
				and (data.plant_cell_pos.y == 0 or data.plant_cell_pos.y == cell.row_col.y + 1):
				plant_cell_pre_plant(cell, data.plant_type, data.is_imitater_plant, game_para.is_zombie_mode)


## 始化我是僵尸模式的植物数据
func init_plant_on_zombie_mode():
	all_must_plants_on_zombie_mode = game_para.all_must_plants_on_zombie_mode
	var plant_random_pool_on_zombie_mode_data := []
	for plant_type in game_para.all_plants_weight_on_zombie_mode.keys():
		plant_random_pool_on_zombie_mode_data.append([plant_type, game_para.all_plants_weight_on_zombie_mode[plant_type]])
	plant_random_pool_on_zombie_mode = RandomPicker.new(plant_random_pool_on_zombie_mode_data)
	all_plant_cells_create_plant_on_zombie_mode.clear()

	for cell: PlantCell in board.cells(): # 按实际逻辑列过滤，不把稀疏行压缩成数组列。
		if cell.row_col.y < game_para.plant_col_on_zombie_mode:
			all_plant_cells_create_plant_on_zombie_mode.append(cell)

## 创建我是僵尸模式的植物
func create_plant_on_zombie_mode():
	var all_plant_cells_create_plant_on_zombie_mode_copy = all_plant_cells_create_plant_on_zombie_mode.duplicate(true)
	all_plant_cells_create_plant_on_zombie_mode_copy.shuffle()
	for plant_type in all_must_plants_on_zombie_mode.keys():
		## 当前种类植物的个数
		for i in range(all_must_plants_on_zombie_mode[plant_type]):
			## 如果已经全都种植过了
			if all_plant_cells_create_plant_on_zombie_mode_copy.is_empty():
				print("warning: 我是僵尸模式当前选择列数已被必种植植物种植满")
				continue
			var plant_cell:PlantCell = all_plant_cells_create_plant_on_zombie_mode_copy.pop_back()
			plant_cell_pre_plant(plant_cell, plant_type, false, true)
	for plant_cell:PlantCell in all_plant_cells_create_plant_on_zombie_mode_copy:
		var plant_type:CharacterRegistry.PlantType = plant_random_pool_on_zombie_mode.get_random_item()
		plant_cell_pre_plant(plant_cell, plant_type, false, true)


#region 罐子
## 是否为罐子模式
var is_pot_mode := false
## 对罐子需求的植物格子僵尸行类型分成两组，水、路两种类型 根据罐子总数需求列数计算
var plant_cell_row_on_zombie_row_type:Dictionary[CharacterRegistry.ZombieRowType, Array] = {
	CharacterRegistry.ZombieRowType.Land:[],
	CharacterRegistry.ZombieRowType.Pool:[],
}

func init_pot():
	is_pot_mode = game_para.is_pot_mode
	match game_para.pot_mode:
		ConstLevelData.E_PotMode.Weight:
			init_pot_random_pool()
			init_plant_cell_row_on_zombie_row_type()
		ConstLevelData.E_PotMode.Fixd:
			init_plant_cell_row_on_zombie_row_type()

func cerate_pot():
	match game_para.pot_mode:
		ConstLevelData.E_PotMode.Weight:
			create_all_pot_on_weigth_mode()
		ConstLevelData.E_PotMode.Fixd:
			create_all_pot_on_fixed_mode()

## 将需求的植物格子按僵尸行类型分类
func init_plant_cell_row_on_zombie_row_type():
	plant_cell_row_on_zombie_row_type[CharacterRegistry.ZombieRowType.Land].clear()
	plant_cell_row_on_zombie_row_type[CharacterRegistry.ZombieRowType.Pool].clear()
	var candidate_count: int = 0 # 只计真实种植点，不能以行数乘列数估算。
	for cell: PlantCell in board.cells(): # 局部水陆能力独立于整行生成能力。
		if cell.row_col.y >= game_para.pot_col_range.x and cell.row_col.y < game_para.pot_col_range.y:
			plant_cell_row_on_zombie_row_type[cell.get_spawn_terrain_type()].append(cell)
			candidate_count += 1
	if game_para.pot_mode == ConstLevelData.E_PotMode.Fixd:
		assert(game_para.pot_num_on_fixed_mode <= candidate_count, "罐子需求超过实际种植点数量。")



#region 权重模式
## 罐子生成植物随机池
var pot_plant_random_pool:RandomPicker
## 罐子生成陆地僵尸随机池
var pot_zombie_random_pool:Dictionary[CharacterRegistry.ZombieRowType, RandomPicker] = {
	CharacterRegistry.ZombieRowType.Land : null,
	CharacterRegistry.ZombieRowType.Pool : null,
}

## 初始化罐子随机池
func init_pot_random_pool():
	print("初始化罐子随机池")
	print("罐子植物候选列表：", game_para.candidate_plant_pot)
	print("罐子僵尸候选列表：", game_para.candidate_zombie_pot_with_zombie_row_type)
	var pot_plant_random_pool_data = []
	for plant_type in game_para.candidate_plant_pot:
		pot_plant_random_pool_data.append([plant_type, game_para.candidate_plant_pot[plant_type]])
	pot_plant_random_pool = RandomPicker.new(pot_plant_random_pool_data)


	var pot_zombie_land_random_pool_data = []
	for zombie_type in game_para.candidate_zombie_pot_with_zombie_row_type[CharacterRegistry.ZombieRowType.Land]:
		pot_zombie_land_random_pool_data.append([zombie_type, game_para.candidate_zombie_pot_with_zombie_row_type[CharacterRegistry.ZombieRowType.Land][zombie_type]])
	pot_zombie_random_pool[CharacterRegistry.ZombieRowType.Land] = RandomPicker.new(pot_zombie_land_random_pool_data)

	var pot_zombie_pool_random_pool_data = []
	for zombie_type in game_para.candidate_zombie_pot_with_zombie_row_type[CharacterRegistry.ZombieRowType.Pool]:
		pot_zombie_pool_random_pool_data.append([zombie_type, game_para.candidate_zombie_pot_with_zombie_row_type[CharacterRegistry.ZombieRowType.Pool][zombie_type]])
	pot_zombie_random_pool[CharacterRegistry.ZombieRowType.Pool] = RandomPicker.new(pot_zombie_pool_random_pool_data)

## 权重模式 生成所有罐子
func create_all_pot_on_weigth_mode():
	var plant_cell_row_on_zombie_row_type_copy = plant_cell_row_on_zombie_row_type.duplicate(true)
	## 先对僵尸陆地和水路罐子划分
	for zombie_row_type in [CharacterRegistry.ZombieRowType.Land,CharacterRegistry.ZombieRowType.Pool]:
		for plant_cell:PlantCell in plant_cell_row_on_zombie_row_type_copy[zombie_row_type]:
			plant_cell_create_pot_on_weigth_mode(plant_cell)

## 权重模式 植物格子创建罐子
func plant_cell_create_pot_on_weigth_mode(plant_cell:PlantCell, ):
	var pot_para:Dictionary = get_pot_para_on_weight_mode(plant_cell)
	plant_cell_creat_pot(plant_cell, pot_para)

## 权重模式 获取罐子参数
func get_pot_para_on_weight_mode(plant_cell:PlantCell) -> Dictionary:
	var pot_para:Dictionary = {}
	pot_para[ScaryPot.E_PotInitParaAttr.PlantCell] = plant_cell
	## 罐子类型：随机、植物、僵尸
	pot_para[ScaryPot.E_PotInitParaAttr.PotType] = get_weighted_result(game_para.weight_pot_type, game_para.weight_pot_type_sum) as ScaryPot.E_PotType
	## 是否为固定结果罐子
	var p_res_fixed := randf()
	## 固定结果罐子
	if p_res_fixed < game_para.weight_res_fiexd:
		pot_para[ScaryPot.E_PotInitParaAttr.IsFixedRes] = true
		match pot_para[ScaryPot.E_PotInitParaAttr.PotType]:
			ScaryPot.E_PotType.Random:
				var p_is_plant_or_zombie := randf()
				if p_is_plant_or_zombie <= 0.5:
					pot_para[ScaryPot.E_PotInitParaAttr.PlantType] = pot_plant_random_pool.get_random_item()
				else:
					var curr_zomebi_row_type:CharacterRegistry.ZombieRowType = plant_cell.get_spawn_terrain_type()
					pot_para[ScaryPot.E_PotInitParaAttr.ZombieType] = pot_zombie_random_pool[curr_zomebi_row_type].get_random_item()
			ScaryPot.E_PotType.Plant:
				pot_para[ScaryPot.E_PotInitParaAttr.PlantType] =pot_plant_random_pool.get_random_item()
			ScaryPot.E_PotType.Zombie:
				var curr_zomebi_row_type:CharacterRegistry.ZombieRowType = plant_cell.get_spawn_terrain_type()
				pot_para[ScaryPot.E_PotInitParaAttr.ZombieType] = pot_zombie_random_pool[curr_zomebi_row_type].get_random_item()
	else:
		pot_para[ScaryPot.E_PotInitParaAttr.IsFixedRes] = false

	return pot_para

func get_weighted_result(weight: Vector3i, weight_sum:int) -> int:
	var r = randi_range(1, weight_sum)
	if r <= weight.x:
		return 0
	elif r <= weight.x + weight.y:
		return 1
	else:
		return 2
#endregion

#region 固定模式
## 固定模式创建所有的罐子
func create_all_pot_on_fixed_mode():
	var plant_cell_row_on_zombie_row_type_copy = plant_cell_row_on_zombie_row_type.duplicate(true)
	## 先对僵尸陆地和水路罐子划分创建僵尸罐子，先创建对僵尸行类型有要求的罐子
	for zombie_row_type in [CharacterRegistry.ZombieRowType.Land,CharacterRegistry.ZombieRowType.Pool]:
		## 先打乱植物格子顺序
		plant_cell_row_on_zombie_row_type_copy[zombie_row_type].shuffle()
		plant_cell_row_on_zombie_row_type_copy[zombie_row_type] = create_multi_zombie_pot(game_para.random_pot_zombie_with_zombie_row_type[zombie_row_type], plant_cell_row_on_zombie_row_type_copy[zombie_row_type], ScaryPot.E_PotType.Random)
		plant_cell_row_on_zombie_row_type_copy[zombie_row_type] = create_multi_zombie_pot(game_para.zombie_pot_with_zombie_row_type[zombie_row_type], plant_cell_row_on_zombie_row_type_copy[zombie_row_type], ScaryPot.E_PotType.Zombie)
	## 将剩余的植物格子放到一起
	var plant_cell_remaining:Array = []
	plant_cell_remaining.append_array(plant_cell_row_on_zombie_row_type_copy[CharacterRegistry.ZombieRowType.Land])
	plant_cell_remaining.append_array(plant_cell_row_on_zombie_row_type_copy[CharacterRegistry.ZombieRowType.Pool])
	## 打乱植物格子顺序
	plant_cell_remaining.shuffle()
	## 创建 both僵尸行类型的僵尸罐子
	plant_cell_remaining = create_multi_zombie_pot(game_para.random_pot_zombie_with_zombie_row_type[CharacterRegistry.ZombieRowType.Both], plant_cell_remaining, ScaryPot.E_PotType.Random)
	plant_cell_remaining = create_multi_zombie_pot(game_para.zombie_pot_with_zombie_row_type[CharacterRegistry.ZombieRowType.Both], plant_cell_remaining, ScaryPot.E_PotType.Zombie)

	plant_cell_remaining = create_multi_plant_pot(game_para.random_pot_plant, plant_cell_remaining, ScaryPot.E_PotType.Random)
	plant_cell_remaining = create_multi_plant_pot(game_para.plant_pot, plant_cell_remaining, ScaryPot.E_PotType.Plant)

	print("当前已经生成的罐子数量:", curr_pot_num)
	print("结果固定罐子生成完成后剩余植物格子数量：", plant_cell_remaining.size())

	## 随机罐子数量和
	var random_pot_num_sum = game_para.random_pot_num_on_fixed_mode.x + game_para.random_pot_num_on_fixed_mode.y + game_para.random_pot_num_on_fixed_mode.z
	print("还需生成结果随机罐子数量(随机、植物、僵尸)：", random_pot_num_sum)
	## 打乱顺序
	plant_cell_remaining.shuffle()

	for i in range(game_para.random_pot_num_on_fixed_mode.x):
		create_random_res_pot(plant_cell_remaining.pop_back(), ScaryPot.E_PotType.Random)

	for i in range(game_para.random_pot_num_on_fixed_mode.y):
		create_random_res_pot(plant_cell_remaining.pop_back(), ScaryPot.E_PotType.Plant)

	for i in range(game_para.random_pot_num_on_fixed_mode.z):
		create_random_res_pot(plant_cell_remaining.pop_back(), ScaryPot.E_PotType.Zombie)

	print("剩余罐子数量：", plant_cell_remaining.size(), " 使用 随机类型 结果随机罐子填充")
	for plant_cell in plant_cell_remaining:
		create_random_res_pot(plant_cell)

	print("生成的所有罐子数量:", curr_pot_num )

	#if ceil(curr_pot_num / float(row_col.x)) > 1:
		#shuffle_pot_on_row()


### TODO:按行打乱植物格子罐子  可以不用，生成时已经打乱顺序，
#func shuffle_pot_on_row():
	### 当前的罐子列数
	#var curr_pot_col = ceil(curr_pot_num / float(row_col.x))
	#for i in range(row_col.x):
		### 当前行有罐子的植物格子
		#var plant_cells_have_pot_on_row:Array = all_plant_cells[i].slice(-curr_pot_col)
		### 当前行的所有罐子
		#var all_pots_on_row:Array[ScaryPot] = []
		#for plant_cell in plant_cells_have_pot_on_row:
			#all_pots_on_row.append(plant_cell.pot)
#
		#assert(all_pots_on_row.size() == curr_pot_col, "当前行的罐子数量：" + str(all_pots_on_row.size()) + "罐子的列数: " + str(curr_pot_col))
		### 罐子打乱顺序
		#all_pots_on_row.shuffle()
		### 每个格子都有罐子，罐子与植物格子无信号连接，只修改引用，修改罐子父节点即可,
		#for j in range(curr_pot_col):
			#var plant_cell:PlantCell = plant_cells_have_pot_on_row[j]
			#var pot:ScaryPot = all_pots_on_row[j]
			#plant_cell.pot = pot
			#pot.reparent(plant_cell)
			#pot.position = Vector2(plant_cell.size.x / 2, plant_cell.size.y)
			#pot.plant_cell = plant_cell

## 创建一个结果随机罐子
func create_random_res_pot(plant_cell:PlantCell, pot_type:=ScaryPot.E_PotType.Random):
	var pot_para:Dictionary = {
		ScaryPot.E_PotInitParaAttr.PotType:pot_type,
		ScaryPot.E_PotInitParaAttr.IsFixedRes:false,
		ScaryPot.E_PotInitParaAttr.PlantCell:plant_cell,
		ScaryPot.E_PotInitParaAttr.IsCanLookRandom:Global.main_game.game_para.is_can_look_random_res_pot
	}
	plant_cell_creat_pot(plant_cell, pot_para)


## 创建多个僵尸罐子
func create_multi_zombie_pot(pot_num_zombie_types:Dictionary, plant_cells_candidate:Array, pot_type:ScaryPot.E_PotType)->Array:
	for zombie_type in pot_num_zombie_types:
		## 循环数量
		for i in range(pot_num_zombie_types[zombie_type]):
			if plant_cells_candidate.is_empty():
				print("warning: 僵尸类型", Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieName), "没有对应的空闲植物格子")
				return plant_cells_candidate
			var plant_cell:PlantCell = plant_cells_candidate.pick_random()
			var pot_para:Dictionary = {
				ScaryPot.E_PotInitParaAttr.PotType:pot_type,
				ScaryPot.E_PotInitParaAttr.IsFixedRes:true,
				ScaryPot.E_PotInitParaAttr.ZombieType:zombie_type,
				ScaryPot.E_PotInitParaAttr.PlantCell:plant_cell
			}
			plant_cell_creat_pot(plant_cell, pot_para)
			plant_cells_candidate.erase(plant_cell)
	return plant_cells_candidate

## 创建多个植物罐子
func create_multi_plant_pot(pot_num_plant_types:Dictionary, plant_cells_candidate:Array, pot_type:ScaryPot.E_PotType)->Array:
	for plant_type in pot_num_plant_types:
		## 循环数量
		for i in range(pot_num_plant_types[plant_type]):
			var plant_cell:PlantCell = plant_cells_candidate.pick_random()
			var pot_para:Dictionary = {
				ScaryPot.E_PotInitParaAttr.PotType:pot_type,
				ScaryPot.E_PotInitParaAttr.IsFixedRes:true,
				ScaryPot.E_PotInitParaAttr.PlantType:plant_type,
				ScaryPot.E_PotInitParaAttr.PlantCell:plant_cell
			}
			plant_cell_creat_pot(plant_cell, pot_para)
			plant_cells_candidate.erase(plant_cell)
	return plant_cells_candidate


#endregion
## 植物格子创建罐子
func plant_cell_creat_pot(plant_cell:PlantCell, pot_para:Dictionary):
	var pot:ScaryPot = plant_cell.create_pot(pot_para)
	if is_pot_mode:
		pot.signal_open_pot.connect(pot_open_update)
	curr_pot_num += 1
	#print("创建一个罐子")

## 罐子模式打开最后一个罐子时按原规则检查清场，与额外 Boss 胜利独立。
## [param is_zombie] 表示最后一个罐子是否生成僵尸；[param glo_pos] 为普通奖杯的全局位置。
func pot_open_update(is_zombie:bool, glo_pos:Vector2):
	curr_pot_num -= 1
	if curr_pot_num == 0:
		## 如果最后一个罐子是僵尸，并且场上有僵尸,让僵尸管理器管理最终胜利
		if is_zombie or Global.main_game.zombie_manager.curr_zombie_num != 0:
			EventBus.push_event("end_wave_zombie")
		else:
			EventBus.push_event("create_trophy", glo_pos)

#endregion

func plant_cell_pre_plant(plant_cell:PlantCell, plant_type:CharacterRegistry.PlantType, is_imitater:bool, is_zombie_mode:=false):
	plant_cell.create_plant(plant_type, false, false, is_imitater, is_zombie_mode,
		null, PlantCell.PlacementOrigin.LevelSetup)

func create_tombstone(new_num:int):
	tomb_stone_manager.create_tombstone(new_num)

## 为 [param lane] 行的现有地块播放原版火焰。
func jalapeno_bomb_effect(lane:int):
	for plant_cell: PlantCell in board.row_cells(lane): # 跳过稀疏棋盘的空格。
		show_jalapeno_fire(plant_cell)

## 在 [param cell] 播放原生火焰并返回实例。[param ground] 启用由爆炸控制器回收的残火。
func show_jalapeno_fire(cell: PlantCell, ground: bool = false) -> BombEffectFire:
	var fire: BombEffectFire = SceneRegistry.FIRE.instantiate() # 独立表现，随地块及平台运动。
	fire.z_index = cell.row_col.x * 50 + 40
	fire.z_as_relative = false
	cell.add_child(fire)
	fire.global_position = cell.global_position + Vector2(cell.size.x / 2, cell.size.y)
	if ground:
		fire.scale *= 0.55
		fire.animation_player.play(&"fire_flame")
	else:
		fire.activate_bomb_effect()
	return fire

func jalapeno_bomb_item_lane(lane:int):
	## 梯子
	for p_c :PlantCell in board.row_cells(lane):
		if is_instance_valid(p_c.ladder):
			p_c.ladder.queue_free()


## 获取有植物的植物格子 (蹦极)
func get_cell_have_plant()->Array[PlantCell]:
	var all_cell_have_plant:Array[PlantCell]
	for plant_cell_lane in all_plant_cells:
		for plant_cell:PlantCell in plant_cell_lane:
			if plant_cell.get_curr_plant_num()>0:
				all_cell_have_plant.append(plant_cell)
	return all_cell_have_plant

#region 多轮游戏
func start_next_game_plant_cell_manager_update():
	## 是否已经清除植物
	var is_clear_plant:=false
	## 如果是罐子模式
	if game_para.is_pot_mode:
		## 如果不保留植物数据
		if not game_para.is_save_plant_on_pot_mode:
			print("开始清除植物")
			clear_all_plant_cell_data()
			## 等待两帧更新数据
			await get_tree().process_frame
			await get_tree().process_frame
			is_clear_plant = true
	## 我是僵尸模式
	if game_para.is_zombie_mode:
		if not is_clear_plant:
			print("开始清除植物")
			clear_all_plant_cell_data()
			## 等待两帧更新数据
			await get_tree().process_frame
			await get_tree().process_frame
			is_clear_plant = true
		if plant_random_pool_on_zombie_mode.get_item_weight(CharacterRegistry.PlantType.P002SunFlower) > 1:
			print("我是僵尸多轮游戏模式，更新向日葵随机权重为:", max(9-Global.main_game.curr_game_round, 1))
			plant_random_pool_on_zombie_mode.update_item_weight(CharacterRegistry.PlantType.P002SunFlower, max(9-Global.main_game.curr_game_round, 1))
		print("我是僵尸模式创建植物")
		## 创建植物
		create_pre_plant()
		create_plant_on_zombie_mode()

	## 创建罐子
	cerate_pot()



#endregion
#region 存档
## 植物格子管理器存档
func get_save_game_data_plant_cell_manager() -> ResourceSaveGamePlantCellManager:
	var save_game_data_plant_cell_manager:ResourceSaveGamePlantCellManager = ResourceSaveGamePlantCellManager.new()
	save_game_data_plant_cell_manager.board_state = board.capture_state()

	for plant_cell_lane in all_plant_cells:
		for plant_cell:PlantCell in plant_cell_lane:
			save_game_data_plant_cell_manager.all_plant_cells_datas.append(plant_cell.get_save_game_data_plant_cell())

	save_game_data_plant_cell_manager.tomb_stone_manager_data = tomb_stone_manager.get_save_game_data_tomb_stone_manager()

	return save_game_data_plant_cell_manager

## 清除所有植物数据
func clear_all_plant_cell_data():
	for plant_cell_lane in all_plant_cells:
		for plant_cell:PlantCell in plant_cell_lane:
			plant_cell.clear_data_plant_cell()

## 植物格子管理器读档
func load_game_data_plant_cell_manager(saved: ResourceSaveGamePlantCellManager) -> bool:
	var plan: BoardRestoreTransaction = BoardRestoreTransaction.prepare(self, saved) # 冻结数据并完成所有资源准备。
	return plan != null and plan.commit()

#endregion


## 解析存档地块；仅旧布局且没有 [param id] 时接受 [param address] 兼容地址。
func saved_cell(id: StringName, address: Vector2i) -> PlantCell:
	if board == null:
		return null
	if id != &"":
		return board.cell_by_id(id)
	return board.cell_at(address) if board.definition == null else null

## 全量预检 [param saved]，必须先于卡槽/推车等其他恢复副作用。
func accepts_save(saved: ResourceSaveGamePlantCellManager) -> bool:
	var plan: BoardRestoreTransaction = BoardRestoreTransaction.prepare(self, saved) # 完整预检而非只核对 ID。
	return plan != null


## 从真实占用一次性派生数量；只供整体恢复在发布事件之前调用，多格实例只计一次。
func rebuild_plant_counts() -> void:
	curr_plant_num.clear()
	var seen: Dictionary[int, bool] = {} # 按实例身份去重，不按格子数累计。
	for cell: PlantCell in board.cells(): # 占用仍由格子唯一持有。
		for reference: Variant in cell.living_plants(): # 先检查可能已失效的引用。
			if not is_instance_valid(reference):
				continue
			var plant := reference as Plant000Base # 已经在场的正式植物。
			if plant == null or plant.is_death or plant.is_queued_for_deletion() or seen.has(plant.get_instance_id()):
				continue
			seen[plant.get_instance_id()] = true
			curr_plant_num[plant.plant_type] = curr_plant_num.get(plant.plant_type, 0) + 1
