extends ComponentNormBase
class_name MoveComponent
## 根据ground节点移动\速度移动的组件
## 移动组件只和owner的is_walk属性、_ground节点和AnimationTree节点有关
## 移动组件要求owner必须有is_walk属性

@onready var owner_zombie: Zombie000Base = owner
@onready var _ground: Sprite2D = get_node_or_null("../Body/BodyCorrect/_ground")
@onready var body: BodyCharacter = %Body

## 未覆盖时的基础移动速度，单位像素/秒。
const DEFAULT_ORI_SPEED: float = 20.0

## 移动方式
enum E_MoveMode {
	Ground,	## 根据ground节点移动
	Speed,	## 根据速度移动
}

## 斜面移动的y值,斜面时每帧更新
var y_value_correct_slope:float = 0
## 屋顶斜坡 移动方向y值修正,移动时,对应y方向的修正,
var move_dir_y_correct_slope:Vector2 = Vector2.ZERO

## 爬梯下降的速度
const SpeedLadderDown:float=100
## 每次爬梯子移动的最大x值
const MaxXOnLadderUp :float = 25
## 爬梯移动的y值,爬梯时每帧更新
var y_value_correct_ladder:float = 0
## 爬梯移动上升的y累计值,爬梯时每帧更新,爬梯完成后下来
var sum_y_value_correct_ladder_up:float = 0
## 爬梯移动下降的y累计值,爬梯时每帧更新
var sum_y_value_correct_ladder_down:float = 0
## 梯子移动y值修正方向,根据状态决定上下移动
var move_dir_y_correct_ladder:Vector2 = Vector2(1, 2.5)
## 爬梯子时移动的x值
var x_on_ladder:float = 0
## 爬梯子状态
var ladder_state :E_LadderState = E_LadderState.None
enum E_LadderState{
	None,
	Up,
	Down,
}

@export var move_mode:E_MoveMode = E_MoveMode.Ground
## 根据速度移动
@export var ori_speed :float = DEFAULT_ORI_SPEED
## 乘入角色速度和动作倍率后的当前移动速度。
var curr_speed :float = DEFAULT_ORI_SPEED
var curr_speed_product :float
var curr_speed_move :float = 1
## 只影响实际位移的来源倍率，不改变动画、啃咬或攻击冷却。
var _move_rate_sources: Dictionary[int, float] = {}
## 当前所有移动专属倍率的乘积；没有来源时为 1。
var _move_rate: float = 1.0
## 本次入场加速区的世界左界。正无穷表示加速未启用或已结束。
var _entry_acceleration_left_x: float = INF
## 恐惧来源独立于魅惑阵营；任一来源存活时反向行走。
var _flee_sources: Dictionary[int, bool] = {}

## 根据ground移动
## 上一帧的ground节点位置
var _previous_ground_global_x:float
## 移动状态
enum WalkingStatus {start, walking, end}
var walking_status := WalkingStatus.end

## 是否移动
var is_move := true

## 移动因素
var move_factors:Dictionary[E_MoveFactor, bool] = {}

## 影响移动的因素、跳跃、舞王入场被卡、伴舞攻击
enum E_MoveFactor{
	IsDisable,			## 组件禁用
	IsCharacter,		## 特殊角色本身(使用该因素不能有冲突)
	IsAttack,			## 攻击
	IsBombDeath,		## 被炸死
	IsJump,				## 跳跃
	IsJacksonEnterPlant,	## 舞王入场被植物卡住
	IsDancerAttack,			## 伴舞攻击
	IsSwimingChange,		## 进入或离开泳池间隙
	IsAnimGap,				## 动画过度间隙
	ForcedDisplacement,		## 正在由共用入口执行强制位移
	IsDeath,				## 停止移动的死亡时
}

signal signal_move_body_y(move_y_value:float)

## 地面推移已经完成一个实际步段，[param from_x] 和 [param to_x] 为修正坡面后的世界横坐标范围。
signal signal_ground_slide(from_x: float, to_x: float)
## 由共用抛飞真实轨迹触地时发出；途中取消、换行或推移结束均不会发出。
signal signal_forced_landed

## 不同来源的轨迹可同时结算，同类轨迹至多保留一条。
enum E_ForcedMotion {
	Push, ## 水平击退或吹飞。
	Launch, ## 带抛物线和落地回调的击飞。
	LaneShift, ## 换行期间仍可沿新的一行向前走。
}

## 一条使用物理时间推进的位移轨迹。
class ForcedMotion:
	## 世界坐标中的总位移，单位像素。
	var offset: Vector2
	## 轨迹持续的战斗秒数。
	var duration: float
	## 已推进的战斗秒数。
	var elapsed: float = 0.0
	## 开始时已抬起的高度，单位世界像素。
	var initial_lift: float = 0.0
	## 本次新增的抛物线高度，单位世界像素。
	var arc_height: float = 0.0
	## 水平风推使用缓入缓出；其他已有位移保持线性时序。
	var smooth_push: bool = false
	## 可选的风推战局门禁，结束或换阶段后取消余程，不执行完成回调。
	var push_validity: Callable
	## 只有存活并到达轨迹终点才执行的回调。
	var on_finish: Array[Callable] = []

	## 将时间进度 [param progress] 转为位移进度；两端速度归零，避免瞬移式起停。
	func travel_at(progress: float) -> float:
		return progress * progress * (3.0 - 2.0 * progress) if smooth_push else progress

	## 按 [param progress]（0 到 1）合成抛高，落地时恢复到地面。
	func lift_at(progress: float) -> float:
		return (initial_lift + 4.0 * arc_height * progress) * (1.0 - progress)

## 当前生效的轨迹，空闲时关闭物理处理。
var _forced_motions: Dictionary[E_ForcedMotion, ForcedMotion] = {}

func _ready() -> void:
	super()
	curr_speed = ori_speed
	set_physics_process(false)
	owner_zombie.signal_character_death.connect(cancel_forced_displacement)

## 返回是否正在被抛起。纯水平击退只占用移动，抛起还会暂停攻击和动画。
func is_forced_airborne() -> bool:
	return _forced_motions.has(E_ForcedMotion.Launch)


## 返回是否正在因水平击退或抛起而暂停普通行走。
func is_forced_moving() -> bool:
	return is_forced_airborne() or _forced_motions.has(E_ForcedMotion.Push)


## [param source_id] 的移动倍率更新为 [param multiplier]；1 撤销，0 停止位移但不停止啃咬。
## 免控只拒绝新的减速，保留加速和来源解除；物种自身耗能不经此入口。
func set_move_rate_source(source_id: int, multiplier: float) -> void:
	if not is_finite(multiplier) or multiplier < 0.0:
		return
	if is_equal_approx(multiplier, 1.0):
		_move_rate_sources.erase(source_id)
	elif multiplier < 1.0 and is_instance_valid(owner_zombie) and not owner_zombie.can_receive_control_effects():
		return
	else:
		_move_rate_sources[source_id] = multiplier
	_move_rate = 1.0
	for rate: float in _move_rate_sources.values(): # 不同来源独立组合，恢复其中一个不会清除其他减速。
		_move_rate *= rate
	update_previous_ground_global_x()


## 设置 [param source_id] 的恐惧 [param enabled]；只改变行走方向和攻击资格，不改变阵营。
func set_flee_source(source_id: int, enabled: bool) -> void:
	if enabled and is_instance_valid(owner_zombie) and not owner_zombie.can_receive_control_effects():
		return
	var was_fleeing: bool = is_fleeing() # 仅在总开关变化时翻转，重复命中不会来回转向。
	if enabled:
		_flee_sources[source_id] = true
	else:
		_flee_sources.erase(source_id)
	if was_fleeing == is_fleeing() or not is_instance_valid(owner_zombie):
		return
	owner_zombie.refresh_flee_direction()
	if is_instance_valid(owner_zombie.attack_component):
		owner_zombie.attack_component.change_is_enabling(not is_fleeing(),
			ComponentNormBase.E_IsEnableFactor.Fear)
	update_previous_ground_global_x()


## 返回是否有有效恐惧来源；移动处理仍可运行。
func is_fleeing() -> bool:
	return not _flee_sources.is_empty()


## [param blover_airborne] 允许三叶草吹动被归类为飞行目标的载具，其他强制位移仍受载具门禁限制。
func _can_shift_alive(blover_airborne: bool = false) -> bool:
	return is_inside_tree() and is_instance_valid(owner_zombie) and not owner_zombie.is_death \
		and owner_zombie.curr_be_attack_status != Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder \
		and not owner_zombie.is_queued_for_deletion() \
		and (not owner_zombie.is_vehicle() or (blover_airborne and owner_zombie.is_blover_flying_target()))


## 外部击退、抛起和换行遵守免控资格，且不得与原生飞行同时写入脚点或身体高度。
## [param blover_airborne] 是三叶草飞行分类的载具例外，沿用其余通用门禁。
func can_receive_forced_displacement(blover_airborne: bool = false) -> bool:
	return _can_shift_alive(blover_airborne) and owner_zombie.can_receive_control_effects() \
		and not owner_zombie.is_native_airborne()


## 原生飞行控制者提交 [param offset] 世界位移；复用坡面和行走基准维护，不创建第二条强制轨迹。
## 只有正在原生飞行且没有旧强制轨迹的存活角色可使用，拒绝时由控制者收尾。
func apply_native_flight_displacement(offset: Vector2) -> bool:
	if not _can_shift_alive() or not owner_zombie.is_native_airborne() \
			or not _forced_motions.is_empty() or not offset.is_finite():
		return false
	_shift_forced(offset)
	return true


## 将存活角色移动 [param offset] 世界像素，X 向右，Y 向下。
## [param seconds] 为 0 时立即移动。[param height] 为抛物线高度，纯换行和吹动可与抛起叠加。
## [param landed] 在完成位移时调用。连续抛起保留剩余位移和回调，死亡时取消。
## [param smooth_push] 仅为纯水平推移启用缓动；重叠的同向风推合并到当前终点，不累计多格位移。
## [param push_validity] 可限制缓动风推的战局寿命；其他原生位移不使用此门禁。
## [param blover_airborne] 由三叶草统一分类入口传入，只解除飞行载具的位移限制。
## 返回是否接受本次位移。离场、死亡或无效参数返回 false。
func apply_forced_displacement(offset: Vector2, seconds: float = 0.0,
		height: float = 0.0, landed: Callable = Callable(), smooth_push: bool = false,
		push_validity: Callable = Callable(), blover_airborne: bool = false) -> bool:
	if not can_receive_forced_displacement(blover_airborne) or not offset.is_finite() \
			or not is_finite(seconds) or seconds < 0.0 or not is_finite(height) or height < 0.0:
		return false
	if seconds == 0.0:
		if height == 0.0 and offset.y == 0.0 and not is_forced_airborne():
			_shift_ground_push(offset)
		else:
			_shift_forced(offset)
		if landed.is_valid():
			landed.call()
		return true
	var motion := ForcedMotion.new() # 新请求从当前世界位置开始走相对位移。
	motion.offset = offset
	motion.duration = seconds
	motion.arc_height = height
	var kind: E_ForcedMotion = E_ForcedMotion.LaneShift if offset.x == 0.0 else E_ForcedMotion.Push # 默认按位移方向区分。
	motion.smooth_push = smooth_push and height == 0.0 and offset.y == 0.0 and kind == E_ForcedMotion.Push
	if motion.smooth_push:
		motion.push_validity = push_validity
		var active_push: ForcedMotion = _forced_motions.get(kind) # 同时触发的暴雪共享尚未完成的一格滑行。
		if active_push != null and active_push.smooth_push and signf(active_push.offset.x) == signf(offset.x) \
				and (not active_push.push_validity.is_valid() or bool(active_push.push_validity.call())):
			if landed.is_valid():
				active_push.on_finish.append(landed)
			return true
	if height > 0.0:
		kind = E_ForcedMotion.Launch
		var previous: ForcedMotion = _forced_motions.get(kind) # 重抛时沿用在空中的高度和余程。
		if previous != null:
			var progress: float = previous.elapsed / previous.duration # 旧轨迹已走过的比例。
			motion.offset += previous.offset * (1.0 - progress)
			motion.initial_lift = previous.lift_at(progress)
			motion.on_finish.append_array(previous.on_finish)
		# 抛离梯子后以地面为落点，取消旧的爬梯高度和下降进度。
		if ladder_state != E_LadderState.None:
			body.pose_position.y += sum_y_value_correct_ladder_up - sum_y_value_correct_ladder_down
			ladder_state = E_LadderState.None
	if landed.is_valid():
		motion.on_finish.append(landed)
	_forced_motions[kind] = motion
	_update_forced_motion_state()
	return true


## 按物理帧 [param delta] 推进各轨迹，全部更新后再触发落地或吹飞结算。
func _physics_process(delta: float) -> void:
	if owner_zombie.is_death or owner_zombie.is_queued_for_deletion():
		cancel_forced_displacement()
		return
	var completed: Array[Callable] = [] # 回调可结束战斗或新增位移，延迟到更新所有轨迹之后。
	var grounded: bool = false # 只在本帧达到抛飞的真实终点时报告落地。
	for kind: E_ForcedMotion in _forced_motions.keys(): # 键快照允许删除已完成的轨迹。
		var motion: ForcedMotion = _forced_motions[kind] # 本帧正在推进的轨迹。
		if motion.push_validity.is_valid() and not bool(motion.push_validity.call()):
			_forced_motions.erase(kind)
			continue
		var before: float = motion.elapsed / motion.duration # 本帧开始前已走过的比例。
		motion.elapsed = minf(motion.elapsed + delta, motion.duration)
		var progress: float = motion.elapsed / motion.duration # 本帧结束时应走到的比例。
		var offset: Vector2 = motion.offset * (motion.travel_at(progress) - motion.travel_at(before)) # 本步实际世界位移。
		if kind == E_ForcedMotion.Push and not is_forced_airborne():
			_shift_ground_push(offset)
		else:
			_shift_forced(offset)
		if kind == E_ForcedMotion.Launch:
			body.set_forced_lift(motion.lift_at(progress))
		if progress == 1.0:
			_forced_motions.erase(kind)
			completed.append_array(motion.on_finish)
			grounded = grounded or kind == E_ForcedMotion.Launch
	_update_forced_motion_state()
	if grounded:
		signal_forced_landed.emit()
	for callback: Callable in completed: # 已落地或已到达吹飞终点的回调。
		if owner_zombie.is_death or owner_zombie.is_queued_for_deletion():
			break
		if callback.is_valid():
			callback.call()

## 按统一规则完成横向推移 [param offset] 后通知地面表现，不改变推移量或回调时序。
func _shift_ground_push(offset: Vector2) -> void:
	var start_x: float = owner_zombie.global_position.x # 当前实际脚点的世界横坐标。
	_shift_forced(offset)
	if offset.x != 0.0:
		signal_ground_slide.emit(start_x, owner_zombie.global_position.x)


## 应用本步 [param offset] 世界位移。横移跨斜坡时更新脚点并防止非致死击退触发清场。
func _shift_forced(offset: Vector2) -> void:
	# 位移使用全局横坐标，屋顶高度按起点和终点之差计算。
	var old_x: float = owner_zombie.global_position.x
	owner_zombie.global_position += offset
	if offset.x == 0.0:
		return
	var new_x: float = owner_zombie.global_position.x # 本步水平终点。
	var game: MainGameManager = Global.main_game # 仅使用本角色所属战场的斜坡和清场边界。
	if is_instance_valid(game) and game.is_ancestor_of(owner_zombie):
		if is_instance_valid(game.main_game_slope):
			signal_move_body_y.emit(game.main_game_slope.get_all_slope_y(new_x)
				- game.main_game_slope.get_all_slope_y(old_x))
		if offset.x > 0.0 and is_instance_valid(game.zombie_manager) \
				and new_x > game.zombie_manager.zombie_range_pos_x.y:
			owner_zombie.nonlethal_displacement_exile = true
	update_previous_ground_global_x()


## 只更新强制位移自身的因子，保留眩晕、攀爬及其他行动状态。
func _update_forced_motion_state() -> void:
	var hold_movement: bool = is_forced_moving() # 换行只改变纵向位置，不暂停行走。
	if move_factors.get(E_MoveFactor.ForcedDisplacement, false) != hold_movement:
		update_move_factor(hold_movement, E_MoveFactor.ForcedDisplacement)
	var speed: float = 0.0 if is_forced_airborne() else 1.0 # 空中暂停自身动作。
	var factor := Character000Base.E_Influence_Speed_Factor.ForcedAirborne # 抛起单独占用的速度因子。
	if owner_zombie.influence_speed_factors.get(factor, 1.0) != speed:
		owner_zombie.update_speed_factor(speed, factor)
	set_physics_process(not _forced_motions.is_empty())


## 抓取或死亡时取消所有位移和完成回调，并清除身体的抛高偏移。
func cancel_forced_displacement() -> void:
	if _forced_motions.is_empty():
		return
	_forced_motions.clear()
	body.set_forced_lift(0.0)
	_update_forced_motion_state()

## 根据角色速度修改移动速度
func owner_update_speed(speed_product:float):
	curr_speed = ori_speed * speed_product * curr_speed_move
	curr_speed_product = speed_product

## 角色速度不变的情况下,只修改移动速度,(跳跳僵尸使用)
func update_only_move_speed(new_speed_move:float=1):
	self.curr_speed_move = new_speed_move
	curr_speed = ori_speed * curr_speed_product * self.curr_speed_move


## 返回速度模式合成后的局部移速，单位为像素/秒，包含只影响位移的倍率。
## 启停和方向由调用方根据当前角色状态决定。
func get_speed_mode_speed() -> float:
	return curr_speed * _move_rate


## 更新影响移动的因素 true表示不移动
func update_move_factor(value:bool, move_factor:E_MoveFactor):
	move_factors[move_factor] = value
	## 全为false时移动
	is_move = move_factors.values().all(func(v): return v == false)
	if is_move:
		_walking_start()

## 获取除了伴舞攻击因素之外的移动结果
func get_exclude_dancer_move_res():
	# 除了 IsDancerAttack，其他 factor 只要有 true 就不能移动
	return not move_factors.keys().any(
		func(k): return k != E_MoveFactor.IsDancerAttack and move_factors[k] == true
	)

func update_move_mode(new_move_mode:E_MoveMode):
	move_mode = new_move_mode

## 初始化敌人首次向左入场的移速倍率，[param left_x] 是包含在加速区内的世界左界。
func begin_entry_acceleration(left_x: float) -> void:
	if owner_zombie.global_position.x >= left_x and owner_zombie.direction_x_root > 0 and not owner_zombie.is_hypno:
		_entry_acceleration_left_x = left_x
		set_move_rate_source(get_instance_id(), 2.0)

## 魅惑友军的这次原生右行从 [param previous_x] 开始；强制位移、传送和坡度修正不会发出。
signal walked_right(previous_x: float)

func _process(delta: float) -> void:
	# 跨过左界或转向后只撤销本次入场倍率，被推回右侧也不会重新开启。
	if is_finite(_entry_acceleration_left_x) and (owner_zombie.global_position.x < _entry_acceleration_left_x \
			or owner_zombie.direction_x_root <= 0 or owner_zombie.is_hypno):
		_entry_acceleration_left_x = INF
		set_move_rate_source(get_instance_id(), 1.0)
	if owner_zombie.is_stunned() or is_forced_moving():
		update_previous_ground_global_x()
		return
	if ladder_state == E_LadderState.Down:
		move_y_correct_ladder_down(delta)
	if is_move:
		var previous_x: float = owner_zombie.global_position.x if owner_zombie.is_hypno \
			and owner_zombie.direction_x_root < 0 and walked_right.has_connections() else INF # 只有订阅实际右行的友军需要追踪脚点。
		match move_mode:
			E_MoveMode.Ground:
				if walking_status == WalkingStatus.end:
					_previous_ground_global_x = _ground.global_position.x
				elif walking_status == WalkingStatus.start:
					walking_status = WalkingStatus.walking
					_previous_ground_global_x = _ground.global_position.x
				else:
					_walk()

			E_MoveMode.Speed:
				var move_x: float = delta * get_speed_mode_speed() * owner_zombie.direction_x_root # 冻结值等仅缩放实际位移。
				owner_zombie.position.x -= move_x

				move_y_correct(move_x)
		if is_finite(previous_x) and owner_zombie.global_position.x > previous_x:
			walked_right.emit(previous_x)

func _walk():
	# 计算ground的全局坐标变化量
	var ground_global_offset: float = (_ground.global_position.x - _previous_ground_global_x) * _move_rate # 动画步幅与速度模式共用移动专属倍率。
	# 反向调整zombie的position.x以抵消ground的移动
	owner_zombie.position.x -= ground_global_offset
	# 更新记录值
	_previous_ground_global_x = _ground.global_position.x
	move_y_correct(ground_global_offset)

## 按已完成的水平位移 [param move_x] 修正斜坡和梯子的纵向位置。
## [param move_x] 沿用调用方的左向为正约定，世界坐标的跨步终点为当前脚点。
func move_y_correct(move_x:float):
	var game: MainGameManager = Global.main_game # 预览僵尸和独立演出节点可能没有活跃战场。
	var slope: MainGameSlope = game.main_game_slope if is_instance_valid(game) else null # 可选的场地高度查询。
	if is_instance_valid(slope) and slope.sample_walking_height and game.is_ancestor_of(owner_zombie):
		var destination_x: float = owner_zombie.global_position.x # 已完成横移后的世界 X。
		var row := owner_zombie.get_parent() as CanvasItem # 攻击行的局部变换决定步幅的世界长度。
		var step: Vector2 = row.get_global_transform().basis_xform(Vector2(move_x, 0.0)) # 将已扣除的局部步幅映射到世界。
		var source_x: float = destination_x + step.x # 由终点和反向步幅还原跨步起点。
		var height_delta: float = slope.get_all_slope_y(destination_x) - slope.get_all_slope_y(source_x) # 精确跨坡差量。
		if not is_zero_approx(height_delta):
			signal_move_body_y.emit(height_delta)
	elif move_dir_y_correct_slope != Vector2.ZERO:
		move_y_correct_slope(move_x)
	if ladder_state == E_LadderState.Up:
		move_y_correct_ladder_up(move_x)

## 移动y的方向修正_斜面
func move_y_correct_slope(move_x:float):
	y_value_correct_slope = -move_x / move_dir_y_correct_slope.x * move_dir_y_correct_slope.y
	signal_move_body_y.emit(y_value_correct_slope)

## 爬梯移动修正y,只修改body y值
func move_y_correct_ladder_up(move_x:float):
	## 梯子移动修正
	x_on_ladder += abs(move_x)
	y_value_correct_ladder = -abs(move_x) / move_dir_y_correct_ladder.x * move_dir_y_correct_ladder.y
	sum_y_value_correct_ladder_up -= y_value_correct_ladder
	body.position.y += y_value_correct_ladder
	if x_on_ladder >= MaxXOnLadderUp:
		ladder_state = E_LadderState.Down

## 下降状态 爬梯移动修正y,每帧更新,
func move_y_correct_ladder_down(delta: float):
	y_value_correct_ladder = SpeedLadderDown * delta
	sum_y_value_correct_ladder_down += y_value_correct_ladder
	if sum_y_value_correct_ladder_down > sum_y_value_correct_ladder_up:
		y_value_correct_ladder -= sum_y_value_correct_ladder_down - sum_y_value_correct_ladder_up
		ladder_state = E_LadderState.None
	body.position.y +=  y_value_correct_ladder

## 开始爬梯子
func start_ladder():
	# 临时飞行期间脚点只是地面投影，不能把飞越的梯子状态带到远处落点。
	if owner_zombie.is_native_airborne():
		return
	if ladder_state != E_LadderState.None:
		#printerr("正在爬梯子,无法继续爬梯子")
		pass
	else:
		x_on_ladder = 0
		sum_y_value_correct_ladder_up = 0
		sum_y_value_correct_ladder_down = 0
		ladder_state = E_LadderState.Up

func _walking_start():
	walking_status = WalkingStatus.start
	#print(111,"walk is start")

func _walking_end():
	walking_status = WalkingStatus.end
	#print(111,"walk is end")

## 外部位移后重置动画行走基准；纯速度移动的僵尸可以没有地面标记。
func update_previous_ground_global_x() -> void:
	if is_instance_valid(_ground):
		_previous_ground_global_x = _ground.global_position.x

## 动画结束时
@warning_ignore("unused_parameter")
func _on_animation_finished(anim_name: StringName) -> void:
	_walking_end()

### 动画开始时
#func _on_animation_tree_animation_started(anim_name: StringName) -> void:
	#_walking_start()


## 启用组件
func enable_component(is_enable_factor:E_IsEnableFactor):
	super(is_enable_factor)
	if is_enabling:
		update_move_factor(false, E_MoveFactor.IsDisable)

## 禁用组件
func disable_component(is_enable_factor:E_IsEnableFactor):
	super(is_enable_factor)
	update_move_factor(true, E_MoveFactor.IsDisable)
