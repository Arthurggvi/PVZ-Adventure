## 管理普通僵尸波次和独立僵王实例，统一敌方计数、轮间保存及胜利请求。
extends MainGameSubManager
class_name ZombieManager

## 出战僵王成功入树、死亡或移除后发出，供所属关卡按当前存活实例选择战斗音乐。
signal signal_living_bosses_changed()
## [param member] 已完成登记，可在入树前连接遭遇信号。整批增援先登记完所有成员，再逐一通知。
signal boss_member_registered(member: ZB000Base)
## 正常僵尸完成初始化与登记后发送，供光环等通用效果覆盖新实例。
signal signal_zombie_created(zombie: Zombie000Base)

## 记录同一实例的登场、死亡、离场和阶段清场条件。
const BossTrace = preload("res://scripts/manager/zombie_manager/boss_lifecycle_trace.gd")

## 独立准备和发布僵王实体；管理器继续唯一持有战场登记、计数与死亡监听。
const BossSpawn = preload("res://scripts/manager/zombie_manager/boss_spawn_factory.gd")

## 两只僵王同时默认登场时，按先后安排在第 2、4 路，内部从 0 开始。
const BOSS_DUO_LANES := Vector2i(1, 3)

## 无出怪模式或最后一波启用的场外清理计时器，每秒清理离开视野的普通僵尸。
@onready var check_zombie_end_wave_timer: Timer = $CheckZombieEndWaveTimer
## 管理器
@onready var zombie_wave_manager: ZombieWaveManager = $ZombieWaveManager
@onready var zombie_show_in_start: ZombieShowInStart = $ZombieShowInStart
@onready var hammer_zombie_manager: HammerZombieManager = $HammerZombieManager
## 所有僵尸根节点
@onready var zombies_root: Node2D = %ZombiesRoot
## 僵王独立挂载，不混入会被当作僵尸行遍历的 ZombiesRoot。
@onready var zombie_boss_root: Node2D = get_node_or_null("%ZombieBossRoot") as Node2D

## 本关已登记的僵王弱引用；死亡演出期间保留，离树时按实例 ID 移除。
var _registered_bosses: Dictionary[int, WeakRef] = {}
## 仍计入敌方数量的僵王 ID；死亡和离树共用此集合，保证只扣一次。
var _counted_boss_ids: Dictionary[int, bool] = {}
## 实例对应的注册类型，用于保存存活僵王，不依赖节点名称。
var _boss_types: Dictionary[int, CharacterRegistry.ZombieBossType] = {}
## 自动生成入口是否已经成功出场；卡牌召唤不占用此记录。
var _auto_boss_spawned := false
## 自动生成实例的 ID，仅用于自动入口重复调用时返回原实例。
var _auto_boss_id: int = 0
## 本局累计成功生成数量，自动出场和卡牌召唤均计入，恢复存档不重复增加。
var _boss_spawn_total: int = 0
## 本局累计确认死亡数量；直接移除不计为击杀。
var _boss_dead_total: int = 0
## 分裂遭遇的成员活着离场后，余下击杀不会再发出完成奖励。
var _escaped_boss_groups: Dictionary[int, bool] = {}
## 额外 Boss 条件实际开始结算后接受最后死亡实例的请求；0 表示没有待结算实例。
var _boss_trophy_pending_id: int = 0
## 额外胜利的奖杯已经收到请求时保存其落点，允许其他仍在演出的 Boss 稍后完成。
var _boss_trophy_pending_position: Vector2 = Vector2.INF
## 已扣除敌方计数但仍在演出、需推迟结算的登记实例。
var _pending_boss_defeat_presentations: Dictionary[int, bool] = {}
## 正式遭遇或关卡直接请求的普通奖杯，演出结束后按原条件重新提交。
var _deferred_round_trophy_position: Vector2 = Vector2.INF
## 轮间计时已到，但仍须等死亡演出完成后交付过渡请求。
var _next_round_waiting_for_boss_presentation: bool = false
## 由 Boss 自行接管死亡演出时，钻石等待其原生完成通知。
var _pending_boss_diamonds: Dictionary[int, bool] = {}
## 本轮调用 Boss 胜利完成入口前置位，防止方法轨道重复触发；下一轮重新开启结算。
var _boss_trophy_created := false
## 轮间读档暂存的数据；选卡完成后才恢复正常出战实例，避免选卡期间启动技能。
var _saved_boss_data: Dictionary = {}
## 场上原先为空时，本帧默认出场的首个实例 ID；用于识别同时登场。
var _first_default_boss_id: int = 0
## 首只默认僵王登场的处理帧，避免挪动更早已出战的僵王。
var _first_default_boss_frame: int = -1
## 每轮只安排一次首波计时，下一轮开始时重置。
var _start_requested := false
## 轮次切换时递增，首波延迟不能从上一轮恢复到新一轮。
var _round_generation: int = 0

#region 僵尸管理器参数
## 刷怪类型
var is_bungi = false
var zombie_refresh_types = []

## 出怪模式
var monster_mode:ConstLevelData.E_MonsterMode = ConstLevelData.E_MonsterMode.Norm

#endregion

#region 多轮游戏
## 多轮游戏最后一波计时器
var multi_round_end_wave_timer:Timer
## 多轮游戏最后一波时长
var multi_round_end_wave_time :float = 49

#endregion

## 场上计入清场判定的敌人总数，包含已登记的存活僵王。
var curr_zombie_num: int = 0
## 本战场的敌方存活上限，包含僵王和援军。零表示沿用不限数量的出怪规则。
@export var max_live_enemies: int = 0
## 已把在场名额交给新形态的旧实例，后续注销只移除旧登记，不重复释放名额。
var _transferred_enemy_slots: Dictionary[Zombie000Base, bool] = {}
## 本战斗场景内的修改器开关；开启时处决新生成的敌人，默认关闭。
var cheat_instant_kill_enabled := false

## 参与自然提前刷新的实例 ID；魅惑、死亡或离树时注销。
var _natural_refresh_zombie_ids: Dictionary[int, bool] = {}
## 自然提前刷新只读取该数量，博士本体及其召唤物不在集合中。
var natural_refresh_zombie_count: int:
	get:
		return _natural_refresh_zombie_ids.size()
## 自然刷新参与数量发生变化时发出；[param num] 不包含博士及其衍生僵尸。
signal signal_natural_refresh_zombie_num_change(num: int)
## 僵尸出生波次独立计数；避免上一波残敌死亡被归入当前波。
signal signal_natural_wave_count_change(wave_number: int, count: int)
var _natural_wave_by_id: Dictionary[int, int] = {}
var _natural_wave_counts: Dictionary[int, int] = {}

func get_natural_wave_count(wave_index: int) -> int:
	return _natural_wave_counts.get(wave_index + 1, 0)

## 是否为最后一波,最后一波时，僵尸数量为0后结束游戏
var is_end_wave := false
## 被魅惑僵尸列表
var all_zombies_be_hypno:Array[Zombie000Base] = []
## 僵尸可以存在的世界 X 坐标范围，波次刷新和末波定时检查会清理越界实例。
@export var zombie_range_pos_x := Vector2(-300, 1000)
## 本关仍登记的普通僵尸，含魅惑实例；死亡或实际离树时移除。
var all_zombies_1d:Array[Zombie000Base]

## 所有僵尸行
var all_zombie_rows:Array[ZombieRow] = []
## 冰道,按行保存每行的冰道
var all_ice_roads:Array[Array] = []
## 按行保存僵尸，用于保存僵尸列表的列表,僵尸被魅惑后从该列表中删除
var all_zombies_2d:Array[Array]

## 当前战场中低频僵尸查询的分帧调度器。
var periodic_updates: ZombieUpdateScheduler

## 按实际场景路径和等阶缓存美术装配，随战场一起释放。
var _appearances: Dictionary[String, AdventureZombieTierArt.PreparedAppearance] = {}

## 是否被冻结，用于管理冰消珊瑚
var is_ice:bool
var ice_timer:Timer

func _ready():
	var death_archive := AdventureZombieDeathArchive.new()
	death_archive.name = "AdventureZombieDeathArchive"
	add_child(death_archive)
	## 注册事件总线
	EventBus.subscribe("ice_all_zombie", ice_all_zombie)
	## 火爆辣椒销毁道具[冰道和梯子]
	EventBus.subscribe("jalapeno_bomb_item_lane", jalapeno_bomb_item_lane)
	EventBus.subscribe("jalapeno_bomb_lane_zombie", jalapeno_bomb_lane_zombie)
	EventBus.subscribe("blover_blow_away_in_sky_zombie", blover_blow_away_in_sky_zombie)
	## 非刷怪模式最后一波僵尸
	EventBus.subscribe("end_wave_zombie", func():is_end_wave=true)
	EventBus.subscribe("test_death_all_zombie", death_all_zombie)

	# 攻击行已由统一装配器创建/适配，这里只登记僵尸运行状态。
	if main_game.board == null or not main_game.board.configured:
		return
	periodic_updates = ZombieUpdateScheduler.new()
	periodic_updates.name = "ZombieUpdateScheduler"
	add_child(periodic_updates)
	## 初始化僵尸和行列表
	for zombie_row_i in zombies_root.get_child_count():
		var zombie_row: ZombieRow = zombies_root.get_child(zombie_row_i) as ZombieRow
		zombie_row.z_index = zombie_row_i * 50 + 30

		all_zombie_rows.append(zombie_row)
		var row_ice_roads:Array[IceRoad] = []
		all_ice_roads.append(row_ice_roads)

		var row_zombies:Array[Zombie000Base] = []
		all_zombies_2d.append(row_zombies)

## 初始僵尸管理器
func init_manager() -> void:
	## 出怪模式
	monster_mode = game_para.monster_mode
	match monster_mode:
		# 不启动自然波次；无论胜利条件如何，都持续清理移出视野的普通僵尸。
		ConstLevelData.E_MonsterMode.Null:
			check_zombie_end_wave_timer.start()
			zombie_wave_manager.flag_progress_bar.hide()
			# 终末阶段重开时仍须初始化独立援军的选行。
			if AdventureSession.owns_battle(game_para):
				zombie_refresh_types = game_para.zombie_refresh_types
				zombie_wave_manager.zombie_wave_create_manager.zombie_choose_row_system.init_zombie_choose_row_system(all_zombie_rows)

		ConstLevelData.E_MonsterMode.Norm:
			## 如果游戏是多轮游戏
			if game_para.game_round != 1:
				update_multi_round_zombie_refresh_types(main_game.curr_game_round, main_game.game_para.game_sences)
			else:
				## 刷怪类型
				is_bungi = game_para.is_bungi
				zombie_refresh_types = game_para.zombie_refresh_types

			zombie_wave_manager.init_zombie_wave_manager(game_para)
			## 波次刷新时判断是否为最后一波，删除多余魅惑僵尸
			zombie_wave_manager.signal_wave_refresh.connect(wave_refresh)
			## 使用独立的自然刷新数量，博士及其召唤物不阻塞旗前波提前刷新。
			signal_natural_refresh_zombie_num_change.connect(zombie_wave_manager.zombie_wave_refresh_manager.judge_total_refresh)

		ConstLevelData.E_MonsterMode.HammerZombie:
			hammer_zombie_manager.init_hammer_zombie_manager(game_para)
			## 波次刷新时判断是否为最后一波，删除多余魅惑僵尸
			hammer_zombie_manager.signal_wave_refresh.connect(wave_refresh)

## 进入 [param phase] 前校验战场已清空且阶段配置可启动，必须先于钥匙消费。
func can_begin_adventure_phase(phase: StagePhaseDefinition) -> bool:
	if not is_game_running() or not is_end_wave or curr_zombie_num != 0 or phase == null:
		return false
	if phase.kind == StagePhaseDefinition.Kind.TERMINAL:
		return phase.wave_profile == null
	return phase.wave_profile != null and phase.wave_profile.wave_count >= 2

## 确认预检及钥匙事务后同步进入 [param phase]；过程无额外失败分支。
## 植物、阳光与卡组仍属于同一战场。
func begin_adventure_phase(phase: StagePhaseDefinition) -> void:
	assert(can_begin_adventure_phase(phase))
	_round_generation += 1
	if is_instance_valid(check_zombie_end_wave_timer):
		check_zombie_end_wave_timer.stop()
	if is_instance_valid(multi_round_end_wave_timer):
		multi_round_end_wave_timer.stop()
	_natural_refresh_zombie_ids.clear()
	_natural_wave_by_id.clear()
	_natural_wave_counts.clear()
	var death_archive := get_node_or_null("AdventureZombieDeathArchive") as AdventureZombieDeathArchive
	if death_archive != null:
		death_archive.clear_history()
	is_end_wave = false
	monster_mode = game_para.monster_mode
	if phase.kind == StagePhaseDefinition.Kind.TERMINAL:
		zombie_wave_manager.stop_wave_refresh()
		zombie_wave_manager.zombie_wave_create_manager.adventure_wave_profile = null
		zombie_wave_manager.curr_wave = -1
		zombie_wave_manager.max_wave = 0
		zombie_wave_manager.max_wave_one_round = 0
		zombie_wave_manager.flag_progress_bar.hide()
		check_zombie_end_wave_timer.start()
	else:
		zombie_wave_manager.begin_adventure_phase(phase.wave_profile)

## 开始第一波
func start_game():
	if not is_game_running() or _start_requested:
		return
	_start_requested = true
	# 等待完成后必须仍属于启动时的轮次。
	var round_generation: int = _round_generation
	_refresh_boss_progress()
	# Boss 生成与自然波次分开；正常模式继续首波计时，无出怪模式在生成后返回。
	if game_para.has_boss() and game_para.boss_spawn_wave == 0 and not _auto_boss_spawned:
		if create_boss() == null:
			return
	match monster_mode:
		ConstLevelData.E_MonsterMode.Null:
			if AdventureSession.owns_battle(game_para):
				main_game.adventure_runtime.start_phase()
			return

		ConstLevelData.E_MonsterMode.Norm:
			# 初代节奏的首波保护由波次管理器统一处理，普通入场与噩梦续战共用。
			if not zombie_wave_manager.uses_classic_spawn_timing():
				await get_tree().create_timer(10, false).timeout
			# 等待期间可能已经失败或离开关卡，不能让旧协程恢复后继续生成敌人。
			if round_generation == _round_generation and is_game_running():
				zombie_wave_manager.start_first_wave()

		ConstLevelData.E_MonsterMode.HammerZombie:
			await get_tree().create_timer(2, false).timeout
			if round_generation == _round_generation and is_game_running():
				hammer_zombie_manager.start_first_wave()


## 返回本管理器是否仍在树中、未排队删除且所属有效关卡处于正式战斗阶段。
## 供生成入口和波次延迟恢复共用；只查询所属关卡，不读取可能已切换的 Global.main_game。
func is_game_running() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() \
		and is_instance_valid(main_game) and not main_game.is_queued_for_deletion() \
		and main_game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME


## 返回本轮是否仍有登记的 Boss 死亡演出推迟战斗结算。
func has_pending_boss_defeat_presentation() -> bool:
	return not _pending_boss_defeat_presentations.is_empty()


## 若死亡演出仍在推进，则暂存 [param global_pos] 的普通奖杯请求并返回 true。
func defer_trophy_for_boss_defeat_presentation(global_pos: Vector2) -> bool:
	if not is_game_running() or not has_pending_boss_defeat_presentation():
		return false
	if not _deferred_round_trophy_position.is_finite():
		_deferred_round_trophy_position = global_pos
	return true


## [param boss] 是在当前场景等候结算的登记成员时允许继续演出。
## 额外 Boss 判胜已停刷但仍在等候奖杯时同样有效，玩家失败和场景卸载立即失效。
func allows_boss_defeat_presentation(boss: ZB000Base) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(main_game) \
			or main_game.is_queued_for_deletion() or get_tree().current_scene != main_game \
			or not is_instance_valid(boss) or not boss.is_death or not boss.is_inside_tree() \
			or boss.is_queued_for_deletion() \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false):
		return false
	var instance_id: int = boss.get_instance_id() # 演出许可仅授予本关死后仍保留登记的原实例。
	return _pending_boss_defeat_presentations.has(instance_id) and _get_registered_boss(instance_id) == boss \
		and (is_game_running() or (_boss_trophy_pending_id != 0 \
			and main_game.main_game_progress == MainGameManager.E_MainGameProgress.GAME_OVER))


## 自动入口按关卡配置只生成一次；卡牌生成不占用该记录，失败返回 null。
func create_boss() -> ZB000Base:
	if _auto_boss_spawned:
		return _get_registered_boss(_auto_boss_id)
	if not is_game_running() or not game_para.has_boss():
		return null
	if monster_mode != ConstLevelData.E_MonsterMode.Norm and monster_mode != ConstLevelData.E_MonsterMode.Null:
		return null
	# 自动实例与卡牌实例共用创建流程，但自动入口仍保持一次性。
	var boss: ZB000Base = BossSpawn.create(self, game_para.boss_type)
	if boss != null:
		_auto_boss_spawned = true
		_auto_boss_id = boss.get_instance_id()
	return boss


## 返回是否有空位且能在当前战场准备已注册的 [param boss_type]。
func can_summon_boss(boss_type: CharacterRegistry.ZombieBossType) -> bool:
	return has_enemy_slots(1) and BossSpawn.can_summon(self, boss_type)


## [param boss_type] 卡牌引用中的僵王类型；成功返回新实例，失败返回 null。[br]
## [param spawn_position] 可选的本地出生点；INF 使用关卡配置或自动分路。
func try_create_boss_from_card(boss_type: CharacterRegistry.ZombieBossType,
	spawn_position: Vector2 = Vector2.INF) -> ZB000Base:
	return BossSpawn.create(self, boss_type, spawn_position)


## [param encounter] 提供遭遇配置；[param on_registered] 在登记之后、正式入树之前连接观察者，避免遗漏入场帧的死亡。
func try_create_adventure_boss(encounter: BossEncounterDefinition, on_registered: Callable = Callable()) -> ZB000Base:
	return BossSpawn.create(self, encounter.boss_type, Vector2.INF, true, -1, INF, encounter, on_registered)

## [param boss_type] 从公共注册表取材；[param positions] 为同类型增援在僵王容器中的有限坐标。[param prepare] 在树外按顺序接收实例和序号，返回能否提交。
## [param commit_origin] 在整批完成入树、向遭遇及血条公开之前提交原体变化。失败返回空数组，不占用计数或触发离场。
func try_create_boss_reinforcements(boss_type: CharacterRegistry.ZombieBossType, positions: Array[Vector2],
		prepare: Callable, commit_origin: Callable) -> Array[ZB000Base]:
	return BossSpawn.create_reinforcements(self, boss_type, positions, prepare, commit_origin)


## [param boss] 已登记且尚未入树的默认出场实例；同帧首对按第 2、4 路分开。
## 跨帧增援只选择自己的位置，优先使用可用的第 4 路。
func place_boss_at_default_spawn(boss: ZB000Base) -> void:
	# 本次实例尚未入树，存活快照只包含更早入树的僵王。
	var others: Array[ZB000Base] = get_living_bosses()
	# 同一处理帧内，连续的生成调用视为同时登场。
	var frame: int = Engine.get_process_frames()
	# -1 保留单独登场时各僵王原有的出生点。
	var spawn_lane: int = -1
	if others.is_empty():
		_first_default_boss_id = boss.get_instance_id()
		_first_default_boss_frame = frame
	elif others.size() == 1 and frame == _first_default_boss_frame \
		and others[0].get_instance_id() == _first_default_boss_id \
		and all_zombie_rows.size() > BOSS_DUO_LANES.y:
		# 第一个实例可能已经开始入场，直接更新其脚底位置、待机点和层级。
		var first: ZB000Base = others[0]
		first.place_boss_at_spawn(self, first.get_default_boss_spawn_position(self, BOSS_DUO_LANES.x))
		spawn_lane = BOSS_DUO_LANES.y
	else:
		spawn_lane = choose_boss_lane(boss, BOSS_DUO_LANES.y)
	boss.place_boss_at_spawn(self, boss.get_default_boss_spawn_position(self, spawn_lane))


## [param world_y] 本体脚底的世界纵坐标；返回最接近的零起始行号，无行时为 -1。
func get_boss_lane_at_y(world_y: float) -> int:
	# 当前最接近的行和距离，依次扫描场地现有的出怪标记。
	var closest_lane: int = -1
	var closest_distance: float = INF
	for row_index: int in all_zombie_rows.size(): # 行索引从上到下。
		# 出怪点和脚底的垂直距离，单位像素。
		var distance: float = absf(world_y - all_zombie_rows[row_index].zombie_create_position.global_position.y)
		if distance < closest_distance:
			closest_distance = distance
			closest_lane = row_index
	return closest_lane


## [param boss] 正在选行的僵王。[br]
## [param preferred_lane] 可选的零起始行号，在同样空闲的候选中优先使用。[br]
## [param can_stay] 转场演出可保留当前行，普通换行排除当前行。
## 同时避让其他僵王的现行和预占行，所有行都有占用时选择占用最少的行。
## 场地没有其他可选行时，返回 [param boss] 的当前行。
func choose_boss_lane(boss: ZB000Base, preferred_lane: int = -1, can_stay: bool = false) -> int:
	# 每行的占用数，当前行和已预占的目标行分别计入。
	var lane_load: PackedInt32Array = []
	lane_load.resize(all_zombie_rows.size())
	for other: ZB000Base in get_living_bosses(): # 离场或死亡的实例不再预占行。
		if other == boss:
			continue
		if other.lane >= 0 and other.lane < lane_load.size():
			lane_load[other.lane] += 1
		if other.boss_target_lane != other.lane and other.boss_target_lane >= 0 \
			and other.boss_target_lane < lane_load.size():
			lane_load[other.boss_target_lane] += 1
	# 收集同为最低占用数的行，普通换行在其中随机选择。
	var candidates: Array[int] = []
	var min_load: int = 2147483647 # 首个有效候选一定会刷新此值。
	for row_index: int in lane_load.size(): # 场地零起始行号。
		if (not can_stay and row_index == boss.lane) or lane_load[row_index] > min_load:
			continue
		if lane_load[row_index] < min_load:
			candidates.clear()
			min_load = lane_load[row_index]
		candidates.append(row_index)
	if candidates.is_empty():
		return boss.lane
	return preferred_lane if candidates.has(preferred_lane) else candidates.pick_random()


## [param boss] 尚未入树或已挂在僵王根节点的正常出战实例。[br]
## [param boss_type] 保存时使用的注册类型；[param count_as_new] 是否增加累计生成数。
## 同一实例重复登记只返回 true，不重复连接信号或计数；不限制登记数量。
func register_boss(boss: ZB000Base, boss_type: CharacterRegistry.ZombieBossType, count_as_new: bool = true) -> bool:
	return register_boss_group([boss], boss_type, count_as_new)

## 原子登记 [param members] 中尚未登记的真实角色；[param boss_type] 与 [param count_as_new] 用于保存及计数。
## 先接入整组死亡和离树信号，再向正式遭遇交付成员；已在树内的外部实例同步刷新。
func register_boss_group(members: Array[ZB000Base], boss_type: CharacterRegistry.ZombieBossType,
		count_as_new: bool = true) -> bool:
	if members.is_empty():
		return false
	var pending: Dictionary[int, ZB000Base] = {} # 集中保存本次尚未登记的唯一实例。
	var in_tree := false # 已经入树的外部成员不再经过工厂最后的发布。
	for member: Variant in members: # 外部传入已释放对象时不能先强转为角色。
		if not is_instance_valid(member) or member.is_queued_for_deletion():
			return false
		var boss := member as ZB000Base # 数组元素类型已约束为公共 Boss 类型。
		var id: int = boss.get_instance_id() # 已登记实例重复提交不再次占用名额。
		if _registered_bosses.has(id) or pending.has(id):
			continue
		if not is_game_running() or boss.is_death or boss.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
				or not Global.character_registry.ZombieBossInfo.has(boss_type) \
				or (boss.get_parent() != null and boss.get_parent() != zombie_boss_root):
			return false
		pending[id] = boss
		in_tree = in_tree or boss.is_inside_tree()
	if not has_enemy_slots(pending.size()):
		return false
	for boss: ZB000Base in pending.values(): # 完成整批计数之后，才可向遭遇观察者交付。
		_register_new_boss(boss, boss_type, count_as_new)
	for member: Variant in pending.values(): # 前一条同步通知可能使其他成员离场。
		if is_instance_valid(member):
			boss_member_registered.emit(member)
	if in_tree:
		publish_boss_spawns([]) # 观察者接入后再通知已入树角色的音乐和血条。
	return true

## [param members] 已完成入树和出场配置；统一通知战斗音乐及总血条，再为仍存活的成员排入修改器命令。
func publish_boss_spawns(members: Array[ZB000Base]) -> void:
	signal_living_bosses_changed.emit()
	_refresh_boss_progress()
	if cheat_instant_kill_enabled:
		for member: Variant in members: # 同步的观察者可能已完成击杀或释放。
			if is_instance_valid(member) and not member.is_death and not member.is_queued_for_deletion():
				_apply_registered_boss_cheat.call_deferred(member.get_instance_id())

## [param id] 在入场发布时登记；延迟一步后重新取仍存在的实体，避免向修改器传入失效对象。
func _apply_registered_boss_cheat(id: int) -> void:
	var boss: ZB000Base = _get_registered_boss(id) # 离场或切关后不再执行本次命令。
	if boss != null:
		_apply_cheat_instant_kill(boss)

## 为已预检且尚未登记的 [param boss] 接线计数；[param boss_type] 与 [param count_as_new] 沿用单体创建语义。
func _register_new_boss(boss: ZB000Base, boss_type: CharacterRegistry.ZombieBossType, count_as_new: bool) -> void:
	var instance_id: int = boss.get_instance_id() # 单体与整批都以真实实例为唯一键。
	_registered_bosses[instance_id] = weakref(boss)
	_counted_boss_ids[instance_id] = true
	_boss_types[instance_id] = boss_type
	if count_as_new:
		_boss_spawn_total += 1
	if not boss.is_node_ready():
		boss.ready.connect(BossTrace.member.bind(&"ready", boss, self), CONNECT_ONE_SHOT)
	boss.signal_character_death.connect(_on_boss_dead.bind(instance_id))
	boss.signal_boss_phase_changed.connect(_on_registered_boss_phase_changed.bind(instance_id))
	boss.signal_trophy_requested.connect(_on_boss_trophy_requested.bind(instance_id))
	boss.tree_exiting.connect(_on_boss_tree_exiting.bind(instance_id))
	curr_zombie_num += 1
	BossTrace.member(&"registered", boss, self)


## Shared Boss phase audio is routed once through the already-registered Boss lifecycle.
## The base class only emits the phase signal; SoundManager remains a service of the game manager.
func _on_registered_boss_phase_changed(_phase: int, instance_id: int) -> void:
	var boss: ZB000Base = _get_registered_boss(instance_id) # 发出阶段信号的登记实例。
	if boss == null or boss.is_death or not boss.play_phase_roar_on_threshold or not is_game_running():
		return
	SoundManager.play_boss_phase_roar()


## [param instance_id] 发出死亡通知的登记实例；重复通知不再次扣数或累计死亡。
## 先检查原有清场条件，再检查额外 Boss 条件；只有实际接受 Boss 胜利才停止刷新并等待演出。
## 单轮全部僵王死亡满足胜利条件时先判胜，已进入结算则保留僵王音乐。
func _on_boss_dead(instance_id: int) -> void:
	# 先验证弱引用，再访问角色死亡状态。
	var boss: ZB000Base = _get_registered_boss(instance_id)
	if boss == null or not boss.is_death or not _counted_boss_ids.erase(instance_id):
		return
	_boss_dead_total += 1
	# 在可能结束战斗前结算真身死亡；召唤物和设施不会登记为 Boss 本体。
	if is_game_running():
		if boss.delays_victory_for_defeat_presentation():
			_pending_boss_defeat_presentations[instance_id] = true
		var group: int = boss.boss_encounter_group_id() # 分裂前后的同一遭遇只允许完成一次奖励。
		var reward_ready: bool = group == 0 or _is_boss_group_defeated(group) # 独立死亡仍计数，最后一名才提交整组奖励。
		if main_game.preview_return_scene.is_empty():
			if reward_ready and is_instance_valid(main_game.drop_item_manager):
				if boss.drop_diamond_after_presentation():
					_pending_boss_diamonds[instance_id] = true
				else:
					var origin: Vector2 = boss.trophy_spawn_point.global_position if is_instance_valid(boss.trophy_spawn_point) \
						else boss.global_position # 无独立演出的 Boss 仍在死亡帧掉落。
					main_game.drop_item_manager.spawn_boss_diamond(origin)
			if not game_para.is_zombie_mode:
				Global.record_zombie_defeat()
		if reward_ready:
			Global.record_quest_event("boss_defeated")
	curr_zombie_num -= 1
	BossTrace.member(&"death", boss, self)
	# 单轮启用死亡胜利且全部僵王已击杀时，延后音乐通知，避免获胜前短暂切回原曲。
	var defer_bgm_update: bool = game_para.game_round == 1 and game_para.win_on_boss_death \
		and _boss_spawn_total > 0 and _boss_dead_total == _boss_spawn_total
	if not defer_bgm_update:
		# 多轮或仍需继续战斗时，先恢复原曲，再允许胜利判断切到结算阶段。
		signal_living_bosses_changed.emit()
	# 普通清场沿用原入口，已登记的等待演出由该入口暂缓。
	var awaiting_wave_clear: bool = has_pending_boss_defeat_presentation() and is_end_wave and curr_zombie_num == 0 # 保留同帧普通清场的优先级。
	_try_finish_wave(boss.global_position)
	if game_para.win_on_boss_death and not awaiting_wave_clear and is_game_running() \
		and _boss_spawn_total > 0 and _boss_dead_total == _boss_spawn_total \
		and main_game.try_claim_round_end(true):
		_boss_trophy_pending_id = instance_id
		# 不暂停场景树、不直接通关，也不改变现有僵尸进房等失败入口。
		main_game.main_game_progress = MainGameManager.E_MainGameProgress.GAME_OVER
		# 停止两种波次入口；无出怪模式的场外清理在死亡演出期间继续运行。
		zombie_wave_manager.stop_wave_refresh()
		hammer_zombie_manager.stop_wave_refresh()
		if monster_mode == ConstLevelData.E_MonsterMode.Norm:
			check_zombie_end_wave_timer.stop()
		if is_instance_valid(multi_round_end_wave_timer):
			multi_round_end_wave_timer.stop()
	if defer_bgm_update:
		# 获胜后阶段过滤会保留僵王曲目；若未实际获胜，仍按存活快照恢复原曲。
		signal_living_bosses_changed.emit()
	_refresh_boss_progress()


## [param global_pos] 死亡动画或直接消失接口请求的奖杯生成位置，使用世界坐标。
## [param instance_id] 发出请求的登记实例；只完成已接受的 Boss 胜利，且每轮最多请求一次。
func _on_boss_trophy_requested(global_pos: Vector2, instance_id: int) -> void:
	var boss: ZB000Base = _get_registered_boss(instance_id) # 先确认请求来自仍在树中的原登记实例。
	BossTrace.member(&"presentation_complete", boss, self)
	if _pending_boss_diamonds.erase(instance_id) and is_instance_valid(main_game) \
			and not main_game.is_queued_for_deletion() and is_instance_valid(main_game.drop_item_manager):
		main_game.drop_item_manager.spawn_boss_diamond(global_pos)
	if boss == null or not boss.is_death \
		or boss.is_queued_for_deletion() or not boss.is_inside_tree():
		return
	var finished_presentation: bool = _pending_boss_defeat_presentations.erase(instance_id) # 同一实例只解除一次等待。
	if game_para.win_on_boss_death and instance_id == _boss_trophy_pending_id:
		_boss_trophy_pending_position = global_pos
	_try_complete_boss_victory()
	if finished_presentation and is_game_running():
		# 正式遭遇也监听这次请求，交给同步退出通知先更新胜利条件。
		_resume_round_after_boss_presentation.call_deferred(global_pos)


## 额外 Boss 胜利已接受且奖杯已请求时，等所有登记演出完成才结算。
func _try_complete_boss_victory() -> void:
	if _boss_trophy_pending_id == 0 or _boss_trophy_created or not _boss_trophy_pending_position.is_finite() \
		or has_pending_boss_defeat_presentation() or not is_inside_tree() or is_queued_for_deletion() \
		or not is_instance_valid(main_game) or main_game.is_queued_for_deletion() or not main_game.is_inside_tree() \
		or main_game.main_game_progress != MainGameManager.E_MainGameProgress.GAME_OVER \
		or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false):
		return
	var global_pos: Vector2 = _boss_trophy_pending_position # 最后死亡实例提交的奖杯落点。
	_boss_trophy_created = true
	_boss_trophy_pending_id = 0
	_boss_trophy_pending_position = Vector2.INF
	# Boss 死亡时已接受胜利，演出结束只完成结算，不能再次调用普通判胜入口。
	main_game.complete_boss_victory(global_pos)


## 以 [param global_pos] 复核因死亡演出暂缓的清场和轮间过渡。
func _resume_round_after_boss_presentation(global_pos: Vector2) -> void:
	if not is_game_running() or has_pending_boss_defeat_presentation() or get_tree().current_scene != main_game:
		return
	var requested_position: Vector2 = _deferred_round_trophy_position # 遭遇编排器可直接提交普通胜利请求。
	_deferred_round_trophy_position = Vector2.INF
	if requested_position.is_finite():
		main_game.create_trophy(requested_position)
	_try_finish_wave(global_pos)
	if _next_round_waiting_for_boss_presentation:
		_on_trigger_start_next_round_game()


## [param instance_id] 即将离树的登记实例；只移除自身引用和计数，直接移除不计为击杀。
func _on_boss_tree_exiting(instance_id: int) -> void:
	var departing: ZB000Base = _get_registered_boss(instance_id) # 先读取离场成员，因为本步随后会撤销登记。
	BossTrace.member(&"tree_exit", departing, self)
	_pending_boss_diamonds.erase(instance_id)
	var released_presentation: bool = _pending_boss_defeat_presentations.erase(instance_id) # 演出被清场也不占用过渡。
	_registered_bosses.erase(instance_id)
	_boss_types.erase(instance_id)
	if _counted_boss_ids.erase(instance_id):
		if is_instance_valid(departing) and not departing.is_death and is_game_running():
			var group: int = departing.boss_encounter_group_id() # 自然离场与实际造成的死亡分开计算。
			if group != 0:
				_escaped_boss_groups[group] = true
		curr_zombie_num -= 1
		# 未死亡的直接移除也解除音乐覆盖；死亡后的离树不再重复通知。
		signal_living_bosses_changed.emit()
	if _boss_trophy_pending_id == instance_id and not _boss_trophy_pending_position.is_finite():
		_boss_trophy_pending_id = 0
	if released_presentation:
		_try_complete_boss_victory()
	_refresh_boss_progress()
	# 逃跑通过树退出解除实体登记；若它恰好是末波最后一个敌人，需重新请求清场判定。
	# Boss 结果尚未交给 Director 时 can_accept_victory 会拒绝，之后 idle 再次复核。
	if is_game_running():
		var global_pos: Vector2 = main_game.camera_2d.get_screen_center_position() # 演出中断时使用当前镜头位置。
		if released_presentation:
			_resume_round_after_boss_presentation.call_deferred(global_pos)
		else:
			_try_finish_wave(global_pos)

## [param group] 中每个成员均确认击杀才允许结算，包含同帧排队移出的活体。
func _is_boss_group_defeated(group: int) -> bool:
	if _escaped_boss_groups.has(group):
		return false
	for id: int in _counted_boss_ids: # 已确认死亡的成员在进入奖励判断前就离开此集合。
		var member: ZB000Base = _get_registered_boss(id) # 排队释放仍是有效的未击杀实例。
		if member != null and member.boss_encounter_group_id() == group:
			return false
	return true


## [param instance_id] 本局实例 ID；返回仍有效的登记僵王，已释放或未登记时返回 null。
func _get_registered_boss(instance_id: int) -> ZB000Base:
	if not _registered_bosses.has(instance_id):
		return null
	# 弱引用先保持 Variant，避免已释放对象传入强类型入口。
	var boss = _registered_bosses[instance_id].get_ref()
	return boss as ZB000Base if is_instance_valid(boss) else null


## 返回按登记顺序排列的存活实例快照；调用方可以遍历施加效果，不持有管理器内部集合。
func get_living_bosses() -> Array[ZB000Base]:
	# 快照只收集仍计入场上敌方的有效实例。
	var bosses: Array[ZB000Base] = []
	# 登记顺序决定屏幕底部血条的排列顺序。
	for instance_id: int in _registered_bosses:
		# 死亡演出仍可登记，但不进入存活快照。
		var boss: ZB000Base = _get_registered_boss(instance_id)
		if _counted_boss_ids.has(instance_id) and boss != null and not boss.is_death \
			and boss.is_inside_tree() and not boss.is_queued_for_deletion():
			bosses.append(boss)
	return bosses

## 返回 [param boss_type] 的首个存活实例，本场没有该类型时返回 null。
func get_living_boss_of_type(boss_type: CharacterRegistry.ZombieBossType) -> ZB000Base:
	for boss: ZB000Base in get_living_bosses(): # 使用与血条、音乐一致的存活快照。
		if _boss_types.get(boss.get_instance_id()) == boss_type:
			return boss
	return null


## 生命周期变化后同步各存活实例的血条；场景卸载时不访问已退出的 UI。
func _refresh_boss_progress() -> void:
	if is_instance_valid(main_game) and is_instance_valid(main_game.level_info) \
		and main_game.level_info.is_inside_tree() and not main_game.level_info.is_queued_for_deletion():
		main_game.level_info.refresh_boss_progress(
			get_living_bosses(), _boss_trophy_pending_id != 0 or _boss_trophy_created,
			monster_mode != ConstLevelData.E_MonsterMode.Null and is_game_running()
		)


## 返回存活僵王及累计结算数据；待恢复的缓存原样复制，避免选卡前再次保存时覆盖为空。
func get_save_game_data_bosses() -> Dictionary:
	if not _saved_boss_data.is_empty():
		return _saved_boss_data.duplicate(true)
	# 只保存正常存活角色，不保存死亡演出或具体技能阶段。
	var living_bosses: Array[Dictionary] = []
	# 每只角色保留类型、生命值、本地位置、待机横坐标及自动入口归属。
	for boss: ZB000Base in get_living_bosses():
		# 运行时 ID 不写入存档，仅用于查找本次实例的元数据。
		var instance_id: int = boss.get_instance_id()
		# 待机横坐标转换为与当前位置相同的根节点本地坐标。
		var snapshot: Dictionary = {"boss_type": _boss_types[instance_id], "hp": boss.hp_component.curr_hp,
			"position": boss.position, "is_auto": instance_id == _auto_boss_id}
		if is_finite(boss.boss_home_x):
			snapshot["home_x"] = zombie_boss_root.to_local(Vector2(boss.boss_home_x, boss.global_position.y)).x
		living_bosses.append(snapshot)
	return {"living_bosses": living_bosses, "spawn_total": _boss_spawn_total,
		"dead_total": _boss_dead_total, "auto_spawned": _auto_boss_spawned}


## [param data] 可选僵王存档数据；仅暂存，正式战斗开始时再恢复，旧存档传空字典即可。
func load_game_data_bosses(data: Dictionary) -> void:
	_saved_boss_data = data.duplicate(true)


## 正式战斗开始后一次性恢复存活实例及累计记录；新实例从完整入场动作开始，不重复计数。
func restore_saved_bosses() -> void:
	if _saved_boss_data.is_empty() or not is_game_running():
		return
	# 消费一次缓存；恢复失败不会由后续开战调用重复生成。
	var data: Dictionary = _saved_boss_data
	_saved_boss_data = {}
	_boss_spawn_total = maxi(int(data.get("spawn_total", 0)), 0)
	_boss_dead_total = clampi(int(data.get("dead_total", 0)), 0, _boss_spawn_total)
	_auto_boss_spawned = bool(data.get("auto_spawned", false))
	# 存档仅记录存活角色，恢复时分配新的实例 ID。
	for snapshot: Dictionary in data.get("living_bosses", []):
		# 保存的类型、剩余生命与本地位置，缺少关键字段时拒绝恢复该条目。
		var boss_type: CharacterRegistry.ZombieBossType = snapshot.get("boss_type", CharacterRegistry.ZombieBossType.Null)
		# 0 血量不恢复为存活角色。
		var hp: int = snapshot.get("hp", 0)
		# 根节点本地坐标，避免恢复时受相机或父节点世界位置影响。
		var spawn_position: Vector2 = snapshot.get("position", Vector2.INF)
		# 旧存档缺少待机横坐标时，按关卡配置或原行的默认右侧待机点恢复。
		var home_x: float = snapshot.get("home_x", INF)
		if hp <= 0:
			continue
		# 恢复使用同一生成流程，但累计生成数已经从存档读取。
		var boss: ZB000Base = BossSpawn.create(self, boss_type, spawn_position, false, hp, home_x)
		if boss == null:
			push_error("ZombieManager：无法恢复存档中的僵王：%s。" % boss_type)
			continue
		if snapshot.get("is_auto", false):
			_auto_boss_id = boss.get_instance_id()
	_refresh_boss_progress()


## 我是僵尸轮间清场时一并移除僵王；清场不产生击杀或奖杯，下一轮重新累计。
func _clear_bosses_for_next_round() -> void:
	# 在清空登记前收集所有有效实例，包括尚未离树的死亡演出。
	var bosses: Array[ZB000Base] = []
	# 逐个查找弱引用，跳过已经释放的实例。
	for instance_id: int in _registered_bosses:
		# 本次准备移除的角色。
		var boss: ZB000Base = _get_registered_boss(instance_id)
		if boss != null:
			bosses.append(boss)
	curr_zombie_num -= _counted_boss_ids.size()
	_counted_boss_ids.clear()
	_registered_bosses.clear()
	_boss_types.clear()
	_saved_boss_data.clear()
	_auto_boss_spawned = false
	_auto_boss_id = 0
	_boss_spawn_total = 0
	_boss_dead_total = 0
	_pending_boss_diamonds.clear()
	_escaped_boss_groups.clear()
	# 信号在离树时仍可能执行，但集合已清空，不会再次扣减敌方数量。
	for boss: ZB000Base in bosses:
		boss.queue_free()
	# 整批清场后同步一次；重选卡阶段由关卡保留选卡音乐。
	signal_living_bosses_changed.emit()
	_refresh_boss_progress()

#region 生成僵尸
## 判断指定类型能否放入目标行，不改变选行历史和场上计数。[br]
## [param zombie_type] 角色注册表中的僵尸类型。[br]
## [param lane] 从 0 开始的目标行号；不存在的行或不兼容的水陆类型返回 false。
func can_spawn_zombie_in_lane(zombie_type: CharacterRegistry.ZombieType, lane: int) -> bool:
	if not is_lane_open(lane) or lane >= all_zombies_2d.size():
		return false
	# 目标行及出生点必须仍属于有效场景，避免使用已卸载的行数据。
	var row: ZombieRow = all_zombie_rows[lane]
	if not is_instance_valid(row) or not row.is_inside_tree() or row.is_queued_for_deletion() \
		or not is_instance_valid(row.zombie_create_position):
		return false
	if zombie_type == 0 or not Global.character_registry.ZombieInfo.has(zombie_type):
		return false
	# 注册场景必须可以实例化，空类型不会进入通用创建入口。
	var scene: PackedScene = Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieScenes) as PackedScene
	if scene == null or not scene.can_instantiate():
		return false
	var row_type: CharacterRegistry.ZombieRowType = Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType)
	return ZombieRow.supports_spawn(row_type, row.zombie_row_type) \
		and (zombie_type != CharacterRegistry.ZombieType.Z039CannonTurret or _has_cannon_turret_slot(lane))


## [param lane] 为已确认开放的目标行。只有有停车格且无存活炮塔的行允许新炮塔入场。
func _has_cannon_turret_slot(lane: int) -> bool:
	if main_game.board == null or main_game.board.row_cells(lane).is_empty():
		return false
	for child: Node in all_zombie_rows[lane].get_children(): # 行子节点覆盖已魅惑及正在入树登记的炮车。
		var zombie := child as Zombie000Base # 跳过出怪锚点和场景特效。
		if zombie != null and zombie.zombie_type == CharacterRegistry.ZombieType.Z039CannonTurret \
				and not zombie.is_death and not zombie.is_queued_for_deletion():
			return false
	return true

## [param lane] 是由零起算的攻击行；不存在、正在脱落或已释放的行不能进入。
func is_lane_open(lane: int) -> bool:
	if lane < 0 or lane >= all_zombie_rows.size():
		return false
	var row: ZombieRow = all_zombie_rows[lane] # 陆地和水路共用入口。
	return is_instance_valid(row) and not row.is_falling and not row.is_queued_for_deletion()

## 技能生成入口：使用释放点 X 和目标行基准 Y，登记与计数复用普通创建流程。[br]
## [param zombie_type] 本次准备阶段锁定的僵尸类型。[br]
## [param lane] 本次准备阶段锁定的目标行号，从 0 开始。[br]
## [param spawn_x] 普通入树脚点的全局 X 坐标；非法坐标或关卡已结束时返回 null。
## [param tier_id] 非空时在入树前应用指定等阶。
## [param replaces] 可将临终且已登记的母体名额交给首只成功后代；默认不转移名额。
## [param initialize] 可在入树前设置技能生成特有的初始姿态。
func create_skill_zombie(zombie_type: CharacterRegistry.ZombieType, lane: int, spawn_x: float,
		tier_id: StringName = &"", replaces: Zombie000Base = null,
		initialize: Callable = Callable()) -> Zombie000Base:
	if not is_game_running() or not is_finite(spawn_x) or not can_spawn_zombie_in_lane(zombie_type, lane):
		return null
	# 新僵尸挂载到实际目标行，继续沿用该行的绘制层级和后续换行规则。
	var row: ZombieRow = all_zombie_rows[lane]
	# 此处只取标准行高；屋顶坡面高度由僵尸 ready_norm() 根据 X 修正一次。
	var spawn_position := Vector2(spawn_x, row.zombie_create_position.global_position.y)
	if not spawn_position.is_finite():
		return null
	# -1 表示技能生成，不归属自然波次，也不接入自然波次的掉血刷新统计。
	var init_parameters: Dictionary = {
		Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane: lane,
		Zombie000Base.E_ZInitAttr.CurrWave: -1,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}
	var modifier: ZombieSpawnModifier = null if tier_id.is_empty() else AdventureZombieTierBinding.new(tier_id) # 冒险遭遇可统一技能援军的等阶。
	return create_norm_zombie(zombie_type, row, init_parameters, spawn_position, initialize, modifier, null, replaces)


## 在 [param lane]（从零开始）的 [param ground_position] 世界脚点生成救主随从。[param replaces] 提供转换原体的在场名额。
## 成功返回已登记的实例；战场、位置或名额不可用时返回 null。随从不参与自然波次统计。
func create_savior_follower(lane: int, ground_position: Vector2, replaces: Zombie000Base = null) -> Zombie000Base:
	if not is_game_running() or not ground_position.is_finite() \
			or not can_spawn_zombie_in_lane(CharacterRegistry.ZombieType.Z001Norm, lane):
		return null
	var scene := load("res://scenes/character/zombie/savior_follower.tscn") as PackedScene # 只在救主实际召唤时加载。
	if scene == null or not scene.can_instantiate():
		return null
	var row: ZombieRow = all_zombie_rows[lane] # 挂到原行以共用绘制、投影和战场统计。
	var spawn_position: Vector2 = ground_position # 初始化会补上屋顶坡面高度，传入值先扣除同一偏移。
	if is_instance_valid(main_game.main_game_slope):
		var slope_y: float = main_game.main_game_slope.get_all_slope_y(ground_position.x) # 普通僵尸入树时使用的局部高度。
		spawn_position -= row.global_transform.basis_xform(Vector2(0.0, slope_y))
	var init_parameters: Dictionary = { # 黑影是全尺寸的普通敌方角色，没有自然出生波次。
		Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane: lane,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: row.zombie_row_type,
		Zombie000Base.E_ZInitAttr.IsMiniZombie: false,
		Zombie000Base.E_ZInitAttr.IsZombieMode: false,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}
	return create_norm_zombie(CharacterRegistry.ZombieType.Z001Norm, row, init_parameters,
		spawn_position, Callable(), null, scene, replaces)


## 创建技能召唤的蹦极僵尸，目标在入树前注入；失败时返回 null。[br]
## [param target_cell] 目标格子，其行号使用项目内部的零起始索引。[br]
## [param anchor] 本列对应的博士手部绳子连接点，入树前与目标一起注入。[br]
## [param on_created] 可选初始化回调，接收僵尸实例；用于在入树前监听本批完成事件。
func create_skill_bungi(target_cell: PlantCell, anchor: Marker2D, on_created: Callable = Callable()) -> Zombie021Bungi:
	if not is_game_running() or not is_instance_valid(target_cell) \
		or target_cell.is_queued_for_deletion() or not target_cell.is_inside_tree() \
		or not main_game.is_ancestor_of(target_cell) or target_cell.get_bungi_target() == null:
		return null
	# 目标所在行，不使用展示用的一起始行号。
	var lane: int = target_cell.combat_lane
	if not can_spawn_zombie_in_lane(CharacterRegistry.ZombieType.Z021Bungi, lane):
		return null
	# 父节点沿用实际僵尸行，保持现有行层级和死亡登记方式。
	var row: ZombieRow = all_zombie_rows[lane]
	# 根节点使用落点基准；身体上方偏移由蹦极自身处理，坡面由 ready_norm 修正一次。
	var spawn_position: Vector2 = target_cell.get_spawn_global_position() # 当前地块脚点。
	if not spawn_position.is_finite():
		return null
	# 技能生成不归属自然波次，但仍正常计入场上僵尸数量。
	var init_parameters: Dictionary = {
		Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane: lane,
		Zombie000Base.E_ZInitAttr.CurrWave: -1,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	}
	return create_norm_zombie(CharacterRegistry.ZombieType.Z021Bungi, row, init_parameters,
		spawn_position, _initialize_skill_bungi.bind(target_cell, anchor, on_created)) as Zombie021Bungi


## [param zombie] 刚实例化且尚未入树的蹦极僵尸。[br]
## [param target_cell] 本轮锁定的格子。[br]
## [param anchor] 本列对应的博士手部绳子连接点。[br]
## [param on_created] 技能提供的实例监听回调；先统一注入出战参数，再交给调用方登记。
func _initialize_skill_bungi(zombie: Zombie021Bungi, target_cell: PlantCell, anchor: Marker2D, on_created: Callable) -> void:
	# 博士已经通过进入动画表现召唤，蹦极入树后隐藏靶子并立即下降。
	zombie.initialize_spawn(target_cell, true, anchor)
	if on_created.is_valid():
		on_created.call(zombie)


## 生成并登记一个正常出战僵尸。[br]
## [param zombie_type] 为角色注册类型，[param zombie_parent] 为持有实例的行节点。[br]
## [param zombie_init_para] 为僵尸初始化参数，[code]StartsHypnotized[/code] 为真时直接登记为友军。[br]
## [param global_pos] 为入树前使用的世界出生点。[br]
## [param init_zombie_special] 在入树前注入特殊参数，[param spawn_modifier] 可替换默认的外观绑定。[br]
## [param scene_override] 允许未注册的技能变体复用出战流程；场景需以僵尸为根且自行提供外观。[br]
## [param replaces] 提供已登记旧敌人的名额，由调用方在新体登记成功后注销旧体。[br]
## 敌方无空位或友军无法完成初始魅惑时返回 null。
func create_norm_zombie(
	zombie_type:CharacterRegistry.ZombieType,
	zombie_parent:Node,
	zombie_init_para:Dictionary,
	global_pos:Vector2=Vector2.ZERO,
	init_zombie_special:Callable = Callable(),
	spawn_modifier: ZombieSpawnModifier = null,
	scene_override: PackedScene = null,
	replaces: Zombie000Base = null
) -> Zombie000Base:
	# 初始阵营决定是否需要敌方名额。
	var starts_hypnotized: bool = zombie_init_para.get(Zombie000Base.E_ZInitAttr.StartsHypnotized, false)
	var transfers_slot: bool = not starts_hypnotized and max_live_enemies > 0 \
		and is_instance_valid(replaces) # 限量战场的敌方转换可沿用旧敌人名额。
	if transfers_slot:
		if not all_zombies_1d.has(replaces) or all_zombies_be_hypno.has(replaces) or _transferred_enemy_slots.has(replaces):
			return null
	elif not starts_hypnotized and available_zombie_slots(1) == 0:
		return null
	var scene: PackedScene = scene_override # 技能变体使用单独场景，普通出战实体继续查注册表。
	if scene == null:
		scene = Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieScenes)
	# 新实例入树前由初始化参数确定刷新归属；博士来源不会登记到自然刷新集合。
	var zombie: Zombie000Base = scene.instantiate()
	var spawn_parameters: Dictionary = zombie_init_para.duplicate(true) # 补齐本场默认参数时保留调用方字典。
	# 石像与运输舰以实际种植点的攻防行登记。
	var transport := zombie as Zombie040TransportAirship
	if (zombie_type == CharacterRegistry.ZombieType.Z028StoneStatue or transport != null) \
			and spawn_parameters.get(Zombie000Base.E_ZInitAttr.CharacterInitType, Character000Base.E_CharacterInitType.IsNorm) == Character000Base.E_CharacterInitType.IsNorm:
		var cell: PlantCell = _pick_transport_airship_cell(transport) if transport != null else _pick_stone_statue_spawn_cell() # 选中本场有效种植点。
		if cell == null:
			zombie.free()
			return null
		spawn_parameters[Zombie000Base.E_ZInitAttr.Lane] = cell.combat_lane
		spawn_parameters[Zombie000Base.E_ZInitAttr.CurrZombieRowType] = cell.get_spawn_terrain_type()
		zombie_parent = all_zombie_rows[cell.combat_lane]
		global_pos = cell.get_spawn_global_position()
	var spawn_row := zombie_parent as ZombieRow # 预览实例可能没有正式攻击行。
	if spawn_row != null and spawn_row.is_falling:
		zombie.free()
		return null
	if not spawn_parameters.has(Zombie000Base.E_ZInitAttr.IsMiniZombie):
		spawn_parameters[Zombie000Base.E_ZInitAttr.IsMiniZombie] = game_para.is_mini_zombie
	if not spawn_parameters.has(Zombie000Base.E_ZInitAttr.IsZombieMode):
		spawn_parameters[Zombie000Base.E_ZInitAttr.IsZombieMode] = game_para.is_zombie_mode

	zombie.init_zombie(spawn_parameters)
	# A typed spawn modifier is validated separately from one-off entity setup.
	if spawn_modifier != null:
		if not spawn_modifier.apply(zombie):
			zombie.free()
			return null
		zombie.combat_spawn_modifier = spawn_modifier
	elif scene_override == null:
		apply_spawn_appearance(zombie, &"")
	if not init_zombie_special.is_null():
		init_zombie_special.call(zombie)
	# 玩家放置、波次和技能都在实际入树前检查名额，预检查与创建之间允许其他生成先占行。
	if zombie.zombie_type == CharacterRegistry.ZombieType.Z039CannonTurret \
			and zombie.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
			and (not can_spawn_zombie_in_lane(zombie.zombie_type, zombie.lane) \
				or zombie_parent != all_zombie_rows[zombie.lane]):
		zombie.free()
		return null
	var parent_canvas: CanvasItem = zombie_parent as CanvasItem # 陆地行是 Node2D，旧泳池水行是 Panel，统一使用画布变换。
	if parent_canvas == null:
		zombie.free()
		push_error("僵尸创建失败：父节点必须提供 CanvasItem 坐标变换")
		return null
	zombie.position = parent_canvas.get_global_transform().affine_inverse() * global_pos
	zombie_parent.add_child(zombie)
	# 角色就绪后先完成朝向、受击层和索敌切换，在发布前登记实际阵营。
	if starts_hypnotized and not zombie.is_hypno:
		zombie.be_hypno()
		if not zombie.is_hypno:
			zombie.queue_free()
			return null

	# 生命周期信号与登记绑定，直接离树也必须在节点失效前注销。
	zombie.signal_character_death.connect(_on_zombie_dead.bind(zombie))
	zombie.signal_character_be_hypno.connect(_on_zombie_hypno.bind(zombie))
	zombie.tree_exiting.connect(_on_zombie_tree_exiting.bind(zombie))
	zombie.signal_lane_update.connect(zombie_update_lane.bind(zombie, zombie.lane))

	all_zombies_1d.append(zombie)

	if zombie.is_hypno:
		all_zombies_be_hypno.append(zombie)
	else:
		all_zombies_2d[zombie.lane].append(zombie)
		if transfers_slot and is_instance_valid(replaces) and all_zombies_1d.has(replaces) \
				and not all_zombies_be_hypno.has(replaces):
			_transferred_enemy_slots[replaces] = true
		else:
			curr_zombie_num += 1
		_register_natural_refresh_zombie(zombie)
	signal_zombie_created.emit(zombie)
	if cheat_instant_kill_enabled and not zombie.is_hypno:
		_apply_cheat_instant_kill.call_deferred(zombie)

	return zombie


## 依据存活登记返回是否还能容纳 [param count] 个新敌人。僵王登记使用实际空位。
func has_enemy_slots(count: int) -> bool:
	return max_live_enemies <= 0 or curr_zombie_num + count <= max_live_enemies

## 从 [param requested] 个新增普通敌人的名额中返回可用数量，扣除 Boss 待入场的分身名额。
func available_zombie_slots(requested: int) -> int:
	if max_live_enemies <= 0:
		return requested
	var remaining: int = max_live_enemies - curr_zombie_num # 先扣除全场已经登记的存活敌人。
	if remaining <= 0:
		return 0
	for boss: ZB000Base in get_living_bosses(): # 已在场的僵王可临时为尚未登场的分身留位。
		remaining -= boss.reserved_enemy_spawn_slots()
	return clampi(remaining, 0, requested)

## 从第 4 列起的全部有效格等概率选取石像出生点；保留水格及已有植物的格子。
## 返回仍属于本战场的地块，无候选时返回 null；只查询空间，不改变植物或地形占用。
func _pick_stone_statue_spawn_cell() -> PlantCell:
	if not is_instance_valid(main_game) or not is_instance_valid(main_game.plant_cell_manager):
		return null
	var board: BoardRuntime = main_game.plant_cell_manager.board # 实际地块索引，避免按矩阵范围补出不存在的格子。
	if board == null or not board.configured:
		return null
	var candidates: Array[PlantCell] = [] # 每格只入选一次，不按行长度或出怪权重二次加权。
	for cell: PlantCell in board.cells(): # 列号从零开始，前三列对应 0、1、2。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_inside_tree() \
				or not cell.is_visible_in_tree() or cell.row_col.y < 3 \
				or cell.board != board or board.cell_by_id(cell.cell_id) != cell \
				or not main_game.is_ancestor_of(cell):
			continue
		if can_spawn_zombie_in_lane(CharacterRegistry.ZombieType.Z028StoneStatue, cell.combat_lane) \
				and cell.get_spawn_global_position().is_finite():
			candidates.append(cell)
	return candidates.pick_random() if not candidates.is_empty() else null


## 在倒数第五至倒数第二列中，为 [param transport] 等概率预留一条无碰撞的下降路线。
## 没有安全格子时返回 null，生成器不登记本次出怪。
func _pick_transport_airship_cell(transport: Zombie040TransportAirship) -> PlantCell:
	var board: BoardRuntime = main_game.board # 运行时索引记录真实列号以及移动格子的当前攻防行。
	if board == null or not board.configured:
		return null
	var occupied: Array[Rect2] = [] # 检查实际机体和入场通道，不依赖移动甲板的逻辑格号。
	for row: ZombieRow in all_zombie_rows: # 读取场景子节点，覆盖已魅惑及正在同帧登记的运输舰。
		if not is_instance_valid(row):
			continue
		for child: Node in row.get_children(): # 只有活着且仍在战场上的运输舰占用航线。
			var active := child as Zombie040TransportAirship # 其他僵尸不妨碍空中停靠。
			if active != null and not active.is_death and not active.is_queued_for_deletion():
				occupied.append(active.occupied_airspace())
	var view_top: Vector2 = main_game.get_canvas_transform().affine_inverse() * main_game.get_viewport_rect().position # 与运输舰共用战场镜头。
	var candidates: Dictionary[PlantCell, Rect2] = {} # 保留计算过的安全通道，选中时立即交给实例。
	for cell: PlantCell in board.cells(): # 使用逻辑列计数，格子随平台移动时仍保持列身份。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
			continue
		var from_right: int = board.extent.y - cell.row_col.y # 最右列计为 1。
		if from_right < 2 or from_right > 5 or not is_lane_open(cell.combat_lane) \
				or not cell.get_spawn_global_position().is_finite():
			continue
		var approach: Rect2 = Zombie040TransportAirship.landing_corridor(cell, view_top.y, main_game.main_game_slope) # 包含机体尺寸和下降扫过的区域。
		if not occupied.any(func(area: Rect2) -> bool: return area.intersects(approach)):
			candidates[cell] = approach
	if candidates.is_empty():
		return null
	var chosen: PlantCell = candidates.keys().pick_random() # 只有路线安全的格子进入等权随机。
	transport.configure_landing(chosen, candidates[chosen])
	return chosen


## 从已有雪橇准备器缓存 [param sample] 的 [param tier_id] 外观，[param appearance] 必须已完整编译。
## 只接收Z1001雪橇队员，实际战斗已生成相同等阶时不覆盖原有缓存。
func cache_prepared_bobsled_appearance(sample: Zombie000Base, tier_id: StringName,
		appearance: AdventureZombieTierArt.PreparedAppearance) -> bool:
	if sample == null or sample.zombie_type != CharacterRegistry.ZombieType.Z1001BobsledSingle \
			or sample.scene_file_path.is_empty() or appearance == null:
		return false
	var key: String = "%s:%s" % [sample.scene_file_path, tier_id] # 与原始出生工厂缓存键完全一致。
	if _appearances.has(key):
		return false
	_appearances[key] = appearance
	if appearance.pending_atlas != null and is_instance_valid(periodic_updates):
		periodic_updates.queue_atlas(appearance.pending_atlas) # 图集仍由本场原调度器分帧构建。
		appearance.pending_atlas = null
	return true

## 为尚未入树的 [param zombie] 装配 [param tier_id] 外观。返回是否匹配等阶美术。
func apply_spawn_appearance(zombie: Zombie000Base, tier_id: StringName) -> bool:
	var specialize_land_rig: bool = AdventureZombieTierArt.can_specialize_land_rig(zombie) # 首次编译和后续复用需匹配形态。
	var key: String = "%s:%s" % [zombie.scene_file_path, tier_id] # 不同变种场景不能共享部件路径。
	var appearance: AdventureZombieTierArt.PreparedAppearance = _appearances.get(key) # 本场的只读素材绑定。
	if appearance == null:
		var pack_sprites: bool = is_instance_valid(periodic_updates) and periodic_updates.can_pack_sprites() # 受本场显存额度约束。
		appearance = AdventureZombieTierArt.prepare(zombie, tier_id, pack_sprites, specialize_land_rig)
		_appearances[key] = appearance
		if appearance.pending_atlas != null:
			periodic_updates.queue_atlas(appearance.pending_atlas)
			appearance.pending_atlas = null
	else:
		appearance.apply_to(zombie, specialize_land_rig)
	return appearance.has_tier_art

## 在生成调用方完成波次或遭遇登记后，让新出场的 [param enemy] 通过原有死亡入口离场。
## 回调时重新检查开关和战斗状态，避免关闭后或切场期间继续处决。
func _apply_cheat_instant_kill(enemy: Character000Base) -> void:
	if not cheat_instant_kill_enabled or not is_game_running() \
			or not is_instance_valid(enemy) or not enemy.is_inside_tree() \
			or enemy.is_death or enemy.is_queued_for_deletion():
		return
	if enemy is ZB000Base:
		enemy.force_defeat(&"spawn_instant_kill")
	elif enemy is SaviorFollower:
		enemy.retire_from_battle()
	else:
		enemy.character_death_disappear()

#endregion

#region 僵尸死亡 魅惑信号 波次刷新 多轮游戏
#region 魅惑 死亡
## [param zombie] 被魅惑时移出敌方及自然刷新计数，保留实例用于后续死亡清理。
func _on_zombie_hypno(zombie: Zombie000Base) -> void:
	if not all_zombies_1d.has(zombie) or all_zombies_be_hypno.has(zombie):
		return
	if not _transferred_enemy_slots.erase(zombie):
		curr_zombie_num -= 1
	all_zombies_2d[zombie.lane].erase(zombie)
	all_zombies_be_hypno.append(zombie)
	_remove_natural_refresh_zombie(zombie.get_instance_id())
	# 魅惑同时移除尚未破壳的本体预算，避免已经转为友军的生命阻塞残血刷新。
	zombie.signal_zombie_hp_loss.emit(zombie.hp_component.get_all_hp() + zombie.contained_zombie_wave_health(), zombie.curr_wave)
	# 魅惑之后不再把该实例的掉血记入原自然波次。
	var connections: Array = zombie.signal_zombie_hp_loss.get_connections()
	# 当前需要移除的掉血监听连接。
	for connection: Dictionary in connections:
		zombie.signal_zombie_hp_loss.disconnect(connection.callable)
	_try_finish_wave(zombie.global_position)


## [param zombie] 死亡时只结算一次；记入有效战斗的敌方击杀，再判断是否清场。
func _on_zombie_dead(zombie: Zombie000Base) -> void:
	if _unregister_zombie(zombie):
		# 强制死亡不会生成后续形态；当前血量已由受击组件结算，只移除额外预留值。
		var contained_health: int = zombie.contained_zombie_wave_health() # 默认物种为零，不改变已有掉血事件。
		if contained_health > 0:
			zombie.signal_zombie_hp_loss.emit(contained_health, zombie.curr_wave)
		if not zombie.retiring_from_battle and is_game_running() \
				and main_game.preview_return_scene.is_empty() and not game_para.is_zombie_mode:
			Global.record_zombie_defeat()
		_remove_natural_refresh_zombie(zombie.get_instance_id())
		_try_finish_wave(zombie.global_position)

## [param zombie] 已由新形态接替。从本波移除原体，转换不产生死亡档案、亡语或掉落。
func retire_converted_zombie(zombie: Zombie000Base) -> void:
	if not _unregister_zombie(zombie):
		return
	zombie.queue_free()
	_remove_natural_refresh_zombie(zombie.get_instance_id())
	# 已交接名单的石像会先断开旧监听；其他强制转换仍须释放封存形态预算。
	zombie.signal_zombie_hp_loss.emit(zombie.hp_component.get_all_hp() + zombie.contained_zombie_wave_health(), zombie.curr_wave)
	_try_finish_wave(zombie.global_position)


## [param zombie] 实际离树的普通僵尸；在节点仍有效时同步清理战场列表。
func _on_zombie_tree_exiting(zombie: Zombie000Base) -> void:
	if zombie.is_changing_lane or not _unregister_zombie(zombie):
		return
	# 未经死亡直接离场的石像一并释放壳与本体预算；已交接/死亡的旧体不会再次进入此分支。
	var contained_health: int = zombie.contained_zombie_wave_health() # 只为含后续形态的实例补齐原始离树路径。
	if contained_health > 0:
		zombie.signal_zombie_hp_loss.emit(zombie.hp_component.get_all_hp() + contained_health, zombie.curr_wave)
	# 波次事件可能生成僵尸，等到本次离树结束后再发出。
	_finish_zombie_departure.call_deferred(zombie.get_instance_id(), zombie.global_position, _round_generation)


## 注销 [param zombie] 的普通僵尸登记；返回是否实际移除了一个计入敌方数量的实例。
func _unregister_zombie(zombie: Zombie000Base) -> bool:
	if not all_zombies_1d.has(zombie):
		return false
	all_zombies_1d.erase(zombie)
	if all_zombies_be_hypno.has(zombie):
		all_zombies_be_hypno.erase(zombie)
		return false
	all_zombies_2d[zombie.lane].erase(zombie)
	if not _transferred_enemy_slots.erase(zombie):
		curr_zombie_num -= 1
	return true

## [param lane] 进入坠落后停止交互，保留活体外观直到真正出屏。
func close_falling_lane(lane: int) -> void:
	var row: ZombieRow = all_zombie_rows[lane] # 攻击行仍留在索引，供本拍结束时结算。
	row.is_falling = true
	row.process_mode = Node.PROCESS_MODE_DISABLED
	for zombie: Zombie000Base in all_zombies_1d: # 同一行的魅惑单位也停止交互。
		if is_instance_valid(zombie) and not zombie.is_death and zombie.lane == lane:
			zombie.hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	zombie_wave_manager.zombie_wave_create_manager.zombie_choose_row_system.init_zombie_choose_row_system(all_zombie_rows)

## 在 [param actor] 的沉降演出中移去最后一条出怪行，先结算死亡再收缩空间索引。
func retire_last_battle_row(actor: ZB000Base) -> void:
	var lane: int = all_zombie_rows.size() - 1 # 只移尾行，存活者无需换编号。
	if lane < 1:
		return
	for zombie: Zombie000Base in all_zombies_1d.duplicate(): # 同时清理本行已魅惑的单位。
		if is_instance_valid(zombie) and zombie.lane == lane:
			zombie.retire_from_battle()
			if all_zombies_1d.has(zombie):
				_on_zombie_dead(zombie)
	for boss: ZB000Base in get_living_bosses(): # 发动沉降的凯莱赫由本次演出重新定位。
		if boss != actor and boss.lane == lane:
			boss.force_defeat(&"terrain_collapse")
	for road: IceRoad in all_ice_roads[lane].duplicate(): # 已不存在的行不再参与雪橇或阻种。
		if is_instance_valid(road):
			road.queue_free()
	var row: ZombieRow = all_zombie_rows.pop_back() # 剩余行仍使用原节点。
	all_zombies_2d.pop_back()
	all_ice_roads.pop_back()
	row.hide()
	row.queue_free()
	zombie_wave_manager.zombie_wave_create_manager.zombie_choose_row_system.init_zombie_choose_row_system(all_zombie_rows)


## [param instance_id] 已离树的敌方实例 ID；[param global_pos] 离树时的位置；[param generation] 离树时的轮次代数。
func _finish_zombie_departure(instance_id: int, global_pos: Vector2, generation: int) -> void:
	_remove_natural_refresh_zombie(instance_id)
	if generation == _round_generation:
		_try_finish_wave(global_pos)


## 将 [param zombie] 登记到自然刷新集合；所有原有生成默认参与，博士来源在入树前明确关闭。
func _register_natural_refresh_zombie(zombie: Zombie000Base) -> void:
	if not zombie.participates_natural_refresh or zombie.is_death or zombie.is_hypno or zombie.is_queued_for_deletion():
		return
	# 集合以实例 ID 去重，死亡、魅惑和离树可重复请求移除而不重复扣数。
	var instance_id: int = zombie.get_instance_id()
	if _natural_refresh_zombie_ids.has(instance_id):
		return
	_natural_refresh_zombie_ids[instance_id] = true
	if zombie.curr_wave >= 0:
		var wave_number: int = zombie.curr_wave + 1
		_natural_wave_by_id[instance_id] = wave_number
		_natural_wave_counts[wave_number] = _natural_wave_counts.get(wave_number, 0) + 1
		signal_natural_wave_count_change.emit(wave_number, _natural_wave_counts[wave_number])
	signal_natural_refresh_zombie_num_change.emit(natural_refresh_zombie_count)


## 移除 [param instance_id] 的刷新登记；场景卸载期间只清理记录，不触发新的自然波次。
func _remove_natural_refresh_zombie(instance_id: int) -> void:
	if not _natural_refresh_zombie_ids.erase(instance_id):
		return
	var wave_number: int = _natural_wave_by_id.get(instance_id, 0)
	_natural_wave_by_id.erase(instance_id)
	if wave_number > 0:
		var remaining: int = maxi(0, _natural_wave_counts.get(wave_number, 0) - 1)
		_natural_wave_counts[wave_number] = remaining
		if is_game_running():
			signal_natural_wave_count_change.emit(wave_number, remaining)
	if is_game_running():
		signal_natural_refresh_zombie_num_change.emit(natural_refresh_zombie_count)


## 普通死亡、魅惑及僵王死亡共用原有清场条件，不受额外 Boss 胜利选项影响。
## [param global_pos] 最后一个敌人的世界坐标，用于原清场胜利的奖杯位置。
func _try_finish_wave(global_pos: Vector2) -> void:
	if not is_game_running() or has_pending_boss_defeat_presentation():
		return
	if is_end_wave and curr_zombie_num == 0:
		if AdventureSession.owns_battle(game_para):
			BossTrace.victory(self, AdventureSession.victory_blocker(), &"last_enemy_cleared")
		if is_instance_valid(multi_round_end_wave_timer):
			multi_round_end_wave_timer.stop()
		EventBus.push_event("create_trophy", [global_pos])
#endregion

#region 波次刷新
func wave_refresh(curr_is_end_wave:bool):
	# 回调发生在本波普通僵尸生成后。先计入僵王，再清理场外僵尸，避免末波短暂归零。
	if monster_mode == ConstLevelData.E_MonsterMode.Norm and game_para.has_boss() \
		and game_para.boss_spawn_wave > 0 and not _auto_boss_spawned \
		and zombie_wave_manager.curr_wave + 1 == game_para.boss_spawn_wave:
		if create_boss() == null:
			return
	is_end_wave = curr_is_end_wave
	set_zombie_death_over_view()
	if is_end_wave:
		check_zombie_end_wave_timer.start()
		print("最后一波僵尸检测是否有离开当前视野的僵尸")
		## 多轮游戏计时器启动
		multi_round_end_wave_timer_start()

### 删除移动超出视野的僵尸,每次刷新僵尸调用
func set_zombie_death_over_view():
	for z:Zombie000Base in all_zombies_1d.duplicate(): # 处决会同步注销僵尸，遍历快照以免跳过后续实例。
		if not is_instance_valid(z) or z.is_death:
			continue
		var x: float = z.global_position.x # 波次清理与末波定时检查共用同一个世界边界。
		if x > zombie_range_pos_x.y:
			if z.is_right_entry_pending():
				continue
			# 击退结束后只保留会向战场走回的目标，避免反向移动的矿工卡住清场。
			if z.nonlethal_displacement_exile and (z.direction_x_root > 0 \
					or (is_instance_valid(z.move_component) and z.move_component.is_forced_moving())):
				continue
		z.nonlethal_displacement_exile = false
		if x > zombie_range_pos_x.y or x < zombie_range_pos_x.x:
			z.retire_from_battle()
#endregion

#region 多轮游戏
#region 触发
## 战斗末波后按原规则启动 49 秒轮间计时，不受额外 Boss 胜利选项影响。
func multi_round_end_wave_timer_start():
	if not is_game_running():
		return
	if not is_instance_valid(multi_round_end_wave_timer):
		multi_round_end_wave_timer = Timer.new()
		multi_round_end_wave_timer.wait_time = multi_round_end_wave_time
		multi_round_end_wave_timer.one_shot = true
		multi_round_end_wave_timer.autostart = false
		multi_round_end_wave_timer.timeout.connect(_on_trigger_start_next_round_game)
		add_child(multi_round_end_wave_timer)
	multi_round_end_wave_timer.start()
	print("多轮游戏波次后一波计时器启动")

## 战斗中触发原有轮间计时请求；末轮与重复请求由主游戏管理器拒绝。
func _on_trigger_start_next_round_game():
	multi_round_end_wave_timer.stop()
	if has_pending_boss_defeat_presentation():
		_next_round_waiting_for_boss_presentation = true
		return
	_next_round_waiting_for_boss_presentation = false
	if is_game_running():
		EventBus.push_event("start_next_round_game")
#endregion

#region 开始下一轮游戏
## 更新下一轮僵尸管理器；[param finish_current_round] 为实际 Boss 胜利时跳过剩余自然波次。
func start_next_game_zombie_mananger_update(finish_current_round: bool = false):
	is_end_wave = false
	_start_requested = false
	_round_generation += 1
	_boss_trophy_pending_id = 0
	_boss_trophy_pending_position = Vector2.INF
	_pending_boss_defeat_presentations.clear()
	_deferred_round_trophy_position = Vector2.INF
	_next_round_waiting_for_boss_presentation = false
	_boss_trophy_created = false
	match monster_mode:
		ConstLevelData.E_MonsterMode.Norm:
			check_zombie_end_wave_timer.stop()
			## 更新当前轮次的出怪列表
			update_multi_round_zombie_refresh_types(main_game.curr_game_round, main_game.game_para.game_sences)
			# 按本轮实际结束原因推进波次，配置开启本身不改变原有轮间规则。
			zombie_wave_manager.start_next_game_zombie_wave_mananger_update(finish_current_round)
		ConstLevelData.E_MonsterMode.HammerZombie:
			hammer_zombie_manager.start_next_game_hammer_manager_update(game_para)

	## 我是僵尸模式删除所有的僵尸
	if game_para.is_zombie_mode:
		_clear_bosses_for_next_round()
		# 我是僵尸轮间原有清场顺序，僵王已由独立根节点清理。
		for i in range(all_zombies_1d.size()-1,-1,-1):
			# 当前轮次尚未移除的普通僵尸。
			var zombie:Zombie000Base = all_zombies_1d[i]
			zombie.retire_from_battle()
	_refresh_boss_progress()

#endregion


#region 多轮(无尽)出怪
## 多轮出怪获取出怪列表
func update_multi_round_zombie_refresh_types(curr_round:int, game_sences:MainSceneRegistry.MainScenes) -> void:
	## 清空数据
	is_bungi = false
	zombie_refresh_types.clear()
	# 第一次选卡 (curr_round == 1) 的 “固定三种”：普僵 + 路障 + 铁桶
	if curr_round == 1:
		zombie_refresh_types.append(CharacterRegistry.ZombieType.Z001Norm)
		zombie_refresh_types.append(CharacterRegistry.ZombieType.Z003Cone)
		zombie_refresh_types.append(CharacterRegistry.ZombieType.Z005Bucket)
	else:
		var whitelist_refresh_zombie_types_copy = Global.global_read_data.whitelist_refresh_zombie_types_with_zombie_row_type[ResourceLevelData.resolve_terrain_type(game_sences, game_para.terrain_rows, game_para.board_definition)].duplicate(true)
		zombie_refresh_types.append(CharacterRegistry.ZombieType.Z001Norm)
		whitelist_refresh_zombie_types_copy.erase(CharacterRegistry.ZombieType.Z001Norm)
		# 第二种：80% 路障 (Cone)，20% 报纸 (Paper)
		var prob = randf()
		if prob < 0.8:
			zombie_refresh_types.append(CharacterRegistry.ZombieType.Z003Cone)
			whitelist_refresh_zombie_types_copy.erase(CharacterRegistry.ZombieType.Z003Cone)
		else:
			zombie_refresh_types.append(CharacterRegistry.ZombieType.Z006Paper)
			whitelist_refresh_zombie_types_copy.erase(CharacterRegistry.ZombieType.Z006Paper)
		## 第二轮之后可能刷新僵尸(min(轮次*2,8)+2)个
		for i in range(min(curr_round * 2, 8)):
			var zombie_type_choose = whitelist_refresh_zombie_types_copy.pick_random()
			zombie_refresh_types.append(zombie_type_choose)
			whitelist_refresh_zombie_types_copy.erase(zombie_type_choose)

			if zombie_type_choose == CharacterRegistry.ZombieType.Z021Bungi:
				print("warning: 出怪刷新列表禁止使用 Z021Bungi ,已修改为选择 is_bungi 参数")
				is_bungi = true
				zombie_refresh_types.erase(zombie_type_choose)

			if whitelist_refresh_zombie_types_copy.is_empty():
				break

	print("当前轮次", curr_round,"可能刷新的僵尸类型有:")
	for zombie_type in zombie_refresh_types:
		print(Global.character_registry.get_zombie_info(zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieName))
	if is_bungi:
		print(Global.character_registry.get_zombie_info(CharacterRegistry.ZombieType.Z021Bungi, CharacterRegistry.ZombieInfoAttribute.ZombieName))


#endregion


#endregion
#endregion

#region 生成关卡前展示僵尸
## 等待展示实体按主线程预算构造完成，调用方随后才启动选卡镜头。
func create_prepare_show_zombies() -> void:
	await zombie_show_in_start.create_prepare_show_zombies()

func delete_prepare_show_zombies():
	zombie_show_in_start.delete_prepare_show_zombies()
#endregion

#region 植物调用相关，寒冰菇\火爆辣椒\三叶草
## 寒冰菇处理普通僵尸及所有存活僵王；各僵王自行检查受击窗口。[br]
## [param time_ice] 完全冻结时长，单位为游戏秒。[br]
## [param time_decelerate] 解冻后的减速时长，单位为游戏秒。
func ice_all_zombie(time_ice:float, time_decelerate: float):
	resolve_ice_blast(time_ice, time_decelerate)

## 结算 [param time_ice] 秒冻结与 [param time_decelerate] 秒后续减速的全场副效果。
## [param freeze_zombie] 仅替换普通僵尸的逐目标结算，设施、珊瑚和僵王共用原生入口。
func resolve_ice_blast(time_ice: float, time_decelerate: float, freeze_zombie: Callable = Callable()) -> void:
	for structure: Node in get_tree().get_nodes_in_group(EnemyStructureBase.GROUP): # 当前战场内的敌方设施。
		if main_game.is_ancestor_of(structure):
			structure.be_attacked_bullet(20, BulletRegistry.AttackMode.Real, false, false)
	# 保留寒冰菇对珊瑚出怪的抑制计时。
	is_ice = true
	var coral_duration: float = time_ice # 转职版本不能缩短已有的珊瑚抑制。
	if freeze_zombie.is_valid() and is_instance_valid(ice_timer):
		coral_duration = maxf(coral_duration, ice_timer.time_left)
	start_ice_timer(coral_duration)
	# 当前行的普通僵尸列表；僵王由独立集合登记。
	for zombie_row:Array in all_zombies_2d:
		if zombie_row.is_empty():
			continue
		# 当前接受冻结效果的普通僵尸。
		for zombie:Zombie000Base in zombie_row.duplicate():
			if freeze_zombie.is_valid():
				freeze_zombie.call(zombie)
			elif is_instance_valid(zombie):
				zombie.be_ice_freeze(time_ice, time_decelerate)
	# 独立登记的僵王各结算一次寒冰菇伤害，由共同受击入口免疫冰冻。
	for boss: ZB000Base in get_living_bosses():
		if is_instance_valid(boss):
			boss.be_ice_freeze(time_ice, time_decelerate)

func start_ice_timer(wait_time:float):
	if not is_instance_valid(ice_timer):
		ice_timer = Timer.new()
		ice_timer.one_shot = true
		ice_timer.timeout.connect(_on_ice_timer_timeout)
		add_child(ice_timer)
	ice_timer.start(wait_time)

func _on_ice_timer_timeout():
	if is_ice == false:
		push_error("冰消珊瑚计时器有误，is_ice应该为true")
	is_ice = false




func jalapeno_bomb_item_lane(lane:int):
	## 冰道
	for i in range(all_ice_roads[lane].size()-1, -1, -1):
		var ice_road:IceRoad = all_ice_roads[lane][i]
		ice_road.ice_road_disappear()

## 火爆辣椒处理整行普通僵尸，并攻击所有存活僵王；僵王检查受击窗口，不限制行号。[br]
## [param lane] 辣椒所在的零起始行号，仅用于选择受影响的普通僵尸。
## [param damage] 由爆炸组件计算的实际伤害；本管理器不解释植物星级。
## [param boss_damage_cap] 传入僵王受击入口，负一表示无需封顶。
func jalapeno_bomb_lane_zombie(lane: int, damage: int, boss_damage_cap: int = -1) -> void:
	for structure: Node in get_tree().get_nodes_in_group(EnemyStructureBase.GROUP): # 同行设施不纳入僵尸计数。
		if main_game.is_ancestor_of(structure) and structure.lane == lane:
			structure.cancel_ice()
			if is_instance_valid(structure):
				structure.be_attacked_bullet(damage, BulletRegistry.AttackMode.Penetration, false, false)
	# 倒序遍历当前行，普通僵尸被炸死时可能立即从列表移除。
	for i in range(all_zombies_2d[lane].size()-1,-1,-1) :
		if is_instance_valid(all_zombies_2d[lane][i]):
			# 当前接受爆炸伤害的普通僵尸，继续沿用其原有灰烬与删除规则。
			var zombie:Zombie000Base = all_zombies_2d[lane][i]
			zombie.be_bomb(damage, true)
	# 任意行的辣椒都可命中僵王，使用专用入口检查受击窗口并保留完整死亡演出。
	# 使用快照，某只僵王死亡不会影响其余实例遍历。
	for boss: ZB000Base in get_living_bosses():
		if is_instance_valid(boss):
			boss.be_jalapeno(damage, boss_damage_cap)

## 三叶草吹走空中僵尸
func blover_blow_away_in_sky_zombie():
	AdventureZombieWindGust.blow_all(self)

#endregion

## 无出怪模式或最后一波时，每秒清理离开当前视野的普通僵尸。
func _on_check_zombie_end_wave_timer_timeout() -> void:
	set_zombie_death_over_view()

## 僵尸换行,更新数据
func zombie_update_lane(zombie:Zombie000Base, ori_lane:int):
	if all_zombies_2d[ori_lane].has(zombie):
		all_zombies_2d[ori_lane].erase(zombie)
		all_zombies_2d[zombie.lane].append(zombie)
		zombie.signal_lane_update.disconnect(zombie_update_lane.bind(zombie, ori_lane))
		zombie.signal_lane_update.connect(zombie_update_lane.bind(zombie, zombie.lane))
		#print("僵尸换行")


#region 控制台 所有僵尸死亡
## 所有僵尸死亡
func death_all_zombie():
	for zombie_row:Array in all_zombies_2d:
		if zombie_row.is_empty():
			continue
		for i in range(zombie_row.size()-1, -1, -1):
			var zombie:Zombie000Base = zombie_row[i]
			if zombie is SaviorFollower:
				zombie.retire_from_battle()
			else:
				zombie.character_death_disappear()
#endregion


## 普通僵尸卡的唯一放置资格；预览和提交都调用，不改变出怪计数。[br]
## [param zombie_type] 为注册物种；[param cell] 必须是本战场仍有效的地块。
func can_place_zombie_at_cell(zombie_type: CharacterRegistry.ZombieType, cell: PlantCell) -> bool:
	if available_zombie_slots(1) == 0 or not is_instance_valid(cell) \
			or cell.is_queued_for_deletion() or not cell.is_inside_tree() \
			or not is_instance_valid(main_game) or cell.board != main_game.board \
			or not main_game.is_ancestor_of(cell) or not cell.board.allows_mutation():
		return false
	if not cell.can_common_zombie and zombie_type != CharacterRegistry.ZombieType.Z021Bungi:
		return false
	if not can_spawn_zombie_in_lane(zombie_type, cell.combat_lane):
		return false
	var terrain: CharacterRegistry.ZombieRowType = Global.character_registry.get_zombie_info(
		zombie_type, CharacterRegistry.ZombieInfoAttribute.ZombieRowType) # 同一注册水陆要求。
	return ZombieRow.supports_spawn(terrain, cell.get_spawn_terrain_type())
