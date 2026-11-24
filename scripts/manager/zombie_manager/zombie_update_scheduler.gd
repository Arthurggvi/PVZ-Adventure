## 战场内的低频复查和图集准备。周期以各实例累积的游戏时间为准。
extends Node
class_name ZombieUpdateScheduler

## 雪橇队员的本场分帧资源准备，复用此调度器而非另建场景加载服务。
const CrewWarmup = preload("res://scripts/manager/zombie_manager/bobsled_crew_warmup.gd")
## 雪橇集中散队的原子工作队列，保留单辆四人同步出生的原始语义。
const CrashBatch = preload("res://scripts/manager/zombie_manager/bobsled_crash_batch.gd")
## 雪橇三名乘客共享姿态仅依赖原AnimationPlayer的轨道一致性，不预加载场景。
const BobsledPose = preload("res://scripts/character/zombie/bobsled_shared_pose.gd")

## 同一周期最多划分的起始相位数。
const PHASE_COUNT := 16
## 构建图集每帧的主线程预算，单位为微秒。
const ATLAS_WORK_USEC := 2000
## 单场额外的共享纹理上限，单位为字节。
const ATLAS_BUDGET_BYTES := 32 * 1024 * 1024
## 每帧最多新增三个同步结算后排队的僵尸，已经开始的一次生成保持原子提交。
const MAX_DEFERRED_SPAWNS := 3
## 分帧生成工作预算，单位为微秒，避免同一帧集中构建大量角色。
const SPAWN_WORK_USEC := 5500

## 一项允许跨帧执行的状态复查。动作引信、伤害和物理判定仍由各自组件驱动。
class Check:
	## 复查所属节点上的方法，不接收参数。
	var callback: Callable
	## 稳定复查间隔，单位为游戏秒。
	var interval: float
	## 下一次应复查的战场时间，单位为游戏秒。
	var deadline: float

## 按回调登记，重复绑定不改变现有周期。
var _checks: Dictionary[Callable, Check] = {}
## 关卡暂停时随节点处理一起暂停的时钟。
var _seconds := 0.0
## 分配给下一项检查的相位。
var _phase := 0
## 逐张处理，每次只解码一个外观的分件。
var _atlas_queue: Array[ZombieSpriteAtlas] = []
## 完成并保留在本场的图集纹理字节数。
var _atlas_bytes := 0
## 只有出现雪橇时才创建的队员资源准备，避免普通关卡加载该角色场景。
var _crew_warmup: RefCounted
## 只在雪橇损毁时才创建的集中散队事务队列。
var _crash_batch: RefCounted
## 战斗事件冻结的数据入队，留在本关的空闲步中逐批发布实际实体。
var _deferred_spawns: Array[Callable] = []
## 本局每个等阶的乘客姿态兼容性，避免同波生成多车时重复验证数千个关键帧。
var _bobsled_pose_compatibility: Dictionary[StringName, bool] = {}


## 默认等待首个检查，随后在角色常规更新之后读取本帧的场上状态。
func _ready() -> void:
	process_priority = 20
	_update_processing()


## 注册 [param callback]，以 [param interval] 游戏秒为周期。
## 首次复查分散在半个到一个周期内，需要立即生效的初始化由调用者完成。
func schedule(callback: Callable, interval: float) -> void:
	if interval <= 0.0 or not is_finite(interval) or not callback.is_valid() or _checks.has(callback):
		return
	var check := Check.new() # 同一物种的不同实例也各有自己的检查进度。
	check.callback = callback
	check.interval = interval
	check.deadline = _seconds + interval * (0.5 + 0.5 * float(_phase) / PHASE_COUNT)
	_phase = (_phase + 1) % PHASE_COUNT
	_checks[callback] = check
	_update_processing()


## 注销 [param callback]，允许重复取消，或从一次检查的回调中取消自己。
func cancel(callback: Callable) -> void:
	_checks.erase(callback)
	_update_processing()


## 有低频回调、图集、雪橇准备或分帧创建时才运行本场调度器。
func _update_processing() -> void:
	set_process(not _checks.is_empty() or not _atlas_queue.is_empty()
		or (_crew_warmup != null and _crew_warmup.has_work())
		or (_crash_batch != null and _crash_batch.has_work()) or not _deferred_spawns.is_empty())

## 由真实雪橇出生时请求 [param tier] 对应的子队员外观；同等阶只排队一次。
func request_bobsled_crew(tier: StringName) -> void:
	if _crew_warmup == null:
		_crew_warmup = CrewWarmup.new()
		_crew_warmup.configure(get_parent() as ZombieManager)
	_crew_warmup.request(tier)
	_update_processing()


## 使用本战 [param tier] 对应的正式动画库判定是否可共享三名乘客姿态。
## [param players] 按Body、Body2、Body3、Body4排序；同等阶只验证一次，特殊动作不兼容时回退原版。
func can_share_bobsled_pose(tier: StringName, players: Array[AnimationPlayer]) -> bool:
	if not _bobsled_pose_compatibility.has(tier):
		_bobsled_pose_compatibility[tier] = BobsledPose.supports(players)
	return _bobsled_pose_compatibility[tier]

## [param sled] 护甲已破损且完成当前伤害结算的雪橇；每辆四人原子出生不拆分。
func enqueue_bobsled_crash(sled: Zombie014Bobsled) -> void:
	if _crash_batch == null:
		_crash_batch = CrashBatch.new()
	_crash_batch.request(sled)
	_update_processing()

## 返回本调度器的有效游戏秒数；用于扣除排队期间已经消耗的效果时长。
func active_seconds() -> float:
	return _seconds

## [param spawn] 是已冻结参数的单次生成；等本次伤害及波次回调结束后在本战场执行。
func enqueue_battle_spawn(spawn: Callable) -> void:
	_deferred_spawns.append(spawn)
	set_process(true)

## 按先入先出兑现。生成回调可能继续入队，新的工作在下一次预算周期处理。
func _advance_battle_spawns() -> void:
	var start: int = Time.get_ticks_usec() # 用真实耗时保护一帧的生成预算。
	var scheduled: int = mini(_deferred_spawns.size(), MAX_DEFERRED_SPAWNS) # 避免新入队回调占据本帧预算。
	for index: int in range(scheduled): # 至少尝试一项，单项不可按节点拆分。
		if index > 0 and Time.get_ticks_usec() - start >= SPAWN_WORK_USEC:
			return
		var spawn: Callable = _deferred_spawns.pop_front() # 此生成应使用原击杀时冻结的状态。
		if spawn.is_valid():
			spawn.call()

## 无图形模式只需要行为及计时，图形战场按剩余显存额度准备小图。
func can_pack_sprites() -> bool:
	return _atlas_bytes < ATLAS_BUDGET_BYTES and DisplayServer.get_name() != "headless"


## 排队构建 [param atlas]。原有分件在等候期间可照常绘制。
func queue_atlas(atlas: ZombieSpriteAtlas) -> void:
	_atlas_queue.append(atlas)
	_update_processing()


## 慢速读回或上传至多超出一个分件的时间，随后留待下帧。
func _advance_atlases() -> void:
	var deadline: int = Time.get_ticks_usec() + ATLAS_WORK_USEC # 只限制纯美术准备工作，不改变游戏时间。
	while not _atlas_queue.is_empty() and Time.get_ticks_usec() < deadline:
		var atlas: ZombieSpriteAtlas = _atlas_queue.front() # 一次只保留当前外观的解码位图。
		if atlas.advance(ATLAS_BUDGET_BYTES - _atlas_bytes):
			_atlas_bytes += atlas.bytes
			_atlas_queue.pop_front()
	if _atlas_queue.is_empty():
		_update_processing()


## 推进 [param delta] 游戏秒。掉帧后按当前状态检查一次，跳过已经过期的历史复查。
func _process(delta: float) -> void:
	_seconds += delta
	for check: Check in _checks.values(): # 回调可注册或取消任务，遍历当帧快照。
		if check.deadline > _seconds or _checks.get(check.callback) != check:
			continue
		var target := check.callback.get_object() as Node # 随实际节点生命周期清除失效登记。
		if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			cancel(check.callback)
			continue
		check.deadline += check.interval * (floorf((_seconds - check.deadline) / check.interval) + 1.0)
		if target.can_process():
			check.callback.call()
	if _crash_batch != null and _crash_batch.has_work():
		_crash_batch.advance() # 原子提交本帧预算允许的整辆雪橇。
	if not _deferred_spawns.is_empty():
		_advance_battle_spawns()
	if _crew_warmup != null and _crew_warmup.has_work():
		_crew_warmup.advance(ATLAS_WORK_USEC if _atlas_queue.is_empty() else ATLAS_WORK_USEC / 2)
	if not _atlas_queue.is_empty():
		_advance_atlases()
	_update_processing()
