## 闪电芦苇的索敌和电击结算。每次放电独立记录命中和折射层数。
extends RefCounted

## 本次放电找到首击目标时，通知植株播放放电音效。
signal discharged()
## 电弧实际命中时通知植株播放表现，首击和折射使用不同贴图。
signal struck(game: MainGameManager, origin: Vector2, impact: Vector2, first_hit: bool)

## 首击的基础伤害，出战星级、光环和其他攻击修正在每层结算时计算。
const BASE_DAMAGE: int = 10
## 普通放电的最大折射层数，首击不计在内。
const MAX_BOUNCES: int = 3
## 两层电弧之间的间隔，单位为游戏秒。
const BOUNCE_DELAY: float = 0.1


## 命中后仅保留位置和身份编号，目标死亡或释放也能从其落点继续折射。
class Impact:
	## 电弧的世界坐标，首段使用植株发射点。
	var position: Vector2
	## 对应的战场行号，供附近索敌使用。
	var lane: int
	## 被直接命中的实例 ID，发射点使用 0。
	var target_id: int
	## 此落点是否来自对僵尸或僵王的命中，决定是否产生溅射。
	var is_zombie: bool

	## 记录落点 [param at]、行 [param row]、目标 [param id] 和溅射资格 [param zombie]。
	func _init(at: Vector2, row: int, id: int = 0, zombie: bool = false) -> void:
		position = at
		lane = row
		target_id = id
		is_zombie = zombie


## 一次放电的所有分支共用命中记录，层数相同的电弧在同一物理帧结算。
class Discharge:
	## 下一层的发射点，取自上一层的实际命中。
	var impacts: Array[Impact] = []
	## 已经直击的目标实例 ID，跨分支去重。
	var visited: Dictionary[int, bool] = {}
	## 下一层的折射次数；0 为从植株发出的首击。
	var hop: int = 0
	## 距下一层结算的游戏秒数，二连发的第二次放电也在这里等待。
	var remaining: float = 0.0


## 当前出战植株，离场后中止尚未结算的攻击。
var _plant: Plant000Base
## 每次放电重新读取的首段发射点。
var _bolt_origin: Marker2D
## 正在推进的放电，二连发和加速后重叠的攻击各有独立状态。
var _active: Array[Discharge] = []
## 二连发的额外放电间隔，0 表示只放电一次。
var _followup_delay: float = 0.0
## 每次折射增加的基础伤害倍率。
var _overload_step: float = 0.0
## 每道闪电累计的额外伤害倍率上限。
var _overload_cap: float = 0.0
## 溅射相对于本次直击的伤害倍率。
var _splash_fraction: float = 0.0
## 溅射半径的平方，单位为平方像素。
var _splash_radius_squared: float = 0.0
## 每次直击施加的眩晕秒数，0 表示没有控制效果。
var _stun_duration: float = 0.0
## 每次放电从植株同时发出的电弧数。
var _initial_targets: int = 1
## 全屏首击与空中目标开关。
var _warp: bool = false
## 每个落点可以向下一层发出的电弧数。
var _branches: int = 1
## 每道闪电的折射深度，分裂共享这一限制。
var _max_bounces: int = MAX_BOUNCES


## [param plant] 持有本对象。[param bolt_origin] 是植株上的首段发射点。
func _init(plant: Plant000Base, bolt_origin: Marker2D) -> void:
	_plant = plant
	_bolt_origin = bolt_origin


## 初始化时读取一次已验证出战快照的 [param events]，之后每帧使用该实例的技能参数。
func configure(events: Array[Dictionary]) -> void:
	# 每条事件来自该独立植物卡已选择的一个转职分支。
	for event: Dictionary in events:
		match event.kind:
			"reed_quick_burst":
				_followup_delay = float(event.delay)
			"reed_overload":
				_overload_step = float(event.step)
				_overload_cap = float(event.cap)
			"reed_splash":
				_splash_fraction = float(event.fraction)
				_splash_radius_squared = float(event.radius) * float(event.radius)
			"reed_paralysis":
				_stun_duration = float(event.seconds)
			"reed_dual_strike":
				_initial_targets = int(event.targets)
			"reed_warp":
				_warp = true
			"reed_split":
				_branches = int(event.branches)
			"reed_ion_refraction":
				_max_bounces = MAX_BOUNCES + int(event.extra_bounces)


## 检查 [param game] 仍是植株所在且正在出战的关卡。
func can_fight(game: MainGameManager) -> bool:
	return is_instance_valid(_plant) and not _plant.is_death and not _plant.is_queued_for_deletion() \
		and _plant.is_inside_tree() and _plant.can_process() and is_instance_valid(game) \
		and not game.is_queued_for_deletion() and game.is_ancestor_of(_plant) \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME


## 返回 [param game] 中是否有能让植株起手的首击目标。
func has_target(game: MainGameManager) -> bool:
	return _nearest_target(game, game.detect_component_global.get_all_enemy_can_be_attacked(),
		_plant.global_position, _plant.lane, true, {}) != null


## 在 [param game] 立即开始首轮放电，二连发的第二轮会重新索敌。
func release(game: MainGameManager) -> void:
	# 首次放电在原动作帧直接结算，其后只保留仍可折射的状态。
	var shot := Discharge.new()
	if _strike_wave(game, shot):
		shot.remaining = BOUNCE_DELAY
		_active.append(shot)
	if _followup_delay > 0.0 and can_fight(game):
		# 追射不沿用第一轮的落点、命中记录或折射次数。
		var followup := Discharge.new()
		followup.remaining = _followup_delay
		_active.append(followup)


## 在 [param game] 按 [param delta] 游戏秒推进已发出的电弧。
## 尚未发出的追射使用 [param action_speed] 换算时间，倍率为 0 时暂停。
func advance(game: MainGameManager, delta: float, action_speed: float) -> void:
	if not can_fight(game):
		_active.clear()
		return
	# 倒序遍历可直接移除已结束的放电，不影响仍在推进的其他放电。
	for index: int in range(_active.size() - 1, -1, -1):
		# 每次放电只推进一层，低帧率时也不把全部电弧压到同一帧。
		var shot: Discharge = _active[index]
		# 只有还未从植株发出的放电需要遵守植株当前的动作速度。
		var waiting_for_release: bool = shot.hop == 0
		shot.remaining -= delta * maxf(0.0, action_speed) if waiting_for_release else delta
		if shot.remaining > 0.0:
			continue
		if _strike_wave(game, shot):
			shot.remaining = BOUNCE_DELAY if waiting_for_release else shot.remaining + BOUNCE_DELAY
		else:
			_active.remove_at(index)


## 在 [param game] 结算 [param shot] 的一层电弧。仍有可继续折射的落点时返回 true。
func _strike_wave(game: MainGameManager, shot: Discharge) -> bool:
	if not can_fight(game):
		return false
	# 候选只在本层使用，跨帧折射时重新读取战场目标。
	var candidates: Array[Character000Base] = game.detect_component_global.get_all_enemy_can_be_attacked()
	# 首击使用植株发射点和三行或全屏的索敌规则，后续从各落点寻找邻近目标。
	var first_hit: bool = shot.hop == 0
	var sources: Array[Impact] = shot.impacts
	var bolts_per_source: int = _branches
	if first_hit:
		sources = [Impact.new(_bolt_origin.global_position, _plant.lane)]
		bolts_per_source = _initial_targets
	shot.impacts = []
	# 先计算折射加成，再经过星级、光环和通用攻击修正，只结算一次。
	var damage_factor: float = 1.0 + minf(_overload_step * shot.hop, _overload_cap)
	var damage: int = _plant.battle_damage(roundi(float(BASE_DAMAGE) * damage_factor))
	# 每个上一层落点分别发出下一段电弧。
	for source: Impact in sources:
		# 同一落点发出的每道闪电各取一个未命中的目标。
		for _bolt: int in range(bolts_per_source):
			if not can_fight(game):
				return false
			# 首击朝向以种植原点判断，折射距离则以实际命中点判断。
			var search_origin: Vector2 = _plant.global_position if first_hit else source.position
			var target: Character000Base = _nearest_target(game, candidates,
				search_origin, source.lane, first_hit, shot.visited)
			if target == null:
				break
			# 扣血前记录落点，致死一击仍可溅射并成为下一层的起点。
			var position: Vector2 = _target_position(target)
			var impact := Impact.new(position, _target_lane(game, target, position),
				target.get_instance_id(), target is Zombie000Base or target is ZB000Base)
			if first_hit and shot.impacts.is_empty():
				discharged.emit()
			shot.visited[impact.target_id] = true
			shot.impacts.append(impact)
			struck.emit(game, source.position, impact.position, first_hit)
			target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Real, true, false)
			if _stun_duration > 0.0 and is_instance_valid(target):
				AdventurePlantNegativeEffects.apply(target, AdventurePlantNegativeEffects.Kind.STUN,
					0, _stun_duration)
	if _splash_fraction > 0.0:
		# 先完成同层直击，再处理溅射，避免激荡提前杀死电压击穿的另一目标。
		var splash_damage: int = roundi(float(damage) * _splash_fraction)
		if splash_damage > 0:
			# 只有直击僵尸的落点触发激荡，设施和溅射本身不会产生新电弧。
			for impact: Impact in shot.impacts:
				if impact.is_zombie and can_fight(game):
					_splash(candidates, impact, splash_damage)
	shot.hop += 1
	return not shot.impacts.is_empty() and shot.hop <= _max_bounces


## [param candidates] 为同层候选。对 [param impact] 范围内的其他敌人结算 [param damage]。
func _splash(candidates: Array[Character000Base], impact: Impact, damage: int) -> void:
	# 只处理仍可受击的敌人，跳过触发本次溅射的直接目标。
	for target: Character000Base in candidates:
		if not is_instance_valid(target) or not _can_hit(target) or target.get_instance_id() == impact.target_id:
			continue
		if _target_position(target).distance_squared_to(impact.position) <= _splash_radius_squared:
			target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Real, true, false)


## [param game] 提供场地行；在 [param candidates] 中选择最接近 [param origin] 和 [param origin_lane] 的敌人。
## [param first_hit] 决定使用首击或折射范围。[param visited] 已命中的目标会被跳过。
func _nearest_target(game: MainGameManager, candidates: Array[Character000Base], origin: Vector2,
		origin_lane: int, first_hit: bool, visited: Dictionary[int, bool]) -> Character000Base:
	# 最近的有效候选和其网格距离的平方。
	var nearest: Character000Base = null
	var nearest_distance: float = INF
	# 跃迁扩大首击范围，折射仍以相邻一格为限。
	var full_field: bool = first_hit and _warp
	# 检查受击状态及本次放电的命中记录，找出距离最小的可用目标。
	for target: Character000Base in candidates:
		if not is_instance_valid(target) or not _can_hit(target) or visited.has(target.get_instance_id()):
			continue
		# 横向使用受击点，纵向使用地面行，避免屋顶坡度或飞行高度影响排序。
		var target_position: Vector2 = _target_position(target)
		var target_lane: int = _target_lane(game, target, target_position)
		var row_offset: int = target_lane - origin_lane
		var offset_x: float = target_position.x - origin.x
		if target_lane < 0 or (not full_field and absi(row_offset) > 1):
			continue
		if (first_hit and not full_field and offset_x < 0.0) \
				or (not first_hit and absf(offset_x) > _plant.plant_cell.size.x):
			continue
		# 用与原版相同的格高把行差换算为像素。
		var distance: float = Vector2(offset_x, row_offset * _plant.plant_cell.size.y).length_squared()
		if distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	return nearest


## 返回已通过实例有效性检查的 [param target] 当前是否可受击。
func _can_hit(target: Character000Base) -> bool:
	if target.is_death or target.is_hypno or target.is_queued_for_deletion() or not target.is_inside_tree() \
			or not is_instance_valid(target.hurt_box_component) or not target.hurt_box_component.is_enabling:
		return false
	if target is Zombie000Base:
		# 全局检测也会提供气球等空中目标，跃迁才允许电弧命中它们。
		var allowed: int = Zombie000Base.E_BeAttackStatusZombie.IsNorm
		if _warp:
			allowed |= Zombie000Base.E_BeAttackStatusZombie.IsSky
		return (target.curr_be_attack_status & allowed) != 0
	return target is ZB000Base or target is EnemyStructureBase


## [param target] 的电弧落点取实际受击形状的世界坐标。
func _target_position(target: Character000Base) -> Vector2:
	# 缺少具名碰撞形状时，使用实际受击区域的原点。
	var area: Area2D = target.hurt_box_component.hurt_box_real
	var shape: Node2D = area.get_node_or_null(^"CollisionShape2D") as Node2D
	return shape.global_position if shape != null else area.global_position


## 优先读取 [param target] 的登记行。无固定行的僵王在 [param game] 中按受击点 [param point] 推断。
func _target_lane(game: MainGameManager, target: Character000Base, point: Vector2) -> int:
	if target.lane >= 0 or not target is ZB000Base:
		return target.lane
	# 当前最接近的格子行号和距离平方；没有格子时返回 -1。
	var nearest: int = -1
	var distance: float = INF
	# 使用实际场地格子推断僵王落点所在的行，兼容屋顶与不同的行数。
	for row: Array in game.plant_cell_manager.all_plant_cells:
		for cell: PlantCell in row:
			# 格子底部中心抬高半格，接近僵尸的受击中心。
			var next_distance: float = (cell.global_position + cell.size * 0.5).distance_squared_to(point)
			if next_distance < distance:
				distance = next_distance
				nearest = cell.row_col.x
	return nearest
