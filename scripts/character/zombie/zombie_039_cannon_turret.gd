## 地面炮塔车沿途碾压，停在同行末列并周期性投射可拦截导弹。
extends Zombie000Base
class_name Zombie039CannonTurret

## 从炮车停稳开始计算的基础发射间隔，单位为战斗秒。
const FIRE_INTERVAL: float = 5.0
## 入场先用短斜率接上滚动，再保持匀速，单位为秒。
const ROLL_ACCEL_END: float = 0.24
## 车轮开始减速、车架开始前倾的动作时间，单位为秒。
const BRAKE_START: float = 1.04
## 轮胎制动完成的动作时间，单位为秒。
const BRAKE_END: float = 1.76
## 悬挂回弹完全结束的动作时间，单位为秒。
const SETTLE_END: float = 2.75
## 速度曲线的积分，换算为全程位移归一化系数。
const ROLL_INTEGRAL: float = BRAKE_START - ROLL_ACCEL_END * 0.5 + (BRAKE_END - BRAKE_START) * 0.5
## 花园飞艇的出生船和末格甲板之间没有连续路面。
const AIRSHIP_BOARD_ID: StringName = &"wonderland.garden_airship"
## 只在炮塔场景被实例化时载入导弹依赖。
const MISSILE_SCENE: PackedScene = preload("res://scenes/bullet/cannon_turret_missile.tscn")
## 每株位于命中四格内的植物承受的基础爆炸伤害。
@export_range(1, 2000, 1) var missile_damage: int = 1000

## 炮口坐标及底盘、炮身的分层演出。
@onready var _rig: CannonTurretPresentation = $Body/CannonRig
## 本场棋盘的末列锚点，入场计算时固定。
var _stop_x: float
## 刚出生时的世界横坐标，供制动插值使用。
var _entry_x: float
## 从出生到结束悬挂回弹的动作秒数。
var _entry_seconds: float = 0.0
## 下一发导弹的剩余战斗时间，停车后开始消耗。
var _fire_wait: float = FIRE_INTERVAL
## 发射速度换算所需的横纵格距，采用停车点所在棋盘的尺度。
var _cell_pitch: Vector2
## 调试或召唤直达末格时，首个有效战斗帧只碾压实际着地位置。
var _check_spawn_contact: bool = false
## 同一趟入场可能跨多帧或重复触及多格植物，实际植株只结算一次。
var _entry_crushed: Dictionary[int, bool] = {}
## 防止死亡信号和同时到达的其他伤害重复触发退场演出。
var _death_processed: bool = false


## 展示和战斗共用驾驶员锚点，只有正式战斗启动入场与发射逻辑。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/CannonRig/ChassisPivot/TurretPivot/HeadAnchor")])
	super()
	set_physics_process(character_init_type == E_CharacterInitType.IsNorm and _cell_pitch.x > 0.0)


## 获取实际末列，不假设旧战场和动态棋盘的列号顺序相同。
func ready_norm() -> void:
	super()
	var game: MainGameManager = Global.main_game # 炮车由所属战场管理器在棋盘配置完成后创建。
	var last_cell: PlantCell # 只在当前行查找最右侧的可用种植格。
	for cell: PlantCell in game.board.row_cells(lane): # 保留真实棋盘的行投影。
		if cell.is_queued_for_deletion():
			continue
		if last_cell == null or cell.get_global_rect().get_center().x > last_cell.get_global_rect().get_center().x:
			last_cell = cell
	if last_cell == null:
		return
	var landing_rect: Rect2 = last_cell.get_global_rect() # 末格中心与右侧着陆边缘。
	_stop_x = landing_rect.get_center().x
	_entry_x = global_position.x
	_cell_pitch = game.board.local_pitch(last_cell).max(Vector2.ONE)
	if _entry_x <= _stop_x:
		# 手动放在战场内时仍对齐末列，无须倒车穿越植物。
		_roll_to(_stop_x)
		_entry_seconds = SETTLE_END
		_check_spawn_contact = true
	else:
		if game.board.board_id == AIRSHIP_BOARD_ID:
			# 承重轮完整跨进甲板边缘再压悬挂，炮塔仍停在同行末格。
			_rig.prepare_deck_entry(_entry_x - landing_rect.end.x + minf(_cell_pitch.x * 0.16, 9.0))
		begin_right_entry(_stop_x)


## 炮车用自己的制动曲线，跳过普通角色的场外加速和定时器。
func judge_battlefield_update_speed() -> void:
	pass


## 地面重型载具沿用本项目的载具击退、恐惧和换行规则。
func is_vehicle() -> bool:
	return true


## 地刺反击沿用轮式载具爆胎规则，由现有击毁入口播放爆炸。
func be_caltrop() -> void:
	if not is_death and not is_queued_for_deletion():
		character_death_not_disappear()


## [param delta] 是物理帧的战斗秒数。发射计时随暂停、冻结及制动停止。
func _physics_process(delta: float) -> void:
	var game: MainGameManager = Global.main_game # 只在当前已进入战斗的关卡推进。
	if is_death or is_queued_for_deletion() or not is_instance_valid(game) or not game.is_ancestor_of(self) \
			or not game.zombie_manager.is_game_running() or is_action_suspended() or speed_factor_product() <= 0.0:
		return
	if _check_spawn_contact:
		_check_spawn_contact = false
		_crush_along_entry(game, global_position.x)
		if is_death or is_queued_for_deletion():
			return
	if _entry_seconds < SETTLE_END:
		var was_rolling: bool = _entry_seconds < BRAKE_END # 停车帧只完成最后一步位移。
		var previous_x: float = global_position.x # 保存本步前的车轮位置，避免快速行进漏掉格子。
		_entry_seconds = minf(_entry_seconds + delta, SETTLE_END)
		if was_rolling:
			var travel: float = _entry_travel(_entry_seconds) # 积分位置与实际滚动距离一致。
			_roll_to(lerpf(_entry_x, _stop_x, travel))
		_rig.pose_entrance(_entry_seconds, _entry_x - global_position.x, _entry_speed(_entry_seconds))
		if was_rolling:
			_crush_along_entry(game, previous_x)
			return
	if is_hypno:
		return
	_fire_wait -= delta
	if _fire_wait <= 0.0:
		_fire_wait += FIRE_INTERVAL
		_launch(game)


## 在 [param game] 中检查从 [param previous_x] 到当前点扫过的接地段；只在入场或出生接地时调用。
func _crush_along_entry(game: MainGameManager, previous_x: float) -> void:
	if is_hypno or not game.zombie_manager.is_lane_open(lane):
		return
	# 腾空时直接退出，不枚举下方浮台。
	var segments: Array[Vector2] = _rig.entry_ground_segments(_entry_x - previous_x, _entry_x - global_position.x)
	if segments.is_empty():
		return
	var contact: Vector2 = _rig.axle_offsets() # 轮轴包围的横向带，不使用炮身或阴影的范围。
	var board: BoardRuntime = game.board # 地块和植物均从当前棋盘取得。
	var cells: Array[PlantCell] = board.row_cells(lane) # 移动甲板按当前攻防行查询。
	var slope: MainGameSlope = game.main_game_slope # 屋顶正常随地势升降。
	var baseline: float = global_position.y # 平整路面使用原脚点。
	if is_instance_valid(slope):
		baseline -= slope.get_all_slope_y(global_position.x)
	for segment: Vector2 in segments: # 由靠近出生点的一端开始，腾空段已排除。
		var right: float = _entry_x - segment.x + contact.y # 扫掠的世界右边界。
		var left: float = _entry_x - segment.y + contact.x # 扫掠的世界左边界。
		var targets: Array[PlantCell] = [] # 只收集实际种植锚点进入轮轴下方的格。
		for cell: PlantCell in cells: # 不压到相同行投影却与脚点分离的浮台。
			if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
				continue
			var anchor_x: float = cell.get_global_rect().get_center().x # 植株横向站位，擦过格边不会被远程压扁。
			if anchor_x < left or anchor_x > right:
				continue
			var foot_y: float = baseline # 换算到锚点处的轨道脚点。
			if is_instance_valid(slope):
				foot_y += slope.get_all_slope_y(anchor_x)
			if board.definition != null and BoardQueries.ground_cell_from(board, Vector2(anchor_x, foot_y),
					lane, [cell]) != cell:
				continue
			targets.append(cell)
		targets.sort_custom(func(a: PlantCell, b: PlantCell) -> bool: # 右边的地刺等反击可以阻止继续碾压。
			return a.get_global_rect().get_center().x > b.get_global_rect().get_center().x)
		for cell: PlantCell in targets: # 按进场方向结算每格的真实植株。
			if not is_instance_valid(cell) or cell.is_queued_for_deletion():
				continue
			for plant: Plant000Base in cell.living_plants(): # 覆盖承托和伴生，保留植物自己的碾压规则。
				if is_death or is_queued_for_deletion() or is_hypno:
					return
				if not is_instance_valid(plant) or plant.is_death or plant.is_queued_for_deletion():
					continue
				var identity: int = plant.get_instance_id() # 多格占位只由首次接触触发。
				if not _entry_crushed.has(identity):
					_entry_crushed[identity] = true
					plant.be_flattened_from_enemy(self)


## 返回 [param seconds] 对应的归一化位移。匀速段与两端的平滑速度变化保持连续。
static func _entry_travel(seconds: float) -> float:
	if seconds <= ROLL_ACCEL_END:
		var ramp: float = seconds / ROLL_ACCEL_END # 加速段的归一化时间。
		return ROLL_ACCEL_END * ramp * ramp * ramp * (1.0 - 0.5 * ramp) / ROLL_INTEGRAL
	if seconds <= BRAKE_START:
		return (seconds - ROLL_ACCEL_END * 0.5) / ROLL_INTEGRAL
	if seconds >= BRAKE_END:
		return 1.0
	var duration: float = BRAKE_END - BRAKE_START # 均匀衔接的制动区间。
	var ramp: float = (seconds - BRAKE_START) / duration # 制动段的归一化时间。
	var braking_distance: float = duration * (ramp - ramp * ramp * ramp * (1.0 - 0.5 * ramp)) # 积分剩余速度。
	return (BRAKE_START - ROLL_ACCEL_END * 0.5 + braking_distance) / ROLL_INTEGRAL


## 返回 [param seconds] 对应的滚动速度相对巡航速度的比例，给悬挂起伏使用。
static func _entry_speed(seconds: float) -> float:
	return smoothstep(0.0, ROLL_ACCEL_END, seconds) * (1.0 - smoothstep(BRAKE_START, BRAKE_END, seconds))


## 移至 [param world_x] 并应用原生屋顶坡度修正，保持受击框与地面子弹对齐。
func _roll_to(world_x: float) -> void:
	var start_x: float = global_position.x # 制动前的脚点用于查询本步坡面高度差。
	global_position.x = world_x
	var slope: MainGameSlope = Global.main_game.main_game_slope # 旧屋顶和连续地形使用同一坡面查询。
	if is_instance_valid(slope):
		move_y_zombie(slope.get_all_slope_y(world_x) - slope.get_all_slope_y(start_x))


## 在 [param game] 的真实棋盘上随机选择命中范围，优先选择至少有一株活植物的区域。
func _launch(game: MainGameManager) -> void:
	var cells: Array[PlantCell] = _pick_footprint(game) # 发射前锁定四个实际种植格。
	if cells.is_empty():
		return
	var missile := MISSILE_SCENE.instantiate() as CannonTurretMissile # 与发射车寿命独立。
	var muzzle: Transform2D = _rig.fire() # 后坐前的世界发射位置和朝向。
	var axis: Vector2 = muzzle.basis_xform(CannonTurretPresentation.BARREL_AXIS).normalized() # 按炮管方向出膛。
	missile.configure(game, cells, _cell_pitch, muzzle.origin, axis, hp_component.outgoing_damage(missile_damage), self)
	game.bullets.add_child(missile)
	CannonTurretBurst.play(game, CannonTurretBurst.Kind.Launch, muzzle.origin, axis)


## 枚举 [param game] 棋盘中同平台的完整 2×2 方块，优先有植物并分散在途锁定。
## 返回四个格子的快照。洞口、断行和不足两行或两列的棋盘不会构造残缺目标。
func _pick_footprint(game: MainGameManager) -> Array[PlantCell]:
	var board: BoardRuntime = game.board # 当前战斗的合法地块与行拓扑。
	var planted: Array[Array] = [] # 至少一格被植物占用的方块。
	var vacant: Array[Array] = [] # 四格全空的备用候选。
	for origin: PlantCell in board.cells(): # 每个方块按起始逻辑地址只枚举一次。
		var address: Vector2i = origin.row_col # X 为逻辑行，Y 为逻辑列。
		var surface: StringName = origin.board_definition.surface_id # 独立运动的平台不能拼成方块。
		# 从同一起始地址取出双行双列对应的四个格子。
		var cells: Array[PlantCell] = [origin, board.cell_at(address + Vector2i(0, 1)),
			board.cell_at(address + Vector2i(1, 0)), board.cell_at(address + Vector2i(1, 1))]
		if not cells.all(func(cell: PlantCell) -> bool: # 当前候选必须仍完整且可见。
			return is_instance_valid(cell) and not cell.is_queued_for_deletion() \
				and cell.is_visible_in_tree() and cell.board_definition.surface_id == surface \
				and game.zombie_manager.is_lane_open(cell.combat_lane)):
			continue
		if cells.any(func(cell: PlantCell) -> bool: return not cell.living_plants().is_empty()):
			planted.append(cells)
		else:
			vacant.append(cells)
	var candidates: Array[Array] = planted if not planted.is_empty() else vacant # 有植物是第一优先级。
	if candidates.is_empty():
		return []
	var pressure: Dictionary[StringName, int] = {} # 每格当前被几枚在途弹体锁定。
	for bullet: Node in game.bullets.get_children(): # 沿用弹体所有权，拦截后的脱锁即时生效。
		if bullet is CannonTurretMissile:
			(bullet as CannonTurretMissile).collect_target_pressure(pressure)
	var choices: Array[Array] = [] # 优先级相同时保留重叠数最低的候选。
	var lowest: int = 2147483647 # 等到读取首个方块后再收紧阈值。
	for cells: Array in candidates: # 有多个相同最低重叠数的方块时随机抽样。
		var overlap: int = 0 # 重叠格受到的在途锁定次数之和。
		for cell: PlantCell in cells: # 使用稳定 ID，兼容运动中的平台。
			overlap += pressure.get(cell.cell_id, 0)
		if overlap < lowest:
			lowest = overlap
			choices.clear()
		if overlap == lowest:
			choices.append(cells)
	return choices.pick_random()


## 本体击毁时播放分段爆炸，停止射击并注销登记。已发射导弹仍由当前战局处置。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	set_physics_process(false)
	if character_init_type == E_CharacterInitType.IsNorm and not retiring_from_battle:
		var burst_id: int = _rig.play_death_blast(self) # 主爆保留原位置，炮弹仍自行结算。
		var death_visuals: Node = airship_death_presentation() # 底盘快照承接今后的部件爆点。
		if death_visuals != null:
			death_visuals.capture_body(self, 0.86, death_visuals.source_velocity(self), &"turret", burst_id)
	super()
	queue_free()


## 载具被爆炸击毁时沿用独立退场。
func _preserves_blast_death_animation() -> bool:
	return true
