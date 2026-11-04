extends Node
## 僵尸波次管理器
class_name ZombieWaveManager

#region 波次管理器参数
## 是否有墓碑,即墓碑是否生成僵尸
var is_have_tombston := false
## 一轮游戏最大波次
var max_wave_one_round :int
#endregion

## 波次刷新管理器
@onready var zombie_wave_refresh_manager: ZombieWaveRefreshManager = $ZombieWaveRefreshManager
## 波次创建管理器
@onready var zombie_wave_create_manager: ZombieWaveCreateManager = $ZombieWaveCreateManager
## 所属关卡的僵尸管理器；延迟流程只查询本关卡的战斗阶段。
@onready var zombie_manager: ZombieManager = %ZombieManager
## 每秒进度条更新计时器
@onready var every_wave_progress_timer: Timer = $EveryWaveProgressTimer

## 关卡进度条
@onready var flag_progress_bar: FlagProgressBar = %FlagProgressBar
## 大波时文字提醒
@onready var ui_remind_word: UIRemindWord = %UIRemindWord

## 大波僵尸时墓碑生产的僵尸类型
@export var zombie_type_candidate_tombstone :Array[CharacterRegistry.ZombieType] = [CharacterRegistry.ZombieType.Z001Norm]

## 当前波次类型
enum E_WaveType{
	Norm,		## 普通波
	FlagFront,	## 旗前波
	Flag,		## 旗帜波
	Final,		## 最后一波
}
## 当前波次分类，决定提前刷新条件及大波额外生成内容。
var curr_wave_type:E_WaveType
## 最大波次(多轮游戏时更新最大波次)
var max_wave :int
## 当前波次
var curr_wave := -1
## 每波进度条所占大小
var progress_bar_segment_every_wave:float
## 每段根据当前波次时间，每秒多长
var progress_bar_segment_mini_every_sec:float
## 每次停止或切轮递增；等待中的旧波流程不能在下一轮重新进入战斗后恢复。
var _refresh_generation: int = 0
var is_advancement_suspended := false
var _pending_advancement := false
var _before_wave_signalled: int = -1
signal adventure_battle_started
signal adventure_wave_before(wave_number: int)
signal adventure_wave_started(wave_number: int)

## 暂停自然波次的计时、进度和下一波调度；不会影响游戏世界及 Boss 援军。
func suspend_advancement() -> void:
	if is_advancement_suspended:
		return
	is_advancement_suspended = true
	every_wave_progress_timer.paused = true
	zombie_wave_refresh_manager.suspend_refresh()

func resume_advancement() -> void:
	if not is_advancement_suspended:
		return
	is_advancement_suspended = false
	every_wave_progress_timer.paused = false
	zombie_wave_refresh_manager.resume_refresh()
	if _pending_advancement:
		_pending_advancement = false
		start_next_wave.call_deferred()

## 波次刷新信号,给zombie_manager,删除魅惑僵尸，更新是否为最后一波
signal signal_wave_refresh(is_end_wave:bool)


func _ready() -> void:
	## 刷新波次信号
	zombie_wave_refresh_manager.signal_refresh.connect(start_next_wave)
	## 新波次自然刷新时间
	zombie_wave_refresh_manager.signal_norm_time.connect(update_progress_bar_segment_mini_every_sec)

## 初始化波次管理器
func init_zombie_wave_manager(game_para:ResourceLevelData):
	is_advancement_suspended = false
	_pending_advancement = false
	_before_wave_signalled = -1
	every_wave_progress_timer.paused = false
	is_have_tombston = game_para.is_have_tombston
	max_wave_one_round = game_para.max_wave
	## 如果存在存档
	if game_para.save_game_data_main_game:
		curr_wave = game_para.save_game_data_main_game.curr_wave
		max_wave = game_para.save_game_data_main_game.curr_max_wave
	else:
		curr_wave = -1
		max_wave = game_para.max_wave

	flag_progress_bar.init_flag_from_wave(max_wave_one_round)
	progress_bar_segment_every_wave = 100.0 / (max_wave_one_round - 1)

	zombie_wave_create_manager.init_zombie_wave_create_manager(game_para)
	# 冒险事件由 MainGameManager 持有；波次管理器只负责发出波次事件。

## 切换下一轮波次并取消旧轮等待；[param finish_current_round] 表示本轮实际由 Boss 条件结束。
## 仅实际 Boss 提前胜利时跳过未生成波次，先推进到原末波，再扩大下一轮的波次上界。
func start_next_game_zombie_wave_mananger_update(finish_current_round: bool = false):
	stop_wave_refresh()
	if finish_current_round:
		curr_wave = max_wave - 1
	max_wave += max_wave_one_round
	flag_progress_bar.start_next_game_flag_progress_bar_update()
	flag_progress_bar.visible = false
	zombie_wave_create_manager.update_zombie_refresh_types()

## 计算当前进度并更新进度条
func set_progress_bar(curr_flag:int=-1):
	var curr_progress = curr_wave % max_wave_one_round * progress_bar_segment_every_wave
	flag_progress_bar.set_progress(curr_progress, curr_flag)

## 战斗阶段开始第一波并启动进度计时；关卡已结束时不启动。
func start_first_wave():
	if zombie_wave_create_manager.adventure_wave_profile != null:
		adventure_battle_started.emit()
	# 第一波生成期间若停止或切轮，不再重启旧轮进度计时器。
	var refresh_generation: int = _refresh_generation
	start_next_wave()
	if not _is_wave_refresh_current(refresh_generation):
		return
	every_wave_progress_timer.start()
	every_wave_progress_timer.paused = is_advancement_suspended
	flag_progress_bar.visible = true

## 停止自然波次与进度计时并失效旧轮等待；下一轮进入战斗也不会恢复旧波流程。
func stop_wave_refresh() -> void:
	_refresh_generation += 1
	is_advancement_suspended = false
	_pending_advancement = false
	every_wave_progress_timer.paused = false
	every_wave_progress_timer.stop()
	zombie_wave_refresh_manager.stop_refresh()

## 返回 [param refresh_generation] 是否仍属于当前刷新流程，且所属关卡仍处于正式战斗。
func _is_wave_refresh_current(refresh_generation: int) -> bool:
	return refresh_generation == _refresh_generation and zombie_manager.is_game_running()

## 战斗阶段生成下一波并发出刷新信号；大波提示等待后检查战斗阶段及停止版本。
## 一次自然波次：先判断并展示，再确认未暂停，最后才更新波次编号与实例。
## await 期间出现 Boss 时保留待启动波次，不会偷跑生成。
func start_next_wave() -> void:
	if is_advancement_suspended:
		_pending_advancement = true
		return
	var profile: WaveProfile = zombie_wave_create_manager.adventure_wave_profile
	var next_wave_index: int = curr_wave + 1
	if profile != null:
		var next_wave_number: int = next_wave_index + 1
		if next_wave_number != _before_wave_signalled:
			_before_wave_signalled = next_wave_number
			adventure_wave_before.emit(next_wave_number)
			if is_advancement_suspended:
				_pending_advancement = true
				return
	var refresh_generation: int = _refresh_generation
	if not _is_wave_refresh_current(refresh_generation):
		return
	var wave_number: int = next_wave_index + 1
	var is_final: bool = next_wave_index == max_wave - 1
	var is_flag: bool = profile.is_flag_wave(wave_number) if profile != null else next_wave_index % 10 == 9
	var is_flag_front: bool = (profile.is_flag_wave(wave_number + 1) or wave_number + 1 == max_wave) \
		if profile != null else next_wave_index % 10 == 8
	var next_type: E_WaveType = E_WaveType.Norm
	if is_final and (profile != null or is_flag):
		next_type = E_WaveType.Final
	elif is_flag:
		next_type = E_WaveType.Flag
	elif is_flag_front:
		next_type = E_WaveType.FlagFront
	if next_type in [E_WaveType.Final, E_WaveType.Flag]:
		await ui_remind_word.zombie_approach(next_type == E_WaveType.Final)
		if not _is_wave_refresh_current(refresh_generation):
			return
		if is_advancement_suspended:
			_pending_advancement = true
			return
	curr_wave = next_wave_index
	curr_wave_type = next_type
	var is_big_wave: bool = next_type in [E_WaveType.Final, E_WaveType.Flag]
	var spawned: Array[Zombie000Base] = zombie_wave_create_manager.create_curr_wave_all_zombies(curr_wave, is_big_wave)
	set_progress_bar()
	if profile == null and is_big_wave:
		zombie_wave_create_manager.spawn_special_zombie_in_big_wave(is_final)
		if is_have_tombston:
			call_tombstone_create_zombie()
	if not _is_wave_refresh_current(refresh_generation):
		return
	var wave_all_hp := 0
	for zombie: Zombie000Base in spawned:
		zombie.signal_zombie_hp_loss.connect(zombie_wave_refresh_manager.judge_half_refresh)
		wave_all_hp += zombie.hp_component.get_all_hp()
	zombie_wave_refresh_manager.update_wave_health_data(wave_all_hp, curr_wave_type, curr_wave)
	signal_wave_refresh.emit(is_final)
	if profile != null:
		adventure_wave_started.emit(wave_number)

## 请求生成墓碑后等待 1 个游戏秒，再从本关卡墓碑生成僵尸；停止、切轮或结束战斗时取消。
func call_tombstone_create_zombie():
	# 墓碑等待也必须属于同一刷新版本，不能跨轮恢复生成。
	var refresh_generation: int = _refresh_generation
	if not _is_wave_refresh_current(refresh_generation):
		return
	EventBus.push_event("create_tombstone", [randi()%3+1])
	await get_tree().create_timer(1.0, false).timeout
	if not _is_wave_refresh_current(refresh_generation):
		return
	# 从所属关卡读取墓碑列表，避免旧协程恢复时访问新关卡的全局引用。
	var plant_cell_manager: PlantCellManager = zombie_manager.main_game.plant_cell_manager
	# 当前需要出怪的墓碑索引，维持原列表顺序。
	for i in range(plant_cell_manager.tombstone_list.size()):
		if not _is_wave_refresh_current(refresh_generation):
			return
		# 当前墓碑从候选池随机选择的僵尸类型。
		var new_zombie_type = zombie_type_candidate_tombstone.pick_random()
		plant_cell_manager.tombstone_list[i].create_new_zombie(new_zombie_type)

## 更新每秒旗帜进度(僵尸波次更新管理器信号触发)
func update_progress_bar_segment_mini_every_sec(time:float):
	## 如果是旗帜波，时间加6（僵尸靠近）+3（最后一波置为0）秒红字时间
	if curr_wave == max_wave - 1:
		progress_bar_segment_mini_every_sec = 0.0
		return
	var profile: WaveProfile = zombie_wave_create_manager.adventure_wave_profile
	var is_flag: bool = (profile.is_flag_wave(curr_wave + 1) if profile != null else curr_wave % 10 == 9)
	if is_flag:
		time += 6
	progress_bar_segment_mini_every_sec = progress_bar_segment_every_wave / maxf(time, 0.001)

## 战斗阶段随时间每秒更新进度条；停止前已排队的计时回调不再推进。
func _on_every_wave_progress_timer_timeout() -> void:
	if is_advancement_suspended or not zombie_manager.is_game_running():
		return
	# 每秒进度条增加对应的进度值
	flag_progress_bar.set_progress_add_every_sec(progress_bar_segment_mini_every_sec)
