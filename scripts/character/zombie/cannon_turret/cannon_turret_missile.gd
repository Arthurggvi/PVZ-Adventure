## 可被原生对空子弹命中的空中弹体，由战场子弹层管理。
extends Zombie000Base
class_name CannonTurretMissile

## 飞过一格的战斗时间，横纵距离分别按棋盘格距换算。
const SECONDS_PER_CELL: float = 4.0
## 出膛时精灵距投影脚点的高度，单位为世界像素。
const LIFT: float = 94.0
## 炮口短暂爬升的高度，随后回落到稳定巡航高度。
const CLIMB: float = 16.0
## 让炮弹完整脱膛再进入大幅转向，单位为战斗秒。
const CLEAR_MUZZLE_SECONDS: float = 0.62
## 进入末段时离落点的最大距离，单位为格。
const DESCENT_CELLS: float = 0.57
## 极近距离直接收敛的半径，大于转向半径，避免绕着落点打转。
const FINAL_CAPTURE_CELLS: float = 0.14
## 偏离目标时平滑收拢航向，单位为弧度/战斗秒。
const TURN_RATE: float = 2.85
## 弹体销毁后保留的排烟时间，由最长一粒尾烟决定。
const TRAIL_FADE_SECONDS: float = 0.93
## 真实受击框的位置修正，与香蒲的默认追踪终点偏移对应。
const TRACK_AIM_OFFSET: float = 40.0
## 登记弹体素材中的弹头朝向，旋转时扣除素材自身的角度。
const ART_HEADING := Vector2(-0.94908, -0.31503)
## 与战场受击高度同步的弹体精灵。
@onready var _sprite: Sprite2D = $Body/Missile
## 对空检测使用地面投影高度，真实受击区保持在导弹附近。
@onready var _detection: Area2D = $HurtBoxComponent/HurtBoxDetection
## 显示锁定四格及当前落点阶段。
@onready var _warning: CannonTurretWarning = $GroundWarning
## 由弹体实际画面朝向驱动的尾焰挂点。
@onready var _exhaust: Node2D = $Exhaust
## 已散出的烟团停在世界中，随飞行推进逐渐消失。
@onready var _trail: GPUParticles2D = $Exhaust/Smoke
## 推进中的短火舌，落地和空爆时立即熄灭。
@onready var _thrust: Sprite2D = $Exhaust/Thrust
## 发射时接纳弹体的战场。
var _game: MainGameManager
## 发射时锁定的棋盘，换场清除旧导弹。
var _board: BoardRuntime
## 发射时的场景轮次。
var _round: int
## 发射时的冒险阶段，旧关卡为空。
var _phase: StagePhaseDefinition
## 始终跟踪这四个格子，落地时读取其中的植物。
var _footprint: Array[PlantCell] = []
## 横竖移动一格对应的世界像素数。
var _pitch: Vector2
## 炮口的真实朝向，用于确保第一帧与炮管姿态一致。
var _launch_axis: Vector2
## 平面航向，按棋盘横纵格距归一后的角度。
var _heading: float
## 发射后累积的战斗秒数，控制爬升和开舵。
var _age: float = 0.0
## 弹体当前距投影脚点的高度，单位为像素。
var _height: float = LIFT
## 进入末段时记录与落点的距离，零表示巡航。
var _descent_start: float = 0.0
## 进入末段时的飞行高度，沿俯冲进度连续下降。
var _descent_height: float
## 发射瞬间确定的落地爆炸伤害。
var _damage: int
## 导弹伤害的真实发射者，节点寿命与导弹相互独立。
var _launcher: Character000Base


## 发射前绑定 [param game]、实际命中 [param cells]、棋盘格距 [param pitch] 和炮口 [param origin]。
## [param axis] 为炮口真实世界方向，[param damage] 为发射时锁定的伤害，[param launcher] 为伤害来源。
func configure(game: MainGameManager, cells: Array[PlantCell], pitch: Vector2, origin: Vector2,
		axis: Vector2, damage: int, launcher: Character000Base = null) -> void:
	_game = game
	_launcher = launcher
	_board = game.board
	_round = game.curr_game_round
	_phase = AdventureSession.get_active_phase(game.game_para)
	_footprint = cells
	_pitch = pitch
	_damage = damage
	_launch_axis = axis
	_heading = (axis / pitch).angle()
	var ground: Vector2 = origin + Vector2(0.0, LIFT) # 与炮口重合的初始视觉位置对应的地面投影。
	position = game.bullets.to_local(ground)
	lane = _lane_at_ground(ground, _terrain_height(ground.x))


## 初始化耐久、索敌和表现，由子弹层管理飞行和退出的生命周期。
func _ready() -> void:
	if _game == null:
		queue_free()
		return
	curr_be_attack_status = init_be_attack_status
	hp_component.signal_hp_component_death.connect(character_death)
	var target: Vector2 = _target_center() # 入场后读当前场景的四格位置。
	_warning.lock_cells(_footprint, target)
	_sprite.global_rotation = _launch_axis.angle() - ART_HEADING.angle()
	_update_pose(target, Vector2.ZERO, 0.0, 0.0, _terrain_height(global_position.x))
	if is_instance_valid(_game.world_wind):
		const BattleWind := preload("res://scripts/battle/environment/battle_wind_visual.gd") # 复用世界坐标尾焰。
		BattleWind.setup_particles(_trail, _game.world_wind.wind_for_visual(_exhaust.global_position), 0.64)
	_trail.emitting = true


## 将仍在飞行的锁定格累加到 [param counts]，供后续炮塔在同等优先目标中分散落点。
func collect_target_pressure(counts: Dictionary[StringName, int]) -> void:
	if is_death or is_queued_for_deletion():
		return
	for cell: PlantCell in _footprint: # 轮替与坍塌时可能已经失效。
		if is_instance_valid(cell):
			counts[cell.cell_id] = counts.get(cell.cell_id, 0) + 1


## 导弹的空中位移仅由锁定格驱动，避免跳跃、梯子或吹风接管轨迹。
func is_native_airborne() -> bool:
	return true


## 导弹耐久接受正常伤害，行动控制和独立负面状态不改变其追踪。
func can_receive_negative_effects() -> bool:
	return false


## 消费三叶草对弹体的位移请求。[param _cells] 为格数，[param _flying] 为风力分类。
func handle_blover_wind(_cells: int, _flying: bool) -> bool:
	return true


## [param delta] 为本次物理帧的战斗秒数。命中时准确停在四格中心。
func _physics_process(delta: float) -> void:
	if is_death:
		return
	if not _battle_is_active() or not _footprint_is_active():
		queue_free()
		return
	_age += delta
	var target: Vector2 = _target_center() # 平台可能在发射后移动。
	var remaining: Vector2 = (target - global_position) / _pitch # 归一为沿两个轴经过的格数。
	var distance: float = remaining.length() # 当前帧与落点相距的格数。
	var step: float = delta / SECONDS_PER_CELL # 本帧恰好能飞行的格数。
	var separation: float = smoothstep(0.10, CLEAR_MUZZLE_SECONDS, _age) # 出膛过程逐步放开转向。
	var correction: float = TURN_RATE * lerpf(1.65, 1.0, smoothstep(0.22, 1.40, distance)) # 近处提高跟踪响应。
	_heading = rotate_toward(_heading, remaining.angle(), correction * separation * delta)
	if _descent_start > 0.0 and distance > _descent_start + 0.26:
		# 仍锁定原四格。平台明显移开时回到带转向的巡航。
		_descent_start = 0.0
	var lined_up: bool = distance <= FINAL_CAPTURE_CELLS or absf(angle_difference(_heading, remaining.angle())) <= 0.24 # 极近时直接收敛，画面继续平滑转向。
	if _descent_start == 0.0 and separation >= 1.0 and distance <= DESCENT_CELLS and lined_up:
		_descent_start = maxf(distance, step)
		_descent_height = _height
	var descending: bool = _descent_start > 0.0 # 末段直达脚点，避免在目标旁绕圈。
	if descending and distance <= step:
		global_position = target
		_warning.track(target, 1.0)
		_detonate(true)
		return
	var offset: Vector2 = remaining.limit_length(step) if descending else Vector2.from_angle(_heading) * step # 保持棋盘速度。
	var advance: Vector2 = offset * _pitch # 恢复为世界像素位移。
	if descending:
		_heading = offset.angle()
	global_position += advance
	var terrain_height: float = _terrain_height(global_position.x) # 同步检测和投影行的屋顶坡度修正。
	var projected_lane: int = _lane_at_ground(global_position, terrain_height) # 仙人掌按当前投影行索敌。
	if projected_lane != lane:
		lane = projected_lane
		signal_lane_update.emit()
	var approach: float = clampf(1.0 - (remaining - offset).length() / _descent_start, 0.0, 1.0) if descending else 0.0 # 落点预警与俯冲共用进度。
	var hover: float = LIFT + CLIMB * (smoothstep(0.0, 0.30, _age) - 0.76 * smoothstep(0.43, 1.32, _age)) # 起步抬高后自然回落。
	var next_height: float = _descent_height * (1.0 - pow(approach, 1.52)) if descending else move_toward(_height, hover, 128.0 * delta) # 回到巡航时连续抬起。
	var image_motion: Vector2 = advance + Vector2(0.0, _height - next_height) # 弹头根据画面切线抬起或压低。
	_height = next_height
	_update_pose(target, image_motion, delta, approach, terrain_height)
	if is_instance_valid(_game.world_wind):
		_game.world_wind.update_projectile_audio(get_instance_id(), _exhaust.global_position, _height)


## [param target] 为地面落点。[param motion] 为图像位移，[param delta] 为场景时间。
## [param approach] 是俯冲进度，预警和余焰随同一时间推进。
## [param terrain_height] 是地面相对基准行的坡度偏移，仅用于对空检测区域。
func _update_pose(target: Vector2, motion: Vector2, delta: float, approach: float, terrain_height: float) -> void:
	_warning.track(target, approach)
	_sprite.position.y = -_height
	if not motion.is_zero_approx():
		_sprite.global_rotation = rotate_toward(_sprite.global_rotation, motion.angle() - ART_HEADING.angle(), delta * 7.25)
	var aft: float = _sprite.global_rotation + ART_HEADING.angle() + PI # 尾焰沿弹体实际姿态朝后。
	_exhaust.global_position = _sprite.global_position + Vector2.from_angle(aft) * 14.0
	_exhaust.global_rotation = aft
	_thrust.scale.x = (0.31 + 0.045 * sin(_age * 36.0)) * lerpf(1.22, 0.72, approach)
	_trail.amount_ratio = lerpf(1.0, 0.61, approach)
	hurt_box_component.position.y = -_height + TRACK_AIM_OFFSET
	_detection.position.y = -25.0 - hurt_box_component.position.y - terrain_height
	hp_component.position.y = -_height - 25.0


## [param world_x] 为当前世界横坐标，返回该处相对平地的坡度偏移。
func _terrain_height(world_x: float) -> float:
	var slope: MainGameSlope = _game.main_game_slope # 平地没有独立的坡面节点。
	return slope.get_all_slope_y(world_x) if is_instance_valid(slope) else 0.0


## [param ground] 的世界投影减去 [param terrain_height] 后映射到固定攻击行。
func _lane_at_ground(ground: Vector2, terrain_height: float) -> int:
	return _board.lane_at_foot_y(_game.to_local(ground - Vector2(0.0, terrain_height)).y)


## 四个格子的当前世界中心，适用于反序旧棋盘及平移的平台。
func _target_center() -> Vector2:
	var center := Vector2.ZERO # 累加四个格子的世界中心。
	for cell: PlantCell in _footprint: # 在飞行中只读取本次申请的四格。
		center += cell.get_global_transform() * (cell.size * 0.5)
	return center / 4.0


## 当前战局失效时丢弃在途弹体，防止旧导弹打到下一轮。
func _battle_is_active() -> bool:
	return AdventureZombieTierAbility.battle_context_active(_game, _round, _phase) and _game.board == _board


## 校验完整锁定范围，变化后的实际植物占用在落地时读取。
func _footprint_is_active() -> bool:
	for cell: PlantCell in _footprint: # 移除或替换任一地块后，四格中心已失效。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree() \
				or _board.cell_by_id(cell.cell_id) != cell or not _game.zombie_manager.is_lane_open(cell.combat_lane):
			return false
	return true


## 耐久归零时在当前空中坐标引爆。
func character_death() -> void:
	_detonate(false)


## 保留导弹自身的空爆表现。
func _preserves_blast_death_animation() -> bool:
	return true


## [param landed] 为 true 时抵达原锁定位置，空爆使用弹体世界位置。
func _detonate(landed: bool) -> void:
	if is_death or is_queued_for_deletion():
		return
	var center: Vector2 = global_position if landed else _sprite.global_position # 捕获屏幕爆心。
	if is_instance_valid(_game) and is_instance_valid(_game.world_wind):
		_game.world_wind.stop_projectile_audio(get_instance_id())
	super.character_death()
	body.hide()
	hp_component.hide()
	_trail.emitting = false
	_thrust.hide()
	_warning.release(landed)
	set_physics_process(false)
	# 对空碰撞可能在物理回调内结算，此时延后添加爆炸节点。
	_finish_impact.call_deferred(landed, center)


## [param landed] 决定是否结算四格伤害，[param center] 是引爆时保存的世界爆心。
func _finish_impact(landed: bool, center: Vector2) -> void:
	if not _battle_is_active():
		queue_free()
		return
	if landed and _footprint_is_active():
		var areas: Array[Area2D] = [] # 只从锁定格的有效植株收集真实受击区。
		for cell: PlantCell in _footprint: # 兼容保护壳、承托和多格植物。
			for plant: Plant000Base in cell.living_plants(): # 通用爆炸结算会对同一植物去重。
				areas.append(plant.hurt_box_component.hurt_box_real)
		var launcher: Character000Base = _launcher if is_instance_valid(_launcher) else null # 退场炮车不接收反伤。
		CombatExplosion.resolve_targets(areas, get_instance_id(), lane, -1, false, _damage, false, false, launcher)
	CannonTurretBurst.play(_game, CannonTurretBurst.Kind.Ground if landed else CannonTurretBurst.Kind.Air, center)
	var fade: Tween = create_tween() # 留足烟和地面提示的消散时间。
	fade.tween_interval(TRAIL_FADE_SECONDS)
	fade.tween_callback(queue_free)
