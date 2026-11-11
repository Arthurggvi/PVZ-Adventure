extends Node
## 僵尸波次刷新管理器
class_name ZombieWaveRefreshManager
"""
刷新类型分为四种：
	## 不刷新（最后一波）
	正常刷新(刷新时间到后的刷新)
	提前刷新(条件触发)：
		## 残半刷新(普通波或旗帜波)
		## 全死亡刷新(旗前波)
	触发提前刷新时需要当前波次已经开始 time_min_wave(6.0) 秒
"""

## 所属关卡的僵尸管理器，提供自然刷新数量和本关卡战斗阶段。
@onready var zombie_manager: ZombieManager = %ZombieManager

## 正常刷新计时器
@onready var wave_norm_refresh_timer: Timer = $WaveNormRefreshTimer
## 波次最小时间计时器
@onready var wave_min_time_timer: Timer = $WaveMinTimeTimer
## 提醒文字（大波靠近等等）
@onready var ui_remind_word: UIRemindWord = %UIRemindWord

## 提前刷新类型
enum E_RefreshType{
	Null,			## 不刷新（最后一波）
	HalfRefresh,	## 残半刷新(普通波或旗帜波)
	TotalRefresh,	## 全死亡刷新(旗前波)
}
## 刷新状态
enum E_RefreshStatus{
	DisableRefresh,	## 不能刷新
	AwaitRefresh,	## 等待触发刷新
	CompleteRefresh,## 完成刷新
}

## 残半刷新的血量流失比例范围
@export var refresh_threshold_range := Vector2(0.5, 0.67)
## 残半刷新的下一波正常刷新的时间范围
@export var norm_refresh_time_range_in_half_refresh :=  Vector2(25.0, 31.0)
## 全部死亡刷新的下一波正常刷新的时间范围
@export var norm_refresh_time_range_in_total_refresh :=  Vector2(40, 46)
## 波次最小时间
@export var time_min_wave := 6.0

## 初代普通冒险每波的倒计时范围，单位为百分之一游戏秒。
const CLASSIC_REFRESH_TICKS: Vector2i = Vector2i(2500, 3099)
## 开波后经过此游戏秒数，才可按血量缩短倒计时。
const CLASSIC_EARLY_CHECK_SECONDS: float = 4.0
## 提前刷新的剩余倒计时，单位为游戏秒。
const CLASSIC_EARLY_COUNTDOWN_SECONDS: float = 2.0
## 允许提前刷新时，本波敌方剩余血量的比例范围。
const CLASSIC_HEALTH_THRESHOLD_RANGE: Vector2 = Vector2(0.5, 0.65)
## 初代刷新判定只计入五分之一的手持盾牌血量。
const CLASSIC_SHIELD_HEALTH_WEIGHT: float = 0.2

## 本波是否使用初代节奏；每次生成新波时随当前阶段重新读取。
var _classic_spawn_timing: bool = false

## 当前刷新状态
var curr_refresh_status:=E_RefreshStatus.DisableRefresh
## 停止或切波时递增，最短波间隔的旧等待不能消费新波次的刷新机会。
var _refresh_generation: int = 0
## 本轮刷新请求只能投递一次；挂起时保留 CompleteRefresh 状态，恢复后投递。
var _delivered_generation: int = -1
## Boss 遭遇期间只挂起自然刷新，保留剩余时间与当前提前刷新条件。
var _is_suspended: bool = false

func suspend_refresh() -> void:
	if _is_suspended:
		return
	_is_suspended = true
	wave_norm_refresh_timer.paused = true
	wave_min_time_timer.paused = true

func resume_refresh() -> void:
	if not _is_suspended:
		return
	_is_suspended = false
	wave_norm_refresh_timer.paused = false
	wave_min_time_timer.paused = false
	# 已接受的刷新请求属于当前自然波次，不因 Boss 暂停而丢失。
	if curr_refresh_status == E_RefreshStatus.CompleteRefresh \
			and _delivered_generation != _refresh_generation:
		_deliver_refresh.call_deferred(_refresh_generation)
## 当前可以的刷新类型,不可以选Norm正常刷新
var curr_can_refresh_type = E_RefreshType.Null
## 波次总血量
var wave_total_health := 0
## 当前总血量
var wave_current_health := 0
## 波次触发激活刷新的血量流失
var refresh_health :int
## 当前波次类型，决定下次刷新类型
var curr_wave_type := ZombieWaveManager.E_WaveType.Norm
## 当前波次,判断残半刷新时僵尸所属波次
var curr_wave := -1

## 刷新下一波信号（当前波结束时调用）
@warning_ignore("unused_signal")
signal signal_refresh(generation: int)
## 当前波自然刷新时间（更新完当前波后触发,给波次管理器当前波自然刷新时间）
signal signal_norm_time(time:float)
## 开始等待刷新，当前波次时间已达最小值，可以触发下次提前刷新
signal signal_start_await_refresh

func _ready() -> void:
	wave_min_time_timer.wait_time = time_min_wave
	set_process(false)


## 停止自然刷新和最短波间隔计时，并关闭提前刷新；已排队的回调仍检查战斗阶段。
func stop_refresh() -> void:
	set_process(false)
	_is_suspended = false
	wave_norm_refresh_timer.paused = false
	wave_min_time_timer.paused = false
	_refresh_generation += 1
	wave_norm_refresh_timer.stop()
	wave_min_time_timer.stop()
	curr_can_refresh_type = E_RefreshType.Null
	curr_refresh_status = E_RefreshStatus.DisableRefresh


## 每次刷新僵尸后获取当前波次生成僵尸血量值
func update_wave_health_data(curr_wave_total_health:int, new_curr_wave_type:ZombieWaveManager.E_WaveType, new_curr_wave:int):
	set_process(false)
	_refresh_generation += 1
	self.curr_wave_type = new_curr_wave_type
	self.curr_wave = new_curr_wave
	curr_refresh_status = E_RefreshStatus.DisableRefresh
	_classic_spawn_timing = zombie_manager.zombie_wave_manager.uses_classic_spawn_timing()

	if _classic_spawn_timing and curr_wave_type != ZombieWaveManager.E_WaveType.Final:
		# 初代普通冒险在旗前波也按本波剩余血量判断提前刷新。
		curr_can_refresh_type = E_RefreshType.HalfRefresh
		wave_total_health = _classic_wave_health()
		var threshold: float = randf_range(CLASSIC_HEALTH_THRESHOLD_RANGE.x, CLASSIC_HEALTH_THRESHOLD_RANGE.y) # 本波的剩余血量门槛。
		refresh_health = int(threshold * wave_total_health)
		_update_timer()
		return

	match self.curr_wave_type:
		## 普通波或旗帜波会触发残半刷新，更新当前残半刷新数据
		ZombieWaveManager.E_WaveType.Norm, ZombieWaveManager.E_WaveType.Flag:
			curr_can_refresh_type = E_RefreshType.HalfRefresh
			self.wave_total_health = curr_wave_total_health
			self.wave_current_health = self.wave_total_health
			## 残半刷新血量倍率
			var refresh_threshold = randf_range(refresh_threshold_range.x, refresh_threshold_range.y)
			refresh_health = int(refresh_threshold * self.wave_total_health)
			## 旗前波 僵尸全部死亡触发提前刷新
		ZombieWaveManager.E_WaveType.FlagFront:
			curr_can_refresh_type = E_RefreshType.TotalRefresh
			print("旗前波")
		## 最后一波，不刷新
		ZombieWaveManager.E_WaveType.Final:
			curr_can_refresh_type = E_RefreshType.Null
			print("最后一波")
	_update_timer()

## 更新计时器
func _update_timer():
	if curr_can_refresh_type == E_RefreshType.Null:
		wave_min_time_timer.stop()
		wave_norm_refresh_timer.stop()
		return
	var wave_norm_refresh_time: float # 当前波等到自动刷新所需的游戏秒数。
	if _classic_spawn_timing:
		wave_norm_refresh_time = float(randi_range(CLASSIC_REFRESH_TICKS.x, CLASSIC_REFRESH_TICKS.y)) / 100.0
	elif curr_can_refresh_type == E_RefreshType.HalfRefresh:
		wave_norm_refresh_time = randf_range(norm_refresh_time_range_in_half_refresh.x, norm_refresh_time_range_in_half_refresh.y)
	else:
		wave_norm_refresh_time = randf_range(norm_refresh_time_range_in_total_refresh.x, norm_refresh_time_range_in_total_refresh.y)
	wave_min_time_timer.start(CLASSIC_EARLY_CHECK_SECONDS if _classic_spawn_timing else time_min_wave)
	wave_norm_refresh_timer.start(wave_norm_refresh_time)
	signal_norm_time.emit(wave_norm_refresh_time)

## 读取本波敌人实际剩余血量，应用初代盾牌权重并计入雪人回血。
func _classic_wave_health() -> int:
	var total_health: int = 0 # 仅累计当前波仍敌对的单位。
	for zombie: Zombie000Base in zombie_manager.zombie_wave_manager.zombie_wave_create_manager.wave_all_zombies:
		# 已死亡、魅惑或离场的本波僵尸不再贡献血量。
		if is_instance_valid(zombie) and zombie.is_inside_tree() and not zombie.is_queued_for_deletion() \
				and not zombie.is_death and not zombie.is_hypno and zombie.curr_wave == curr_wave:
			var health: HpComponentZombie = zombie.hp_component as HpComponentZombie # 当前本体与各类护甲的血量。
			if health == null:
				total_health += zombie.hp_component.get_all_hp()
			else:
				total_health += health.get_all_hp() - health.curr_hp_armor2 \
					+ int(health.curr_hp_armor2 * CLASSIC_SHIELD_HEALTH_WEIGHT)
			if zombie is Zombie014Bobsled:
				total_health += zombie.passenger_wave_health()
	return total_health

## 初代节奏在保护结束后检查实际血量，达标时只缩短倒计时一次。
func _process(_delta: float) -> void:
	if _is_suspended or not zombie_manager.is_game_running() \
			or curr_refresh_status != E_RefreshStatus.AwaitRefresh:
		return
	if wave_norm_refresh_timer.time_left <= CLASSIC_EARLY_COUNTDOWN_SECONDS:
		set_process(false)
	elif _classic_wave_health() <= refresh_health:
		wave_norm_refresh_timer.start(CLASSIC_EARLY_COUNTDOWN_SECONDS)
		set_process(false)

## 判断残半刷新
func judge_half_refresh(all_loss_hp:int, wave:int):
	## 可以残半刷新时，更新当前波次僵尸血量，僵尸掉血信号连接触发
	if not _classic_spawn_timing and wave == curr_wave and curr_can_refresh_type == E_RefreshType.HalfRefresh:
		wave_current_health -= all_loss_hp

		if wave_current_health <= refresh_health or zombie_manager.natural_refresh_zombie_count <= 0:
			_trigger_refresh()

## [param zombie_num] 为自然刷新参与数量，博士及其召唤物不阻塞旗前波的清空刷新。
func judge_total_refresh(zombie_num: int) -> void:
	if curr_can_refresh_type == E_RefreshType.TotalRefresh and zombie_num <= 0:
		_trigger_refresh()

## 等待最短波间隔后触发提前刷新；关卡结束或本波不再允许刷新时不新增等待。
func _trigger_refresh():
	if _is_suspended or not zombie_manager.is_game_running() or curr_can_refresh_type == E_RefreshType.Null:
		return
	if curr_refresh_status == E_RefreshStatus.AwaitRefresh:
		refresh_once()
	else:
		# 多个掉血回调可能同时等待，绑定本次刷新版本，停止或切波后旧等待失效。
		var refresh_generation: int = _refresh_generation
		await signal_start_await_refresh
		if not _is_suspended and refresh_generation == _refresh_generation and curr_refresh_status == E_RefreshStatus.AwaitRefresh:
			refresh_once()

## 波次最小时间到达后允许提前刷新；结束战斗后不重新激活刷新状态。
func _on_wave_min_time_timer_timeout() -> void:
	if _is_suspended or not zombie_manager.is_game_running() or curr_can_refresh_type == E_RefreshType.Null:
		return
	curr_refresh_status = E_RefreshStatus.AwaitRefresh
	if _classic_spawn_timing:
		set_process(true)
		return
	signal_start_await_refresh.emit()
	# 选行失败可能产生空波；达到最短等待后重新检查，避免依赖一次不存在的死亡信号。
	if curr_refresh_status != E_RefreshStatus.AwaitRefresh:
		return
	if curr_can_refresh_type == E_RefreshType.TotalRefresh:
		judge_total_refresh(zombie_manager.natural_refresh_zombie_count)
	elif curr_can_refresh_type == E_RefreshType.HalfRefresh:
		if wave_current_health <= refresh_health or zombie_manager.natural_refresh_zombie_count <= 0:
			_trigger_refresh()

## 正常计时到达后请求下一波；关卡已结束时忽略回调。
func _on_wave_norm_refresh_timer_timeout() -> void:
	if not _is_suspended and curr_refresh_status == E_RefreshStatus.AwaitRefresh:
		refresh_once()

## 消费本波刷新机会并延迟发出下一波信号；结束战斗后不再排队刷新请求。
func refresh_once() -> void:
	if _is_suspended or not zombie_manager.is_game_running() \
			or curr_refresh_status == E_RefreshStatus.CompleteRefresh \
			or curr_can_refresh_type == E_RefreshType.Null:
		return
	curr_refresh_status = E_RefreshStatus.CompleteRefresh
	set_process(false)
	curr_can_refresh_type = E_RefreshType.Null
	# 延迟事件携带自身波次代数；停止、切波和切阶段都会废弃旧请求。
	_deliver_refresh.call_deferred(_refresh_generation)

## 唯一刷新发放接口：失效代数丢弃，暂停中的有效请求保留，恢复后恰好投递一次。
func _deliver_refresh(generation: int) -> void:
	if generation != _refresh_generation or _delivered_generation == generation \
			or curr_refresh_status != E_RefreshStatus.CompleteRefresh:
		return
	if _is_suspended or not zombie_manager.is_game_running():
		return
	_delivered_generation = generation
	signal_refresh.emit(generation)

## 供下游核验请求身份；只有本代确实发放的信号可以推进波次。
func is_current_refresh_request(generation: int) -> bool:
	return generation == _refresh_generation and _delivered_generation == generation \
		and curr_refresh_status == E_RefreshStatus.CompleteRefresh \
		and not _is_suspended and zombie_manager.is_game_running()
