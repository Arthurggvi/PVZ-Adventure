## 猎人雪球：沿用直线弹的碰撞与坡面阻挡，以现成抛物线运动瞄准真实受击区域。
extends BulletLinear000Base
class_name HunterSnowball

## 发射战场的弱引用；来源猎人死亡不会使已经飞出的雪球失效。
var _game_ref: WeakRef
## 发射时的空间身份；同场景重新装配棋盘后拒绝旧弹命中。
var _board: BoardRuntime
## 发射时的轮次，普通多轮关卡切换后失效。
var _round: int = -1
## 发射时的冒险阶段；普通关卡为 null，冒险续战通过资源身份区分。
var _phase: StagePhaseDefinition
## 出手时真实碰撞区域内的世界落点；不持有可能死亡、铲除或换格的植物引用。
var _aim_world: Vector2 = Vector2(INF, INF)

## [param displacement] 同时平移猎人的短弧和落点快照。
func translate_with_board(displacement: Vector2) -> void:
	super(displacement)
	_aim_world += displacement
	var flight := movement_component as HunterSnowballMovement # 本弹场景绑定短弧运动适配器。
	flight.translate_world_path(displacement)

## 仅在入树前绑定 [param game]；[param lane_id] 为攻击行，[param origin_world] 为世界出手位置。
## [param target] 只在本次调用内采样实际碰撞形状，返回是否得到合法落点；失败时调用方回收未入树实例。
func configure(game: MainGameManager, lane_id: int, origin_world: Vector2, target: Plant000Base) -> bool:
	if is_inside_tree() or not is_instance_valid(game) or game.board == null \
			or not is_instance_valid(game.bullets) or not origin_world.is_finite() \
			or lane_id < 0 or lane_id >= game.board.lanes.size() \
			or not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
			or target.lane != lane_id or not game.is_ancestor_of(target) \
			or not is_instance_valid(target.hurt_box_component) or not target.hurt_box_component.is_enabling \
			or (target.curr_be_attack_status & can_attack_plant_status) == 0:
		return false
	_aim_world = _hit_point(target.hurt_box_component.hurt_box_real)
	if not _aim_world.is_finite():
		return false
	_game_ref = weakref(game)
	_board = game.board
	_round = game.curr_game_round
	_phase = AdventureSession.get_active_phase(game.game_para)
	bullet_camp = CharacterRegistry.CharacterType.Zombie
	type_bullet_SFX = SoundManagerClass.TypeBulletSFX.Null
	init_bullet({
		E_InitParasAttr.BulletLane: lane_id,
		E_InitParasAttr.IsActivateLane: true,
		E_InitParasAttr.Position: game.bullets.to_local(origin_world),
		E_InitParasAttr.Direction: Vector2.LEFT,
	})
	return true

## 父类初始化世界射程原点；只为已绑定当前战场的弹体启动短弧，保留原线性碰撞入口。
func _ready() -> void:
	super()
	if not is_attack_active() or not _aim_world.is_finite():
		queue_free()
		return
	var flight: HunterSnowballMovement = movement_component as HunterSnowballMovement # 场景只替换本雪球的运动适配器。
	flight.start_flight(_aim_world)
	_update_shadow()

## [param delta] 由原直线弹消费，沿用其战场门禁、世界射程和命中回收；影子单独贴地。
func _physics_process(delta: float) -> void:
	super(delta)
	if not is_queued_for_deletion():
		_update_shadow()

## 只让影子采样本行地面；弹体和碰撞仍位于真实世界短弧，不投影到逻辑检测行。
func _update_shadow() -> void:
	var game: MainGameManager = _game_ref.get_ref() as MainGameManager # 调用前已经通过原战场有效性门禁。
	var ground_y: float = game.zombie_manager.all_zombie_rows[lane].zombie_create_position.global_position.y # 固定攻击行基准。
	if is_instance_valid(game.main_game_slope):
		ground_y += game.main_game_slope.get_all_slope_y(global_position.x)
	bullet_shadow.global_position.y = ground_y

## 返回 [param area] 的世界命中点，实心形状取内部，纯边界取边上；无有效几何时返回非有限值。
static func _hit_point(area: Area2D) -> Vector2:
	if not is_instance_valid(area):
		return Vector2(INF, INF)
	for child: Node in area.get_children(): # 采样实际形状的完整变换，包含坡高、承托偏移和缩放。
		if child is CollisionShape2D:
			var collider: CollisionShape2D = child as CollisionShape2D # 常规植物使用以原点为中心的胶囊或矩形。
			if collider.disabled or collider.shape == null:
				continue
			var center: Vector2 = collider.shape.get_rect().get_center() # 圆、矩形和胶囊的包围盒中心均位于内部。
			if collider.shape is ConvexPolygonShape2D:
				var points: PackedVector2Array = (collider.shape as ConvexPolygonShape2D).points # 凸形用顶点平均保证在内部。
				if points.size() < 3:
					continue
				center = Vector2.ZERO
				for point: Vector2 in points: # 不使用可能落在凸形之外的包围盒中心。
					center += point / float(points.size())
			elif collider.shape is ConcavePolygonShape2D:
				var segments: PackedVector2Array = (collider.shape as ConcavePolygonShape2D).segments # 线段形状没有填充区域，取实际碰撞边中点。
				if segments.size() < 2:
					continue
				center = (segments[0] + segments[1]) * 0.5
			return collider.to_global(center)
		if child is CollisionPolygon2D:
			var polygon: CollisionPolygon2D = child as CollisionPolygon2D # 凹多边形需取实际三角剖分内部点。
			if polygon.disabled or polygon.polygon.size() < 3:
				continue
			if polygon.build_mode == CollisionPolygon2D.BUILD_SEGMENTS:
				return polygon.to_global((polygon.polygon[0] + polygon.polygon[1]) * 0.5)
			var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon.polygon) # 空结果表示没有有效填充区域。
			if triangles.size() >= 3:
				return polygon.to_global((polygon.polygon[triangles[0]] + polygon.polygon[triangles[1]] \
					+ polygon.polygon[triangles[2]]) / 3.0)
	return Vector2(INF, INF)

## 返回弹体是否仍属于当前正式战斗的原棋盘、轮次和阶段；不读取发射者状态。
func is_attack_active() -> bool:
	if _game_ref == null:
		return false
	var game: MainGameManager = _game_ref.get_ref() as MainGameManager # 已释放战场不会被全局下一局替代。
	return is_instance_valid(game) and game == Global.main_game and game.is_inside_tree() \
		and not game.is_queued_for_deletion() and game.is_ancestor_of(self) \
		and _board != null and game.board == _board and game.curr_game_round == _round \
		and AdventureSession.get_active_phase(game.game_para) == _phase \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME and super()

## [param plant] 为碰撞到的植物；沿用南瓜、主体、伴生和承托物顺序选择本次实际受击者。
## 已有冰壳由植物入口拒绝刷新；无论能否新装冰壳，父类都消耗这次命中和弹体，不扣生命。
func _attack_plant(plant: Plant000Base) -> void:
	var target: Plant000Base = get_first_be_hit_plant_in_cell(plant) # 不能让碰撞顺序绕过同格保护层。
	if not is_attack_active() or not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
		return
	target.apply_hunter_ice_shell()
