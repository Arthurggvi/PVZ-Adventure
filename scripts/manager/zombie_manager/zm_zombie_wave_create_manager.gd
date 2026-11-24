extends Node
## 僵尸波次生成管理器
class_name ZombieWaveCreateManager

## 一帧用于创建冒险出怪实例的软预算，单位为微秒；单只实例会完整创建。
const WAVE_SPAWN_BUDGET_USEC := 3500
## 一阶段救主在场时追加一倍；二阶段只保留原计划名额。
const SAVIOR_NATURAL_MULTIPLIER := 2

#region 波次生成僵尸管理器参数
## 出怪倍率
var zombie_multy := 1
## 蹦极僵尸数量范围
var range_num_bungi:Vector2i = Vector2i(3,5)
#endregion
@onready var zombie_manager: ZombieManager = %ZombieManager

## 僵尸选行系统
@onready var zombie_choose_row_system: ZombieChooseRowSystem = %ZombieChooseRowSystem

## 本管理器独立维护的运行时权重，实例创建时复制注册表基础数据，后续按自然波次调整。[br]
## 键和值均为整数值类型，普通复制即可隔离修改，无需深度复制。
var zombie_weights: Dictionary[CharacterRegistry.ZombieType, int] = CharacterRegistry.ZombieSpawnWeights.duplicate()

## 僵尸随机选择池
var zombie_choose_random_pool:RandomPicker

## 每波最大僵尸数量
@export var max_zombies_per_wave: int = WaveProfile.MAX_ZOMBIES_PER_WAVE
## 刷新类型最小战力
var min_power:=100
## 当前波次生成的僵尸
var wave_all_zombies:Array[Zombie000Base]
## 仅冒险阶段启用，正常原版关卡仍保持原有按波衰减/旗帜规则。
var adventure_wave_profile: WaveProfile
## 冒险计划使用的战场内随机流，每阶段重新初始化。
var _adventure_rng := RandomNumberGenerator.new()
## 本阶段开场波已计划的最低常规出怪项数；-1 表示尚未编排开场波。
var _opening_regular_spawn_floor: int = -1

## 使用 [param game_para] 初始化波次生成配置、选行系统和随机池，保留本实例已有的运行时权重。
func init_zombie_wave_create_manager(game_para:ResourceLevelData):
	zombie_multy = game_para.zombie_multy
	range_num_bungi = game_para.range_num_bungi
	zombie_choose_row_system.init_zombie_choose_row_system(zombie_manager.all_zombie_rows)
	begin_adventure_phase(AdventureSession.get_active_wave_profile(game_para))

## 更新可以刷新的僵尸列表
## 阶段连续战斗切换时替换自然波次配置，不重建选行系统或战场。
func begin_adventure_phase(profile: WaveProfile) -> void:
	adventure_wave_profile = profile
	_opening_regular_spawn_floor = -1
	_adventure_rng.randomize()
	update_zombie_refresh_types()

func update_zombie_refresh_types():
	if adventure_wave_profile != null:
		zombie_choose_random_pool = null
		return
	## 初始化僵尸生成随机池数据
	var zombie_choose_random_pool_data:Array[Array] = []
	min_power = 100
	for zombie_type in zombie_manager.zombie_refresh_types:
		if min_power > CharacterRegistry.ZombieSpawnPower[zombie_type]:
			min_power = CharacterRegistry.ZombieSpawnPower[zombie_type]
		zombie_choose_random_pool_data.append([zombie_type, zombie_weights[zombie_type]])
	print("更新僵尸随机选择池")
	zombie_choose_random_pool = RandomPicker.new(zombie_choose_random_pool_data)


## 为当前冒险阶段编排第 [param wave_number] 波，开场三波只记录已减量的常规出怪项数。
func _plan_adventure_wave(wave_number: int) -> Array[Dictionary]:
	var profile: WaveProfile = adventure_wave_profile # 调用时已确认当前处于自然出怪阶段。
	var budget: int = AdventureWavePlanner.wave_budget(profile, wave_number, zombie_multy) # 与入口校验共用预算。
	var capacity: int = profile.resolve_capacity(max_zombies_per_wave) # 已配置的阶段可提高默认单波容量。
	var plan: Array[Dictionary] = AdventureWavePlanner.build_plan(profile, wave_number, budget, capacity,
		AdventureStageCatalog.tier_threat_costs(), _adventure_rng, maxi(0, _opening_regular_spawn_floor)) # 后段下限沿用本阶段的开场记录。
	if profile.late_spawn_count_start_wave > 0 and wave_number <= WaveProfile.OPENING_WAVE_COUNT:
		var count: int = AdventureWavePlanner.regular_spawn_count(plan) # 不计旗帜、固定行及独立滑雪配额。
		_opening_regular_spawn_floor = count if _opening_regular_spawn_floor < 0 else mini(_opening_regular_spawn_floor, count)
	return plan


#region 创建当前波次僵尸
## 创建 [param wave] 的僵尸，[param is_big_wave] 用于选择大波计划。[br]
## [param yield_for_budget] 可等待下一帧并检查战斗是否仍有效；返回 false 时停止本次生成。[br]
## [param mower_weights] 为本波丢车保护的逐行权重，空数组沿用地形基础权重。
func create_curr_wave_all_zombies(wave: int, is_big_wave: bool,
		yield_for_budget: Callable = Callable(), mower_weights: Array[float] = []) -> Array[Zombie000Base]:
	## 获取当前波僵尸生成列表
	var wave_spawn: Array[Dictionary] = []
	if adventure_wave_profile != null:
		wave_spawn = _plan_adventure_wave(wave + 1) # 冒险资源使用从 1 开始的波次编号。
	else:
		for zombie_type: CharacterRegistry.ZombieType in create_curr_wave_zombie_list(wave, is_big_wave):
			wave_spawn.append({"zombie_type": zombie_type, "tier_id": &""})
	# ice_weights 是本波雪橇可用的行权重，按需读取一次。
	var ice_weights: Array[float] = []
	wave_all_zombies.clear()
	## 当前波次僵尸数据
	var curr_wave_zombie_date:Array[Dictionary]

	# spawn 是策划生成的单个出生项。
	for spawn: Dictionary in wave_spawn:
		# zombie_type 是本项要生成的类型。
		var zombie_type: CharacterRegistry.ZombieType = spawn["zombie_type"]
		# lane 为选定的行，-1 表示无合法行。
		var lane :int = -1
		var fixed_row: int = spawn.get("row", 0) # 预排行从 1 开始，0 继续使用常规选行。
		var is_cannon: bool = zombie_type == CharacterRegistry.ZombieType.Z039CannonTurret # 炮车的空行在实际创建前确认。
		if zombie_type == CharacterRegistry.ZombieType.Z014Bobsled and fixed_row == 0:
			if ice_weights.is_empty():
				ice_weights = _bobsled_ice_weights(mower_weights)
			# 有效冰道即使降权也能出雪橇；没有正权重时用四名普通僵尸替代整队。
			if not ice_weights.any(func(weight: float) -> bool: return weight > 0.0):
				# member_index 是这支替补小队中的序号。
				for member_index in range(4):
					# normal_type 用于按普通僵尸的行规则选行。
					var normal_type := CharacterRegistry.ZombieType.Z001Norm
					lane = zombie_choose_row_system.select_spawn_row(
							Global.character_registry.get_zombie_info(normal_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType),
							mower_weights)
					if lane >= 0:
						curr_wave_zombie_date.append({
							"zombie_type": normal_type, "lane": lane, "tier_id": spawn["tier_id"],
						})
				continue
		if fixed_row > 0:
			lane = fixed_row - 1
			if zombie_manager.main_game.board.definition != null and not zombie_manager.is_lane_open(lane):
				# 遭遇中移除预排行时，交给当前留存地形的选行权重。
				if not is_cannon:
					lane = zombie_choose_row_system.select_spawn_row(
							Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType),
							mower_weights)
			elif not zombie_manager.can_spawn_zombie_in_lane(zombie_type, lane):
				if not is_cannon:
					push_error("预排出怪无法生成到第%d行。" % fixed_row)
				continue
			else:
				zombie_choose_row_system.on_zombie_spawned(lane)
		elif zombie_type == CharacterRegistry.ZombieType.Z014Bobsled:
			lane = zombie_choose_row_system.select_spawn_row(
					Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType),
					ice_weights)
		elif not is_cannon:
			lane = zombie_choose_row_system.select_spawn_row(
					Global.character_registry.ZombieInfo[zombie_type][CharacterRegistry.ZombieInfoAttribute.ZombieRowType],
					mower_weights)
		# 选行失败时跳过该项，不能把 -1 作为最后一行索引使用。
		if lane < 0 and not is_cannon:
			continue
		curr_wave_zombie_date.append(
			{
				"zombie_type":zombie_type,
				"lane":lane,
				"tier_id":spawn["tier_id"],
			}
		)
	var base_count: int = curr_wave_zombie_date.size() # 模板已选行的原始名额，仍可在救主死亡后按原配置生成。
	var limit: int = base_count * SAVIOR_NATURAL_MULTIPLIER if adventure_wave_profile != null else base_count # 附加名额只存在于冒险。
	var batch_started_at: int = Time.get_ticks_usec() # 只计入同一帧的出怪开销，等待下一帧后重置。
	for index: int in range(limit): # 跨帧续刷时按当前存活者决定名额、实际类型与等阶。
		if yield_for_budget.is_valid() and Time.get_ticks_usec() - batch_started_at >= WAVE_SPAWN_BUDGET_USEC:
			if not await yield_for_budget.call():
				return wave_all_zombies
			batch_started_at = Time.get_ticks_usec()
		# 本波尚未出怪时等首个空位。已经出怪的批次到达上限后结束，避免积压到下一波。
		while zombie_manager.available_zombie_slots(1) == 0:
			if not wave_all_zombies.is_empty() or not yield_for_budget.is_valid():
				return wave_all_zombies
			if not await yield_for_budget.call():
				return wave_all_zombies
			batch_started_at = Time.get_ticks_usec()
		var savior: ZB000Base = zombie_manager.get_living_boss_of_type(
			CharacterRegistry.ZombieBossType.ZB005Savior) if adventure_wave_profile != null else null # 本体死亡时继承存活分身。
		var empowered: bool = savior != null # 二阶段延续四阶替换，最后一名死亡才恢复模板。
		if index >= base_count and (not empowered or savior.boss_phase >= 2):
			break
		var entry: Dictionary = curr_wave_zombie_date[index % base_count] # 额外项沿用自然选行规则。
		var kind: CharacterRegistry.ZombieType = CharacterRegistry.ZombieType.Z001Norm if empowered else entry["zombie_type"] # 本次真正出场的物种。
		var lane: int = entry["lane"] # 模板项保留原有选行和预排行。
		if kind == CharacterRegistry.ZombieType.Z039CannonTurret and not zombie_manager.is_lane_open(lane):
			lane = _select_cannon_turret_lane(mower_weights)
		elif index >= base_count:
			lane = zombie_choose_row_system.select_spawn_row(
					Global.character_registry.ZombieInfo[kind][CharacterRegistry.ZombieInfoAttribute.ZombieRowType],
					mower_weights if mower_weights.size() == zombie_manager.all_zombie_rows.size() else [])
		elif not zombie_manager.is_lane_open(lane):
			# 跨帧生成区在地形退行后重新选择仍存在的合法行。
			lane = zombie_choose_row_system.select_spawn_row(
					Global.character_registry.ZombieInfo[kind][CharacterRegistry.ZombieInfoAttribute.ZombieRowType])
		var modifier: ZombieSpawnModifier = null # 无冒险阶段时保留原版生成行为。
		if adventure_wave_profile != null:
			modifier = AdventureZombieTierBinding.new(&"tier4" if empowered else entry["tier_id"])
		var zombie: Zombie000Base = wave_create_zombie(kind, lane, wave, Callable(), true, modifier) # 沿用自然波次归属和生成预算。
		if is_instance_valid(zombie):
			wave_all_zombies.append(zombie)

	return wave_all_zombies

## 返回各行的雪橇出生权重；有效冰道采用 [param mower_weights] 或默认权重 1，无冰道的行权重为 0。
func _bobsled_ice_weights(mower_weights: Array[float]) -> Array[float]:
	# 与僵尸行顺序一致的雪橇候选权重。
	var weights: Array[float] = []
	# row_roads 是一行中由不同造冰车生成的冰道。
	for row_roads: Array in zombie_manager.all_ice_roads:
		var has_ice: bool = zombie_manager.is_lane_open(weights.size()) and row_roads.any( # 只有开放行的冰道才能刷雪橇。
				func(road: IceRoad) -> bool: return is_instance_valid(road) and road.has_board_ice())
		var weight: float = 1.0 if mower_weights.is_empty() else mower_weights[weights.size()] # 取当前行的丢车权重。
		weights.append(weight if has_ice else 0.0)
	return weights


## 生成波次僵尸
## [param zombie_type] 和 [param tier_id] 指定援军或事件生成的敌人，满场时返回 null。
## 支援单位计入场上敌人，不参与自然波次残血或清空刷新。
func spawn_stage_support(zombie_type: CharacterRegistry.ZombieType, tier_id: StringName) -> Zombie000Base:
	if not zombie_manager.is_game_running() or zombie_manager.available_zombie_slots(1) == 0 \
			or not Global.character_registry.ZombieInfo.has(zombie_type):
		return null
	var row_type: CharacterRegistry.ZombieRowType = Global.character_registry.ZombieInfo[zombie_type][CharacterRegistry.ZombieInfoAttribute.ZombieRowType]
	var lane: int = _select_cannon_turret_lane([]) if zombie_type == CharacterRegistry.ZombieType.Z039CannonTurret \
		else zombie_choose_row_system.select_spawn_row(row_type) # 炮塔援军也只从有余位的行选取。
	if lane < 0:
		return null
	return wave_create_zombie(zombie_type, lane, -1, Callable(), false,
		AdventureZombieTierBinding.new(tier_id))

## 从当前可用的炮塔行平滑抽样。[param mower_weights] 保留无车行保护，棋盘换行后使用当前行数。
## 无空行时返回 -1，由普通波次入口跳过该次生成。
func _select_cannon_turret_lane(mower_weights: Array) -> int:
	var weights: Array[float] = [] # 与实际行号对齐，已占用行权重为零。
	var lane_count: int = zombie_manager.all_zombie_rows.size() # 按当前棋盘行数重算候选。
	for lane: int in range(lane_count): # 每次只为本只即将出场的炮车取一次候选。
		var base: float = mower_weights[lane] if mower_weights.size() == lane_count else 1.0 # 继承关卡已有行保护。
		weights.append(base if zombie_manager.can_spawn_zombie_in_lane(CharacterRegistry.ZombieType.Z039CannonTurret, lane) else 0.0)
	return zombie_choose_row_system.select_spawn_row(CharacterRegistry.ZombieRowType.Land, weights)

func wave_create_zombie(
	zombie_type:CharacterRegistry.ZombieType,
	lane:int, 	## 僵尸行
	curr_wave:int,		## 僵尸波次
	init_zombie_special:Callable = Callable(),	## 初始化僵尸特殊属性
	is_natural: bool = true,
	spawn_modifier: ZombieSpawnModifier = null
):
	# 直接调用者也必须使用真实存在的行，防止错误下标进入通用创建入口。
	if not zombie_manager.is_lane_open(lane):
		return null
	var zombie_init_para:Dictionary = {
		Zombie000Base.E_ZInitAttr.CharacterInitType:Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane:lane,
		Zombie000Base.E_ZInitAttr.CurrWave:curr_wave,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh:is_natural,
	}
	var zombie_parent = zombie_manager.all_zombie_rows[lane]
	var zombie_glo_pos = zombie_manager.all_zombie_rows[lane].zombie_create_position.global_position + Vector2(randf_range(-10, 10), 0)
	if zombie_type == CharacterRegistry.ZombieType.Z014Bobsled:
		# 初代雪橇比普通僵尸更早在画面外开始推行。
		zombie_glo_pos.x += 64.0

	var zombie = zombie_manager.create_norm_zombie(zombie_type,zombie_parent,
		zombie_init_para, zombie_glo_pos, init_zombie_special, spawn_modifier)

	return zombie

#region 创建当前波僵尸生成列表
## 根据零起始波次 [param wave] 和大波标记 [param is_big_wave] 返回本波僵尸类型列表。[br]
## 每次生成前同步权重与随机池，确保直接载入后期波次也使用对应的衰减权重。
func create_curr_wave_zombie_list(wave:int, is_big_wave:bool):
	# 本波可分配给僵尸的战力总额。
	var curr_wave_power_limit = calculate_wave_power_limit(wave, is_big_wave)
	# 按当前波次直接计算，不能依赖先前波次曾经更新过权重。
	_update_weights(wave)
	# 按本波权重和战力预算抽取的僵尸类型列表。
	var wave_spawn :Array[CharacterRegistry.ZombieType] = get_curr_wave_zombie_list(wave, is_big_wave, curr_wave_power_limit)

	return wave_spawn

## 计算每波的战力上限
func calculate_wave_power_limit(wave:int, is_big_wave: bool) -> int:
	## x从0开始
	## 计算战力上限 = y=int(x/3)+1
	@warning_ignore("integer_division")
	var base_power_limit:int = wave / 3 + 1
	## 如果是大波，战力上限是原战力上限的2.5倍
	if is_big_wave:
		return int(base_power_limit * 2.5) * zombie_multy

	return base_power_limit * zombie_multy

## 按零起始自然波次 [param wave] 更新权重及随机池；本函数独立维护自然出怪的成长规则。[br]
## 每次从注册表基础值计算，重复调用不会累加衰减，超过索引 25 后保持末档权重。
func _update_weights(wave: int) -> void:
	zombie_weights = CharacterRegistry.ZombieSpawnWeights.duplicate()
	# 前六波保持基础权重，之后最多衰减二十档，保留原自然出怪公式。
	var decay_steps: int = clampi(wave - 5, 0, 20)
	zombie_weights[CharacterRegistry.ZombieType.Z001Norm] -= decay_steps * 180
	zombie_weights[CharacterRegistry.ZombieType.Z003Cone] -= decay_steps * 150
	# 只有这两种类型随进度衰减，其余随机池条目保持基础权重。
	for zombie_type: CharacterRegistry.ZombieType in [CharacterRegistry.ZombieType.Z001Norm, CharacterRegistry.ZombieType.Z003Cone]:
		if zombie_type in zombie_manager.zombie_refresh_types:
			zombie_choose_random_pool.update_item_weight(zombie_type, zombie_weights[zombie_type], false)
	zombie_choose_random_pool.rebuild_alias_table()

## 获取当前波僵尸列表
func get_curr_wave_zombie_list(wave:int, is_big_wave: bool, curr_wave_power_limit:int) ->Array[CharacterRegistry.ZombieType]:
	## 当前波的僵尸列表
	var wave_spawn :Array[CharacterRegistry.ZombieType]= []
	## 目前总战力
	var total_power = 0
	## 当前空隙位置
	var curr_spare_slot = max_zombies_per_wave

	## 如果是大波，先刷新特殊僵尸
	if is_big_wave:
		## 第一个旗帜僵尸
		wave_spawn.append(CharacterRegistry.ZombieType.Z002Flag)
		total_power += CharacterRegistry.ZombieSpawnPower[CharacterRegistry.ZombieType.Z002Flag]
		curr_spare_slot -= 1

		# 第一次大波（第10波），刷新4个普通僵尸
		if wave == 9:
			for i in range(4):
				wave_spawn.append(CharacterRegistry.ZombieType.Z001Norm)
				total_power += CharacterRegistry.ZombieSpawnPower[CharacterRegistry.ZombieType.Z001Norm]
				curr_spare_slot -= 1
		# 之后的大波（第20波、30波...），刷新8个普通僵尸
		else:
			for i in range(8):
				wave_spawn.append(CharacterRegistry.ZombieType.Z001Norm)
				total_power += CharacterRegistry.ZombieSpawnPower[CharacterRegistry.ZombieType.Z001Norm]
				curr_spare_slot -= 1

	# 生成剩余僵尸，直到总战力符合当前战力上限
	while curr_spare_slot > 0 and total_power < curr_wave_power_limit:

		var selected_zombie:CharacterRegistry.ZombieType = zombie_choose_random_pool.get_random_item()
		# 本次抽中类型消耗的战力，统一读取角色注册表。
		var zombie_power_value: int = CharacterRegistry.ZombieSpawnPower[selected_zombie]

		#prints("当前剩余僵尸", curr_spare_slot, "当前战力:", total_power, "当前所选僵尸:", selected_zombie, "当前所选僵尸战力:", zombie_power_value)

		# 检查如果加上该僵尸的战力后超过当前波的战力上限，重新选择
		if total_power + zombie_power_value <= curr_wave_power_limit:
			wave_spawn.append(selected_zombie)
			total_power += zombie_power_value
			curr_spare_slot -= 1
		elif curr_wave_power_limit - total_power < min_power:
			for i in range(curr_wave_power_limit - total_power):
				wave_spawn.append(CharacterRegistry.ZombieType.Z001Norm)
				total_power += CharacterRegistry.ZombieSpawnPower[CharacterRegistry.ZombieType.Z001Norm]
				curr_spare_slot -= 1
			continue
		else:
			continue

	return wave_spawn

#endregion

#endregion

#region 大波僵尸时生成特殊僵尸
## 大波僵尸时创建特殊僵尸
## [is_final:bool] 是否为最后一波
func spawn_special_zombie_in_big_wave(is_final:=false):
	## 珊瑚僵尸,若有水路自动创建,没有则不创建
	if is_final:
		if not zombie_manager.is_ice:
			print("生成珊瑚僵尸")
			spawn_sea_weed_zombies()
		else:
			print("被冰冻无法生成珊瑚僵尸")
	## 如果有蹦极僵尸
	if zombie_manager.is_bungi:
		spawn_bungi_zombies()

#region 珊瑚僵尸
## 最后一大波珊瑚僵尸
func spawn_sea_weed_zombies():
	var zombie_row_pool_i :Array[int]
	for i in range(zombie_manager.all_zombie_rows.size()):
		if zombie_manager.all_zombie_rows[i].zombie_row_type == CharacterRegistry.ZombieRowType.Pool:
			zombie_row_pool_i.append(i)
	if zombie_row_pool_i.is_empty():
		print("无水路,无法生成珊瑚僵尸")
		return

	var zombie_type_sea_weed_list :Array= [CharacterRegistry.ZombieType.Z001Norm, CharacterRegistry.ZombieType.Z003Cone, CharacterRegistry.ZombieType.Z005Bucket]

	for i in range(3):
		var zombie_type:CharacterRegistry.ZombieType = zombie_type_sea_weed_list.pick_random()
		var lane:int= zombie_row_pool_i.pick_random()
		var zombie_sea_weed:Zombie000Base = wave_create_zombie(zombie_type, lane, -1, _zombie_seaweed)

		if is_instance_valid(zombie_sea_weed):
			zombie_sea_weed.global_position.x = randf_range(500, 750)

## 珊瑚僵尸
func _zombie_seaweed(z:Zombie001Norm):
	z.is_seaweed = true
#endregion

#region 蹦极僵尸
func spawn_bungi_zombies():
	## 选择plant_cell
	var num_bungi_rand:int = randi_range(range_num_bungi.x, range_num_bungi.y)
	var all_cell_have_plant:Array[PlantCell] = zombie_manager.main_game.plant_cell_manager.get_cell_have_plant()
	var num_bungi_res:int = min(num_bungi_rand, all_cell_have_plant.size())
	## 打乱顺序
	all_cell_have_plant.shuffle()
	## 蹦极僵尸选中的plant_cell
	var all_cell_be_bungi = all_cell_have_plant.slice(0, num_bungi_res)
	## 生成蹦极僵尸
	for plant_cell:PlantCell in all_cell_be_bungi:
		var zombie_init_para:Dictionary = {
			Zombie000Base.E_ZInitAttr.CharacterInitType:Character000Base.E_CharacterInitType.IsNorm,
			Zombie000Base.E_ZInitAttr.Lane:plant_cell.row_col.x
		}

		zombie_manager.create_norm_zombie(
			CharacterRegistry.ZombieType.Z021Bungi,
			zombie_manager.all_zombie_rows[plant_cell.row_col.x],
			zombie_init_para,
			plant_cell.get_spawn_global_position(),
			GlobalUtils.create_bungi.bind(plant_cell)
		)

#endregion

#endregion
