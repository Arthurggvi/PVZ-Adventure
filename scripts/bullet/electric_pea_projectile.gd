## 电球沿真实世界轨迹穿透，独立按半秒节奏向附近敌人放电。
extends Node2D
class_name ElectricPeaProjectile

## 三种普通电球动画资源。
const EFFECTS: PackedScene = preload("res://scenes/character/plant/electric_peashooter_effects.tscn")
## 与出手等阶对应的共享电系换色接口。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 随实际速度方向绘制细尾、白芯及出生脉冲的独立表现。
const ProjectileVisual = preload("res://scripts/fx/electric_pea_projectile_visual.gd")
## 原版电球在坡面坐标内的飞行速率，单位为世界像素每秒。
const SPEED: float = 180.0
## 每次邻近放电之间的游戏秒数。
const BOLT_INTERVAL: float = 0.5
## 三种普通球的循环片段。
const PROJECTILE_CLIPS: Array[StringName] = [&"projectile", &"projectile2", &"projectile3"]

## 冻结战局、伤害与来源；须在入树前配置。
var shot: ElectricPeaShotContext
## 离手前设置的坡面相对方向；入树后固定，不吸附邻行或追随母株。
var flight_direction: Vector2 = Vector2.RIGHT
## 入树时冻结的坡面相对速度，单位为世界像素每秒；所有方向保持相同速率。
var velocity: Vector2 = Vector2.ZERO
## 最近物理帧的世界速度，包含屋顶高度变化，供弹体表现对齐真实运动。
var frame_velocity: Vector2 = Vector2.ZERO
## 仅离手时读取的原始地块，用于冻结枪口到地面中心的高度差。
var launch_origin: PlantCell
## 是否为分裂后代，决定尺寸、伤害及是否仍可分裂。
var is_child_ball: bool = false
## 放电的当前攻击行，随斜向飞行更新。
var _lane: int = -1
## 原始飞行坡面，母株移除不改变已经离手的轨迹。
var _slope: MainGameSlope
## 当前坡面相对高度，按固定二维速度推进，单位为世界像素。
var _level_y: float = 0.0
## 枪口到地格中心的固定高度差；后代继承，避免跨行定位受弹体离地高度影响。
var _lane_height_offset: float = 0.0
## 距下次放电的游戏秒数；首轮采用原版随机相位。
var _bolt_remaining: float = 0.0
## 每枚球的直击记录，独立于每轮放电目标。
var _contact_ids: Dictionary[int, bool] = {}
## 本颗球的实际承伤去重；多枚弹体各自允许独立伤害，保护者代伤同弹只结算一次。
var _hit_scope: CombatHitScope = CombatHitScope.new()
## 每枚球独立碰撞大小和连续碰撞查询器。
var _query: ElectricPeaFlightQuery
## 生存秒数限制永久追随弹体的镜头造成的泄漏。
var _elapsed: float = 0.0
## 跟随速度调整的寿命上界。
var _lifetime: float = 0.0
## 折算转职后的坡面相对飞行速率，单位为世界像素每秒。
var _speed: float = SPEED
## 小球仅乘一次比例，普通球保持离手伤害。
var _damage_multiplier: float = 1.0
## 跟随逻辑物理帧更新的方向性电球表现，暂停时保持静止。
var _flight_visual: ProjectileVisual


## 入树后建立独立表现和放电计时；无有效战局时直接释放。
func _ready() -> void:
	if shot == null or not shot.is_active():
		queue_free()
		return
	# 暂停时仍核对战场身份，换场立即清掉旧弹。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lane = shot.lane if _lane < 0 else _lane
	z_index = _lane * 50 + 45
	_slope = shot.game.main_game_slope
	_level_y = _height_above_slope(global_position)
	if is_instance_valid(launch_origin):
		_lane_height_offset = _height_above_slope(launch_origin.get_global_rect().get_center()) - _level_y
	launch_origin = null
	_speed = SPEED * shot.promotions.speed_multiplier
	velocity = flight_direction.normalized() * _speed
	frame_velocity = velocity
	_bolt_remaining = BOLT_INTERVAL if is_child_ball else randf_range(0.0, BOLT_INTERVAL)
	_lifetime = maxf(8.0 * SPEED, _screen_rect().size.x * 2.0) / _speed
	var size_multiplier: float = shot.promotions.split_size if is_child_ball else 1.0 # 小球缩小碰撞与美术。
	_damage_multiplier = shot.promotions.split_damage if is_child_ball else 1.0
	_query = ElectricPeaFlightQuery.new(size_multiplier)
	var visual: Node2D = EFFECTS.instantiate() as Node2D # 由逻辑根节点维持真实世界尺寸。
	visual.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(visual)
	visual.scale *= size_multiplier
	var clip: StringName = PROJECTILE_CLIPS.pick_random() # 保留原版三种球面循环，片段同时提供各自半径。
	PromotionArt.apply_to_projectile(visual, shot.appearance_rank, clip)
	var player: AnimationPlayer = visual.get_node(^"AnimationPlayer") as AnimationPlayer # 只播放普通电球片段。
	player.play(clip)
	_flight_visual = ProjectileVisual.new()
	_flight_visual.configure(shot.appearance_rank, is_child_ball, PromotionArt.projectile_radius(clip))
	_flight_visual.scale *= size_multiplier
	add_child(_flight_visual)
	_flight_visual.advance_visual(_elapsed, frame_velocity)
	if shot.matrix_damage > 0:
		ElectricPeaMatrix.register_ball(self)


## [param delta] 为游戏物理秒数，屋顶折线与斜向位移都纳入连续扫掠。
func _physics_process(delta: float) -> void:
	if shot == null or not shot.is_active():
		queue_free()
		return
	if get_tree().paused:
		return
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return
	var start: Vector2 = global_position # 本帧真实起点，用于恢复世界速度。
	var start_y: float = _level_y # 保存上一帧的坡面相对高度，不累积屋顶投影误差。
	var advance: Vector2 = velocity * delta # 正向、反向及竖向使用同一速率，不靠tan放大斜向速度。
	_level_y += advance.y
	var finish_x: float = start.x + advance.x # 不继承母株或移动平台的横向位移。
	var finish_y: float = _level_y # 坡面相对高度持续线性变化，经过邻行也不拐平。
	var finish := Vector2(finish_x, finish_y + ElectricPeaFlightQuery.height_at(_slope, finish_x)) # 世界终点。
	frame_velocity = (finish - start) / delta if delta > 0.0 else velocity
	var candidates := ElectricPeaFlightQuery.all_targets(shot.game) # 原始候选保留跳跃敌人。
	var points := ElectricPeaFlightQuery.path_points(start, finish, _slope, start_y, finish_y) # 正反向跨过坡面折点时逐段扫掠。
	for index: int in range(1, points.size()): # 命中回调结束战局或分裂时立即停止旧球。
		_move_segment(points[index], candidates)
		if is_queued_for_deletion() or not shot.is_active():
			queue_free()
			return
		if get_tree().paused:
			_level_y = _height_above_slope(global_position)
			return
	_flight_visual.advance_visual(_elapsed, frame_velocity)
	_bolt_remaining -= delta
	if _bolt_remaining <= 0.0:
		_bolt_remaining = BOLT_INTERVAL
		ElectricPeaBolt.discharge(shot, global_position, _lane, roundi(shot.bolt_damage * _damage_multiplier))
	var screen: Rect2 = _screen_rect().grow(ElectricPeaFlightQuery.HALF_SIZE) # 给球体边缘留下可见空间。
	if not screen.has_point(global_position):
		queue_free()


## 按弹体的真实地面投影更新攻击行；离板侧弹只选实际存在的最近行，不改变飞行方向。
func _refresh_lane() -> void:
	if not is_child_ball and is_zero_approx(velocity.y):
		return
	var ground: Vector2 = global_position + Vector2(0.0, _lane_height_offset) # 抵消枪口离地高度后再定位。
	_lane = ElectricPeaFlightQuery.nearest_lane(shot.board, ground, _slope, _lane)
	z_index = _lane * 50 + 45


## 沿当前位置至 [param finish] 搜索 [param candidates]，先结算最近的真实接触。
func _move_segment(finish: Vector2, candidates: Array[Character000Base]) -> void:
	var start: Vector2 = global_position # 固定本段起点，按比例还原实际撞击位置。
	var contacts: Array[Dictionary] = [] # 先排序，碰撞顺序独立于场景树顺序。
	for reference: Variant in candidates: # 前一坡段的命中可能已经释放候选。
		if not is_instance_valid(reference) or not ElectricPeaFlightQuery.can_hit(reference):
			continue
		var target: Character000Base = reference # 已通过当前实例与攻击状态检查。
		if _contact_ids.has(target.get_instance_id()) or (target is EnemyStructureBase \
				and is_zero_approx(velocity.y) and not is_child_ball and target.lane != _lane):
			continue
		var fraction: float = _query.contact_fraction(target.hurt_box_component.hurt_box_real, start, finish) # 连出生重叠一起检查。
		if is_finite(fraction):
			contacts.append({"target": target, "fraction": fraction})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction)) # a、b 为两次待结算接触。
	var splitting: bool = not is_child_ball and shot.promotions.split_count > 0 # 后代始终继续穿透。
	for contact: Dictionary in contacts: # 每次攻击后重查战局与下一个目标。
		if not shot.is_active() or get_tree().paused:
			return
		var target: Variant = contact.target # 弱引用经受击回调可能已经失效。
		if not is_instance_valid(target) or not ElectricPeaFlightQuery.can_hit(target):
			continue
		var target_id: int = target.get_instance_id() # 即使后续死亡仍能屏蔽子球出生碰撞。
		_contact_ids[target_id] = true
		global_position = start.lerp(finish, float(contact.fraction))
		_refresh_lane()
		var kind := ElectricPeaShotContext.HitKind.SPLIT if splitting else ElectricPeaShotContext.HitKind.CONTACT # 只有母球首次合法接触可触发分裂，后代不再递归。
		shot.hit(target, roundi(shot.contact_damage * _damage_multiplier), kind, _hit_scope)
		if splitting:
			if shot.is_active():
				# 接触与分裂作为同一事件完成；若受击回调暂停，后代留在命中点等待恢复。
				_split(target_id)
			queue_free()
			return
		if not shot.is_active() or get_tree().paused:
			return
	global_position = finish
	_refresh_lane()


## 在撞击点向整圈分层散射；[param parent_target_id] 标记小球出生时必须绕过的母命中目标。
func _split(parent_target_id: int) -> void:
	var count: int = shot.promotions.split_count # 各子球随机占据不同扇区，避免重合方向。
	var segment: float = TAU / count # 等分整圈；三颗子球的基准方向彼此相隔120度。
	var phase: float = randf_range(0.0, TAU) # 每次分裂整体旋转，避免固定向右的偏向。
	var jitter: float = minf(segment * 0.1, deg_to_rad(12.0)) # 有限抖动保证三颗不会全部挤入同一半圆。
	for index: int in range(count): # 各子球从同一个命中点离手并独立放电。
		var child: ElectricPeaProjectile = get_script().new() # 同一弹体实现，后代不再分裂。
		child.shot = shot
		child.is_child_ball = true
		child._lane = _lane
		child._lane_height_offset = _lane_height_offset
		child._contact_ids[parent_target_id] = true
		child.flight_direction = Vector2.from_angle(phase + float(index) * segment + randf_range(-jitter, jitter))
		child.position = get_parent().to_local(global_position)
		get_parent().add_child(child)


## 将 [param point] 换算为扣除当前坡面的世界高度。
func _height_above_slope(point: Vector2) -> float:
	return point.y - ElectricPeaFlightQuery.height_at(_slope, point.x)


## 返回当前镜头的世界可见矩形，兼容平移和缩放。
func _screen_rect() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()
