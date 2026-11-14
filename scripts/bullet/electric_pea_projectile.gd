## 电球沿真实世界轨迹穿透，独立按半秒节奏向附近敌人放电。
extends Node2D
class_name ElectricPeaProjectile

## 三种普通电球动画资源。
const EFFECTS: PackedScene = preload("res://scenes/character/plant/electric_peashooter_effects.tscn")
## 与出手等阶对应的共享电系换色接口。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 原版电球水平速度，单位为世界像素每秒。
const SPEED: float = 180.0
## 每次邻近放电之间的游戏秒数。
const BOLT_INTERVAL: float = 0.5
## 三种普通球的循环片段。
const PROJECTILE_CLIPS: Array[StringName] = [&"projectile", &"projectile2", &"projectile3"]

## 冻结战局、伤害与来源；须在入树前配置。
var shot: ElectricPeaShotContext
## 扩散射击的实际相邻地块及发射地块；仅扩散侧弹使用。
var spread_destination: PlantCell
## 扩散方向取 -1、0、1；缺少邻格时只保留实际射线方向。
var spread_direction: int = 0
## 发射地块，与相邻地块共同提供当前行距。
var spread_origin: PlantCell
## 分裂小球的坡面相对斜率，无量纲；普通球为零。
var split_gradient: float = 0.0
## 是否为分裂后代，决定尺寸、伤害及是否仍可分裂。
var is_child_ball: bool = false
## 放电的当前攻击行，随斜向飞行更新。
var _lane: int = -1
## 原始飞行坡面，母株移除不改变已经离手的轨迹。
var _slope: MainGameSlope
## 离手时的坡面相对高度，单位为世界像素。
var _level_y: float = 0.0
## 斜射到达邻行时的坡面相对位移，单位为世界像素。
var _spread_offset: float = 0.0
## 从起点累计向前飞行的世界像素。
var _distance: float = 0.0
## 距下次放电的游戏秒数；首轮采用原版随机相位。
var _bolt_remaining: float = 0.0
## 每枚球的直击记录，独立于每轮放电目标。
var _contact_ids: Dictionary[int, bool] = {}
## 每枚球独立碰撞大小和连续碰撞查询器。
var _query: ElectricPeaFlightQuery
## 生存秒数限制永久追随弹体的镜头造成的泄漏。
var _elapsed: float = 0.0
## 跟随速度调整的寿命上界。
var _lifetime: float = 0.0
## 折算转职后的水平速度，单位为世界像素每秒。
var _speed: float = SPEED
## 小球仅乘一次比例，普通球保持离手伤害。
var _damage_multiplier: float = 1.0


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
	_speed = SPEED * shot.promotions.speed_multiplier
	_bolt_remaining = BOLT_INTERVAL if is_child_ball else randf_range(0.0, BOLT_INTERVAL)
	_lifetime = maxf(8.0 * SPEED, _screen_rect().size.x * 2.0) / _speed
	var size_multiplier: float = shot.promotions.split_size if is_child_ball else 1.0 # 小球缩小碰撞与美术。
	_damage_multiplier = shot.promotions.split_damage if is_child_ball else 1.0
	_query = ElectricPeaFlightQuery.new(size_multiplier)
	var visual: Node2D = EFFECTS.instantiate() as Node2D # 由逻辑根节点维持真实世界尺寸。
	visual.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(visual)
	visual.scale *= size_multiplier
	PromotionArt.apply_to_effect(visual, shot.appearance_rank)
	var player: AnimationPlayer = visual.get_node(^"AnimationPlayer") as AnimationPlayer # 只播放普通电球片段。
	player.play(PROJECTILE_CLIPS.pick_random())
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
	var start_y: float = _height_above_slope(global_position) # 本帧实际起点，包含上帧的坡面高度。
	var advance: float = _speed * delta # 横向世界位移。
	_distance += advance
	var finish_x: float = global_position.x + advance # 不继承母株或移动平台的横向位移。
	var finish_y: float = _trajectory_y() # 扣除坡面的目标高度。
	var finish := Vector2(finish_x, finish_y + ElectricPeaFlightQuery.height_at(_slope, finish_x)) # 世界终点。
	var candidates := ElectricPeaFlightQuery.all_targets(shot.game) # 原始候选保留跳跃敌人。
	var points := ElectricPeaFlightQuery.path_points(global_position, finish, _slope, start_y, finish_y) # 跨过坡面折点时逐段扫掠。
	for index: int in range(1, points.size()): # 命中回调结束战局或分裂时立即停止旧球。
		_move_segment(points[index], candidates)
		if is_queued_for_deletion() or not shot.is_active():
			queue_free()
			return
	_bolt_remaining -= delta
	if _bolt_remaining <= 0.0:
		_bolt_remaining = BOLT_INTERVAL
		ElectricPeaBolt.discharge(shot, global_position, _lane, roundi(shot.bolt_damage * _damage_multiplier))
	var screen: Rect2 = _screen_rect().grow(ElectricPeaFlightQuery.HALF_SIZE) # 给球体边缘留下可见空间。
	if not screen.has_point(global_position):
		queue_free()


## 返回累计横向位移决定的坡面相对高度，并随相邻地块几何更新扩散行。
func _trajectory_y() -> float:
	if spread_direction != 0:
		if not is_instance_valid(spread_origin) or not is_instance_valid(spread_destination):
			# 棋盘边界仍按当前格距向外散射；放电行保留已知真实行。
			return _level_y + spread_direction * shot.cell_pitch.y * _spread_progress()
		var start: Vector2 = spread_origin.get_global_rect().get_center() # 平台当前位置下的发射地块中心。
		var finish: Vector2 = spread_destination.get_global_rect().get_center() # 同一平台上的目标行地块中心。
		_spread_offset = _height_above_slope(finish) - _height_above_slope(start)
		var progress: float = _spread_progress() # 同口离手，逐步到达相邻行。
		_lane = spread_destination.row_col.x if progress >= 0.5 else shot.lane
		z_index = _lane * 50 + 45
		return _level_y + _spread_offset * progress
	if is_child_ball:
		var ground: PlantCell = shot.board.nearest_cell(global_position) # 小球斜向移动时，放电跟随当前位置附近的行。
		if is_instance_valid(ground):
			_lane = ground.row_col.x
			z_index = _lane * 50 + 45
	return _level_y + _distance * split_gradient


## 返回侧弹已走过的发散距离比例，抵达邻行后沿该行继续飞行。
func _spread_progress() -> float:
	return clampf(_distance / (shot.promotions.spread_cells * shot.cell_pitch.x), 0.0, 1.0)


## 沿当前位置至 [param finish] 搜索 [param candidates]，先结算最近的真实接触。
func _move_segment(finish: Vector2, candidates: Array[Character000Base]) -> void:
	var start: Vector2 = global_position # 固定本段起点，按比例还原实际撞击位置。
	var contacts: Array[Dictionary] = [] # 先排序，碰撞顺序独立于场景树顺序。
	for reference: Variant in candidates: # 前一坡段的命中可能已经释放候选。
		if not is_instance_valid(reference) or not ElectricPeaFlightQuery.can_hit(reference):
			continue
		var target: Character000Base = reference # 已通过当前实例与攻击状态检查。
		if _contact_ids.has(target.get_instance_id()) or (target is EnemyStructureBase 				and spread_direction == 0 and not is_child_ball and target.lane != _lane):
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
		var kind := ElectricPeaShotContext.HitKind.SPLIT if splitting else ElectricPeaShotContext.HitKind.CONTACT # 只有母球首个实伤分裂。
		if shot.hit(target, roundi(shot.contact_damage * _damage_multiplier), kind, shot.contact_scope) > 0 and splitting:
			if shot.is_active() and not get_tree().paused:
				_split(target_id)
			queue_free()
			return
	global_position = finish


## 在撞击点向前分裂；[param parent_target_id] 标记小球出生时必须绕过的目标。
func _split(parent_target_id: int) -> void:
	var count: int = shot.promotions.split_count # 各子球随机占据不同扇区，避免重合方向。
	var segment: float = deg_to_rad(54.0) / count # 前向扇面的单个随机扇区宽度。
	for index: int in range(count): # 各子球从同一个命中点离手并独立放电。
		var child: ElectricPeaProjectile = get_script().new() # 同一弹体实现，后代不再分裂。
		child.shot = shot
		child.is_child_ball = true
		child._lane = _lane
		child._contact_ids[parent_target_id] = true
		child.split_gradient = tan((float(index) - (count - 1) * 0.5 + randf_range(-0.35, 0.35)) * segment)
		child.position = get_parent().to_local(global_position)
		get_parent().add_child(child)


## 将 [param point] 换算为扣除当前坡面的世界高度。
func _height_above_slope(point: Vector2) -> float:
	return point.y - ElectricPeaFlightQuery.height_at(_slope, point.x)


## 返回当前镜头的世界可见矩形，兼容平移和缩放。
func _screen_rect() -> Rect2:
	return get_canvas_transform().affine_inverse() * get_viewport_rect()
