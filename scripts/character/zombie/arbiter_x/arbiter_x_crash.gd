## 仲裁者的拖烟俯冲、擦地、爆炸与残骸演出，沿同一条世界轨迹衔接。
extends Node2D
class_name ArbiterXCrash

## 首次真实触地，传递机头触点 [param world]、原 [param airframe] 和世界 [param velocity]。
signal first_touchdown(world: Vector2, airframe: Node2D, velocity: Vector2)

## 素材包的 60 Hz 俯仰和双喷口功率值轨，位移按实际巡航速度与场地高度计算。
const DIVE: Animation = preload("res://assets/adventure/zombies/arbiter_x/dive.tres")
## 擦地开始时实例化，同一节点继续承接火光、冲击波和尘烟。
const IMPACT_SCENE: PackedScene = preload("res://scenes/character/zombie/arbiter_x/arbiter_x_impact.tscn")
## 从真实战斗归属取得花园飞艇爆炸能力。
const VehicleDeathBlast := preload("res://scripts/character/zombie/vehicle_death_blast.gd")
## 计算实际机舱和翼片所在的世界画布深度。
const DeathPose := preload("res://scripts/adventure/garden_airship/garden_airship_death_pose.gd")
## 从交接到撞地的场景时间，单位为秒。
const GLIDE_SECONDS: float = 2.32
## 整段滑降逐渐增加的水平速度上限，单位为世界像素/秒。
const GLIDE_SPEED_GAIN: float = 24.0
## 巡航悬浮和俯仰与下沉姿态交接的时间，单位为秒。
const COAST_SECONDS: float = 0.38
## 去除地基后，俯冲末帧由机头下沿接触地面。坐标相对机体纹理轴心。
const CONTACT_POINT: Vector2 = Vector2(-180.0, 70.0)
## 擦滑回弹时，机腹前段下缘会滚到接地位置。
const SKID_SUPPORT: Vector2 = Vector2(-108.0, 106.0)
## 机翼脱落后，机舱最低处用作残骸的支撑点。
const BELLY_SUPPORT: Vector2 = Vector2(-2.0, 142.0)
## 原擦滑局部动作和普通战场爆炸之间的场景秒数。
const SKID_SECONDS: float = 0.36
## 花园飞艇真实接地至活动机舱起爆的秒数；扫离仍在首触当帧开始。
const AIRSHIP_BURST_AT: float = 0.15
## 爆炸后保留焦化残骸的场景秒数。
const WRECK_SECONDS: float = 2.23

## 只跟随地面接触线，从擦地持续到残骸消散。
@onready var _shadow: Sprite2D = $WreckShadow

## 从本体接管的原机体，包括当时的尾雾和警报相位。
var _airframe: ArbiterXAirframe
## 被击毁瞬间的完整世界姿态，保留悬浮与转身。
var _start_pose: Transform2D
## 被击毁前的世界横向速度，单位为像素/秒。
var _speed_x: float
## 滑降末段沿原方向增加的有符号横速，单位为世界像素/秒。
var _speed_gain_x: float
## 切换时机身相对巡航脚点的悬浮惯性，单位为世界像素/秒。
var _hover_velocity: Vector2
## 从巡航继承的尾焰相位，单位为动画秒。
var _flight_seconds: float
## 当时的双喷口功率，熄火曲线始于此值。
var _initial_power: Vector2
## 当时的告警强度，滑降时逐步加重。
var _initial_pressure: float
## 俯冲开始后累计的场景秒数，擦地和爆炸沿用同一时间线。
var _elapsed: float = 0.0
## 按接触点真实棋盘高度计算的世界落差。
var _ground_drop: float
## 屋顶战场的地面采样器，平地不需要。
var _slope: MainGameSlope
## 俯冲在第一个触地点的完整机体变换。
var _touch_pose: Transform2D
## 从触地到制动停止的有符号水平路程，单位为世界像素。
var _skid_distance: float
## 首次接地的世界位置。
var _touch_point: Vector2
## 擦滑结束、火球开始的最终接触点。
var _stop_point: Vector2
## 爆炸前最后一帧机壳的变换，给残骸接续俯仰。
var _stop_pose: Transform2D
## 擦地与爆炸共用的粒子和声场，可能因战场特效额度跳过。
var _impact: ArbiterXImpact
## 亦用于防止外部重复触发首次接地时重播原擦滑。
var _touched_down: bool = false
## 以接地为界的无碰撞扫离表现，其他战场不提供该服务。
var _death_visuals: Node
## 接地前的原父坐标，仅用于已脱离机身的局部痕迹与裂解动作。
var _contact_parent_inverse: Transform2D
## 原始擦滑轨迹的当前姿态，用于局部动作和普通战场的触地效果。
var _ground_pose: Transform2D
## 实际成功接管才隐藏地面机身阴影。
var _sweeping: bool = false
## 活动扫离代理，回收时不再在其机体上触发主爆。
var _sweep_anchor: Node2D
## 花园飞艇当局爆炸演出的唯一入口。
var _blast_director: Node
## 锁定交接时选择的演出路径，避免服务退出后补播旧地面爆炸。
var _uses_airship_blast: bool = false
## 移动机舱爆炸和翼片解体只启动一次。
var _body_burst_started: bool = false
## 上一拍的机舱世界爆点，用于继承实际移动速度。
var _prior_body_origin: Vector2


## 接管 [param airframe] 并从 [param ground] 延伸终端轨迹。
## [param speed_x] 和 [param hover_velocity] 分别为世界横速与悬浮惯性，单位为像素/秒。
## [param phase] 和 [param tint] 延续尾焰与机体彩色修正。
## [param death_visuals] 只在真实地面接触时获准接管绘制。
func start(airframe: ArbiterXAirframe, ground: Vector2, speed_x: float, hover_velocity: Vector2,
		phase: float, tint: Color, death_visuals: Node = null) -> void:
	_death_visuals = death_visuals
	_blast_director = VehicleDeathBlast.find_airship(self)
	_uses_airship_blast = is_instance_valid(_blast_director)
	global_position = ground
	_airframe = airframe
	_start_pose = airframe.global_transform
	_speed_x = speed_x
	_hover_velocity = hover_velocity
	var direction: float = signf(speed_x) if not is_zero_approx(speed_x) else -signf(_start_pose.x.x) # 静止时沿机头方向滑降。
	_speed_gain_x = direction * GLIDE_SPEED_GAIN
	_flight_seconds = phase
	_initial_power = Vector2(airframe.far_exhaust.self_modulate.a, airframe.near_exhaust.self_modulate.a)
	_initial_pressure = airframe.damage_pressure
	_airframe.handoff_to_glide(self, tint)
	var final_angle: float = DIVE.value_track_interpolate(1, DIVE.length) # 相对巡航姿态的终点俯角。
	var contact: Vector2 = _start_pose.basis_xform(CONTACT_POINT.rotated(final_angle)) # 终态轴心到机头的世界偏移。
	var landing_x: float = _start_pose.origin.x + _horizontal_offset(GLIDE_SECONDS) + contact.x # 坡面查询使用实际机头落点。
	var ground_y: float = ground.y # 平地沿用角色所属行脚点。
	var game: MainGameManager = Global.main_game # 独立展示时允许没有主战场。
	if is_instance_valid(game) and game.is_ancestor_of(self) and is_instance_valid(game.main_game_slope):
		if game.main_game_slope.sample_walking_height:
			_slope = game.main_game_slope
	ground_y += _height_change(ground.x, landing_x)
	_ground_drop = ground_y - _start_pose.origin.y - contact.y
	_skid_distance = (_speed_x + _speed_gain_x) * SKID_SECONDS * 0.5


## [param delta] 推进连续的俯冲、擦滑和爆炸，跨过阶段边界也各触发一次。
func _process(delta: float) -> void:
	var previous: float = _elapsed # 上一拍时间用于判定跨过的阶段。
	_elapsed += delta
	if previous < GLIDE_SECONDS:
		_apply_sample(minf(delta, GLIDE_SECONDS - previous))
		if _elapsed < GLIDE_SECONDS:
			return
		_begin_touchdown()

	var ground_time: float = _elapsed - GLIDE_SECONDS # 从首次触地开始的场景秒数。
	if previous < GLIDE_SECONDS + SKID_SECONDS:
		_pose_skid(clampf(ground_time / SKID_SECONDS, 0.0, 1.0))
		if ground_time < SKID_SECONDS:
			if _uses_airship_blast:
				_pose_airship_breakup(ground_time, delta, 1.0)
			return
		_burst()

	var after_blast: float = ground_time - SKID_SECONDS # 擦滑结束后的场景秒数。
	_pose_wreck(after_blast, delta)
	if after_blast >= WRECK_SECONDS:
		if _sweeping and is_instance_valid(_airframe):
			_airframe.queue_free()
		queue_free()


## 先把姿态推进到这一帧，再沿刚经过的喷口路径密集补烟。[param delta] 为实际帧长。
func _apply_sample(delta: float) -> void:
	var seconds: float = minf(_elapsed, GLIDE_SECONDS) # 保留精确的终点姿态。
	var progress: float = seconds / GLIDE_SECONDS # 归一化的真实俯冲秒数。
	var path_time: float = DIVE.length * progress # 动画姿态均匀采样，避免在末段突然加快。
	var angle: float = DIVE.value_track_interpolate(1, path_time) # 俯冲弧度。
	var power: Vector2 = DIVE.value_track_interpolate(2, path_time) # 两个喷口先后熄火。
	var coast: float = smoothstep(0.0, COAST_SECONDS, seconds) # 将原悬浮惯性平滑收束到滑降姿态。
	var descent: float = progress * progress * (2.0 - progress) # 从水平切入下沉，末段保留触地速度。
	var offset: Vector2 = Vector2(_horizontal_offset(seconds), _ground_drop * descent) # 世界水平和垂直位移。
	offset += _hover_velocity * seconds * (1.0 - coast)
	var shudder: float = sin(seconds * 28.0) * sin(PI * progress) * (1.0 - progress) * 0.09 # 故障抖动在触地前收束。
	var pose: Transform2D = _start_pose * Transform2D(angle * coast + shudder, Vector2.ZERO) # 叠加姿态时保留原缩放和朝向。
	pose.origin += offset
	_airframe.global_transform = pose
	_airframe.pose_exhaust(_flight_seconds + seconds, _initial_power * power)
	var pressure: float = lerpf(_initial_pressure, 1.0, smoothstep(0.0, 0.72, seconds)) # 先细烟，再连续拖出两股浓烟。
	_airframe.advance_fault(delta, pressure)
	_airframe.shape_rush(smoothstep(0.0, 1.0, progress))


## [param seconds] 为滑降时间。对平滑增速曲线积分，返回从巡航位置走过的世界横向距离。
func _horizontal_offset(seconds: float) -> float:
	var progress: float = seconds / GLIDE_SECONDS # 0–1 内，对应速度从巡航横速变为目标横速。
	var ramp: float = progress * progress * (1.0 - 0.5 * progress) # 速度增量的累计位移系数。
	return seconds * (_speed_x + _speed_gain_x * ramp)


## 从机体的真实触点开始拖出火星。旧烟仍由机壳的世界尾迹节点消散。
func _begin_touchdown() -> void:
	if _touched_down:
		return
	_touched_down = true
	_touch_pose = _airframe.global_transform
	_touch_point = _airframe.to_global(CONTACT_POINT)
	_airframe.begin_ground_contact()
	_shadow.show()
	if not _uses_airship_blast:
		_begin_legacy_scrape()
	var velocity := Vector2(_speed_x + _speed_gain_x, _ground_drop / GLIDE_SECONDS) # 原滑降曲线在真实接地时的导数。
	first_touchdown.emit(_touch_point, _airframe, velocity)
	if is_instance_valid(_death_visuals) and is_instance_valid(_airframe):
		_contact_parent_inverse = global_transform.affine_inverse()
		_airframe.retain_contact_effects(self)
		_sweep_anchor = _death_visuals.sweep_visual(_airframe, 1.0, velocity, &"arbiter", _touch_point)
		_sweeping = _sweep_anchor != null
		if _sweeping:
			_shadow.hide()
	if _uses_airship_blast:
		set_deferred(&"process_priority", 1) # 从下一拍起先推进扫离，首触帧仍沿用原来的处理顺序。
	if is_instance_valid(_blast_director):
		_prior_body_origin = _touch_pose * ArbiterXAirframe.CABIN_BURST_POINT
		var layer_source: Node2D = _airframe if is_instance_valid(_airframe) else self # 首触信号可能已结束机体的生命周期。
		_blast_director.contact(_touch_point, velocity, _touch_pose.x.length(),
			DeathPose.absolute_z(layer_source) + 2)


## 普通战场仍由原擦滑粒子和声场承接爆炸。
func _begin_legacy_scrape() -> void:
	var game: MainGameManager = Global.main_game # 正式战场共享特效额度。
	var budget: BattleBlastFxBudget = game.blast_fx_budget \
		if is_instance_valid(game) and game.is_ancestor_of(self) else null # 独立展示不使用战斗额度。
	var kind: StringName = &"arbiter_x_impact" # 擦滑与后续火球使用同一个演出名额。
	if budget == null or budget.can_start(kind, _touch_point):
		_impact = IMPACT_SCENE.instantiate() as ArbiterXImpact
		var row: CanvasItem = get_parent() as CanvasItem # 演出在机身熄灭后仍继续燃烧。
		_impact.position = row.get_global_transform().affine_inverse() * _touch_point
		_impact.z_index = z_index + 2
		row.add_child(_impact)
		_impact.begin_scrape(signf(_skid_distance))
		if budget != null:
			budget.track(_impact, kind, _touch_point)


## [param progress] 为擦滑进度；水平速度逐渐减至零，机头压下再短暂回弹。
func _pose_skid(progress: float) -> void:
	var center_x: float = _touch_pose.origin.x + _skid_distance * progress * (2.0 - progress) # 机身轴心以触地横速开始减速。
	var rebound: float = smoothstep(0.0, 1.0, progress) # 回弹缓入，避免触地时的突然转动。
	var pitch: float = deg_to_rad(-6.0 * sin(PI * rebound) + 6.0 * rebound) # 着地时先低头，再回到中间姿态。
	var squash: float = 1.0 - 0.10 * sin(PI * rebound) - 0.06 * rebound # 机体在受压时略微下沉。
	var pose: Transform2D = _touch_pose * Transform2D(pitch, Vector2.ZERO) # 回弹只转动机身，不将轴心拉离擦滑路径。
	var floor_x: float = center_x + pose.basis_xform(CONTACT_POINT).x # 火星沿当前机头触点移动。
	_stop_point = Vector2(floor_x, _touch_point.y + _height_change(_touch_point.x, floor_x))
	_set_grounded_pose(pose, _stop_point, squash, 0.0)
	if is_instance_valid(_airframe) and not _body_burst_started:
		_airframe.pose_scrape(progress)
	if is_instance_valid(_impact):
		_impact.global_position = _stop_point
	_update_shadow(_stop_point.y, 0.24 + 0.16 * progress)


## 保存擦滑末端的局部姿态，并在采用原爆炸演出时拆开机壳。
func _burst() -> void:
	_stop_pose = _ground_pose
	if not _uses_airship_blast and is_instance_valid(_airframe):
		_airframe.break_apart()
	if is_instance_valid(_impact):
		_impact.burst()


## [param seconds] 为擦滑结束后的场景秒数，[param delta] 用于估算活动机舱的世界速度。
func _pose_wreck(seconds: float, delta: float) -> void:
	var settle: float = smoothstep(0.0, 0.61, seconds) # 爆炸冲击卸去后，残骸进一步向地面塌落。
	var squash: float = lerpf(1.0, 0.76, settle) # 随机翼分离而压扁机身。
	var pitch: float = deg_to_rad(13.0 * settle - 5.0 * sin(PI * settle)) # 回弹到较平的机身姿势。
	_set_grounded_pose(_stop_pose * Transform2D(pitch, Vector2.ZERO), _stop_point, squash, settle)
	var opacity: float = 1.0 - smoothstep(1.27, WRECK_SECONDS, seconds) # 主烟散去后仍能看到焦黑残骸。
	if _uses_airship_blast:
		_pose_airship_breakup(seconds + SKID_SECONDS, delta, opacity)
	else:
		var hot_light: float = ArbiterXImpact.reflected_heat(seconds) if is_instance_valid(_impact) else 0.0 # 同步原爆光。
		if is_instance_valid(_airframe):
			_airframe.pose_wreck(seconds, hot_light, opacity)
		if is_instance_valid(_impact):
			if _sweeping:
				_impact.fire_followups(seconds, null, _original_followup_origin.bind(seconds))
			else:
				_impact.fire_followups(seconds, _airframe)
	_update_shadow(_stop_point.y, 0.4 * opacity)


## [param ground_time] 从真实首触计时，[param delta] 为本次采样秒数。
## 首次起爆交出活动的翼片锚点，之后仅推进机体解体姿态及 [param opacity]。
func _pose_airship_breakup(ground_time: float, delta: float, opacity: float) -> void:
	if not is_instance_valid(_airframe) or not _airframe.is_inside_tree() or _airframe.is_queued_for_deletion():
		return
	if _sweeping and (not is_instance_valid(_sweep_anchor) or _sweep_anchor.is_queued_for_deletion()):
		return
	var seconds: float = ground_time - AIRSHIP_BURST_AT # 结构解体相对于提前的主爆计时。
	if not _body_burst_started:
		var origin: Vector2 = _airframe.to_global(ArbiterXAirframe.CABIN_BURST_POINT) # 活动机舱的实际世界位置。
		var velocity: Vector2 = (origin - _prior_body_origin) / maxf(delta, 0.001) # 包含扫离与局部擦滑动作。
		_prior_body_origin = origin
		if seconds < 0.0:
			return
		_body_burst_started = true
		_airframe.break_apart()
		if is_instance_valid(_blast_director):
			var body_scale: float = _airframe.global_transform.x.length() # 包含原机体的世界缩放。
			var depth: int = DeathPose.absolute_z(_airframe) + 2 # 火光在实际机身绘制层上方。
			var burst_id: int = _blast_director.start_burst(&"arbiter", origin, body_scale, velocity, depth) # 主爆只申请一次额度。
			if burst_id > 0:
				var points := PackedVector2Array([ArbiterXAirframe.FAR_WING_PIVOT,
					ArbiterXAirframe.NEAR_WING_PIVOT, ArbiterXAirframe.CABIN_BURST_POINT]) # 每个点使用所属翼片或机舱的坐标。
				_blast_director.track_burst(burst_id, _airframe, points, _airframe.wreck_burst_pieces())
	_airframe.pose_wreck(seconds, ArbiterXImpact.flash_at(seconds), opacity)


## [param index] 和 [param seconds] 为未配置新爆炸演出的原擦滑路径提供余爆点。
func _original_followup_origin(index: int, seconds: float) -> Vector2:
	return _ground_pose * ArbiterXAirframe.wreck_burst_offset(index, seconds)


## 把 [param pose] 固定在 [param floor_point]。 [param squash] 是纵向压缩倍率。
## [param settle] 从整机翼缘的支撑转向机舱底部，保持轮廓贴地。
func _set_grounded_pose(pose: Transform2D, floor_point: Vector2, squash: float, settle: float) -> void:
	pose.x.y *= squash
	pose.y.y *= squash
	var nose: Vector2 = pose.basis_xform(CONTACT_POINT) # 横向定位沿用真实触点。
	var height_fin: float = maxf(nose.y, pose.basis_xform(SKID_SUPPORT).y) # 整机擦滑时贴合机腹最低处。
	var height_body: float = maxf(nose.y, pose.basis_xform(BELLY_SUPPORT).y) # 折断后由机舱接触地面。
	pose.origin = floor_point - Vector2(nose.x, lerpf(height_fin, height_body, settle))
	_ground_pose = pose
	if is_instance_valid(_airframe):
		if _sweeping:
			_airframe.transform = _contact_parent_inverse * pose
		else:
			_airframe.global_transform = pose


## 返回 [param from_x] 滑到 [param to_x] 时的棋盘高差。
func _height_change(from_x: float, to_x: float) -> float:
	if is_instance_valid(_slope):
		return _slope.get_all_slope_y(to_x) - _slope.get_all_slope_y(from_x)
	return 0.0


## [param floor_y] 为当地板面高度，[param opacity] 为机身下接触阴影的透明度。
func _update_shadow(floor_y: float, opacity: float) -> void:
	if _sweeping:
		return
	_shadow.global_position = Vector2(_ground_pose.origin.x, floor_y + 2.0)
	_shadow.modulate.a = opacity
