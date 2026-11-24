## 原生齐射与转职共享当前攻击行。额外发数由同一时钟排开，不创建等待协程。
extends AttackComponentBulletBase
class_name AttackComponentBulletThreePea

## 并入同路的相邻豌豆出生间距，单位为世界像素。
const MERGED_PEA_SPACING: float = 18.0
## 普通齐射补发间隔与高能脉冲间隔，单位为游戏秒。
const PEA_INTERVAL: float = 0.080
const LASER_INTERVAL: float = 0.20
## 裁出棋盘外余量，保留临近进场的敌人。
const OFFBOARD_MARGIN: float = 72.0
## 延迟加载独立弹型，不将战斗贴图纳入启动入口。
const LASER_SCENE: String = "res://scenes/bullet/bullet_three_pea_laser.tscn"
const KINETIC_SCENE: String = "res://scenes/bullet/bullet_three_pea_kinetic.tscn"
## 命中规则由单株冻结，已离手的攻击与火炬升级都保留这份规则。
const ImpactRules = preload("res://scripts/bullet/three_pea_impact_rules.gd")
## 三路光束保持同一配色体系，在近白芯下仍有微小差别。
const LANE_TINTS := [Color(0.16, 1.0, 0.67), Color(0.51, 1.0, 0.42), Color(0.19, 0.88, 1.0)]

## 绑定在三个动画口型内的高能炮口，按画面从上到下对应逻辑攻击行。
@export var laser_muzzles: Array[Marker2D] = []

## 高能和动能源自合法冻结路径。
var laser_enabled: bool = false
var kinetic_enabled: bool = false
## 终结的末发倍率上限；零表示按普通发数结算。
var finisher_cap: int = 0

## 已点火的齐射冻结战局与出膛伤害，不持有已退场的母株。
var _shot: RepeaterShotContext
## 已离手的弹体持有此闭包，清空齐射时间表也不丢失跨阶段门禁。
var _shot_guard: Callable
## 已选择的实体弹场景，后续批次直接复用。
var _pea_scene: PackedScene
## 可贯穿的脉冲场景，首次出膛才加载。
var _laser_scene: PackedScene
## 普通豌豆的待发轮数；每轮每条逻辑路径一发。
var _pea_rounds: int = 0
## 激光各逻辑路径剩余的脉冲次数，边路多余发数先并回本行。
var _laser_rounds := PackedInt32Array([0, 0, 0])
## 当前齐射内的剩余延时和固定间隔。
var _next_pulse: float = 0.0
var _pulse_interval: float = 0.0
## 单株的催折计数由此对象共享；非命中类分支保持空值。
var _impact_rules: ImpactRules
## 此次齐射冻结方向和战局的命中回调。
var _shot_impact: Callable
## 记录此次齐射各实际攻击行已发射的弹量，从上至下。
var _fired_in_lane := Vector3i.ZERO

## 保留跨行索敌，子弹按实际选中的攻击行命中。
func _ready() -> void:
	super()
	is_lane = true
	set_physics_process(false)

## 从 [param rule] 读取一次真实的命中型转职配置。
func configure_impact(rule: Dictionary) -> void:
	if _impact_rules == null:
		_impact_rules = ImpactRules.new()
	_impact_rules.configure(rule)

## 原版动画刻点开始第一次齐射；只有实际拥有多发时才启动物理时间表。
func _shoot_bullet() -> void:
	var game: MainGameManager = Global.main_game # 核对动画仍属于当前战场。
	if not _can_fire(game):
		return
	var count: int = owner.shots_per_ray() # 洪流、陷阵及边路均从各路径的真实配额出发。
	if not laser_enabled and not kinetic_enabled and count == 1 and _impact_rules == null and finisher_cap == 0:
		_fire_peas(game, false)
		play_throw_sfx()
		return
	_shot = RepeaterShotContext.from_plant(owner)
	if _shot == null:
		return
	var frozen: RepeaterShotContext = _shot # 闭包持有快照，原株退场后弹体仍能检查本战局。
	_shot_guard = func() -> bool: return frozen.is_active()
	_fired_in_lane = Vector3i.ZERO
	if _impact_rules != null:
		var rules: ImpactRules = _impact_rules # 闭包保留连击状态直到已离手的弹体自然收尾。
		var direction_x: float = -1.0 if _direction(1).x < 0.0 else 1.0 # 以出膛方向背离来源击退。
		_shot_impact = func(target: Character000Base, first: bool, armor: bool) -> void:
			rules.apply(target, first, armor, frozen, direction_x)
	if laser_enabled:
		if _laser_scene == null:
			_laser_scene = load(LASER_SCENE) as PackedScene
		_laser_rounds.fill(count)
	else:
		_pea_rounds = count
	var raw_interval: float = LASER_INTERVAL if laser_enabled else PEA_INTERVAL # 标准攻速下保持清晰的明暗和弹间距。
	var possible_rounds: int = count * 3 if laser_enabled else count # 极窄棋盘可能把三路全折返。
	var rate: float = maxf(0.1, owner.speed_factor_product()) # 攻速变快后让整轮仍能在下一次动画前完成。
	_pulse_interval = minf(raw_interval, (attack_cd / rate) * 0.84 / maxi(1, possible_rounds - 1))
	_next_pulse = _pulse_interval
	if not laser_enabled:
		play_throw_sfx() # 整串实弹用一次出膛声，避免十二轮重叠占用音轨。
	_fire_pulse()
	if _has_pending():
		set_physics_process(true)
	else:
		_clear_pending()

## 一次待发序列是否还有额外批次。
func _has_pending() -> bool:
	return _pea_rounds > 0 or _laser_rounds[0] > 0 or _laser_rounds[1] > 0 or _laser_rounds[2] > 0

## 清掉尚未出膛的攻击；实体弹已有独立战局快照。
func _clear_pending() -> void:
	_pea_rounds = 0
	_laser_rounds.fill(0)
	_shot = null
	_shot_guard = Callable()
	_shot_impact = Callable()
	set_physics_process(false)

## 推进 [param delta]；倍速下可在同一帧补齐到期批次，循环上界由单轮发数决定。
func _physics_process(delta: float) -> void:
	if _shot == null or not _shot.is_active() or not _can_fire(_shot.game) or owner.lane != _shot.lane:
		_clear_pending()
		return
	_next_pulse -= delta
	while _next_pulse <= 0.0 and _has_pending():
		_next_pulse += _pulse_interval
		_fire_pulse()
		if not _shot.is_active() or not _can_fire(_shot.game):
			break
	if not _has_pending() or not _shot.is_active():
		_clear_pending()

## [param game] 必须是仍活动的当前战场；冻结或离开攻击行会停止后续出膛。
func _can_fire(game: MainGameManager) -> bool:
	return is_instance_valid(game) and game.is_ancestor_of(self) and is_instance_valid(bullets) \
		and is_instance_valid(owner) and not owner.is_death and not owner.is_queued_for_deletion() \
		and not owner.is_cold_frozen() and owner.action_rate() > 0.0 and not owner.is_sleeping \
		and game.zombie_manager.is_lane_open(owner.lane)

## 从已冻结配额发出一批；本行合流的激光依次放出，每发独立命中整行。
func _fire_pulse() -> void:
	if laser_enabled:
		_fire_lasers(_shot.game)
		var origin: Vector2 = markers_2d_bullet[0].global_position if not markers_2d_bullet.is_empty() else owner.global_position # 合流发射的可见弹口。
		SoundManager.play_threepeater_laser_SFX(self, origin)
	else:
		_pea_rounds -= 1
		_fire_peas(_shot.game, true)

## 返回 [param ray] 当前的实际攻击方向，缺少配置时回退到水平向右。
func _direction(ray: int) -> Vector2:
	var directions: Array[Vector2] = detect_component.ray_area_direction # 保留原有三轴朝向。
	return directions[mini(ray, directions.size() - 1)] if not directions.is_empty() else Vector2.RIGHT

## [param game] 的三路豌豆或动能弹共用入行与合流。[param enhanced] 为真时装入本轮来源及剪裁范围。
func _fire_peas(game: MainGameManager, enhanced: bool) -> void:
	var manager: ZombieManager = game.zombie_manager # 原生真实行状态。
	var lane: int = owner.lane # 读出当前炮口所在行。
	var rows: Array[ZombieRow] = manager.all_zombie_rows # 行高由关卡装配。
	var muzzle: Vector2 = markers_2d_bullet[0].global_position # 三路原生炮口。
	var source_y: float = rows[lane].zombie_create_position.global_position.y # 跨行相对高度基准。
	if _pea_scene == null:
		_pea_scene = load(KINETIC_SCENE) as PackedScene if kinetic_enabled else Global.bullet_registry.get_bullet_scenes(attack_bullet_type)
	var merged: int = 0 # 窄棋盘两个外侧方向都可以并回本路。
	var view: Rect2 = BloomerangFlightQuery.screen_rect(self) if enhanced else Rect2() # 每批只读取一次视口位置。
	var fold_top: bool = not manager.is_lane_open(lane - 1) # 缺失或关闭的上邻行并到本行。
	var fold_bottom: bool = not manager.is_lane_open(lane + 1) # 缺失或关闭的下邻行同理。
	var merge_splats: bool = enhanced and not kinetic_enabled and attack_bullet_type == BulletRegistry.BulletType.Bullet001Pea \
		and owner.shots_per_ray() > 1 # 密集实弹共用目标的原生溅射反馈。
	var finisher: bool = enhanced and finisher_cap > 0 # 每次只在确实选了终结时维护计数。
	var boosts: Vector3i = _finish_multipliers(fold_top, fold_bottom) if finisher else Vector3i.ONE # 针对实际末发。
	var ray_order := Vector3i(1, 0, 2) if finisher and fold_top else Vector3i(0, 1, 2) # 同路先发前弹再补尾弹。
	for index: int in range(3): # 每批仍消耗原先三个逻辑发数。
		var ray: int = ray_order[index] # 同批中的实际派发次序。
		var target_lane: int = lane + ray - 1 # 初始瞄准的攻击行。
		var fold: bool = (ray == 0 and fold_top) or (ray == 2 and fold_bottom) # 不发向关闭的相邻行。
		var direction: Vector2 = _direction(1 if fold else ray) # 折返弹沿用本行方向。
		var origin: Vector2 = muzzle # 折返弹稍落后但独立碰撞。
		if fold:
			target_lane = lane
			merged += 1
			origin -= direction.normalized() * (MERGED_PEA_SPACING * merged)
		var bullet: BulletLinear000Base = _pea_scene.instantiate() # 原生线性弹体或动能特化。
		var params: Dictionary = _parameters(origin, direction, target_lane, enhanced) # 源星级倍率只应用一次。
		if boosts[ray] > 1:
			params[Bullet000NormBase.E_InitParasAttr.DamageMultiplier] = _shot.damage_multiplier * boosts[ray]
			params[Bullet000NormBase.E_InitParasAttr.FinisherHighlight] = true
		bullet.init_bullet(params)
		if enhanced:
			bullet.merge_pea_splats = merge_splats
			var edge: float = _edge_x(rows[target_lane], view, direction.x) # 已越出有效战斗区时尽早回收。
			bullet.max_distance = absf(edge - origin.x) + OFFBOARD_MARGIN
			if kinetic_enabled:
				bullet.set("terrain", game.main_game_slope)
		bullets.add_child(bullet)
		if target_lane != lane:
			var target_y: float = rows[target_lane].zombie_create_position.global_position.y # 原生行高。
			bullet.change_y(muzzle.y + target_y - source_y)

## 计入本批实际送往各行的发数。[param fold_top] 与 [param fold_bottom] 描述发射时的行状态。
## 只在末批返回各行尾弹的倍率；边路按末发前实际合流的发数计算。
func _finish_multipliers(fold_top: bool, fold_bottom: bool) -> Vector3i:
	_fired_in_lane += Vector3i(int(not fold_top), 1 + int(fold_top) + int(fold_bottom), int(not fold_bottom))
	var boosts := Vector3i.ONE # 非末批全部是普通伤害。
	if _pea_rounds > 0:
		return boosts
	if not fold_top:
		boosts.x = mini(finisher_cap, _fired_in_lane.x)
	if not fold_bottom:
		boosts.z = mini(finisher_cap, _fired_in_lane.z)
	var tail: int = 2 if fold_bottom else (0 if fold_top else 1) # 有并入时，最后的一颗落在炮口后方。
	boosts[tail] = mini(finisher_cap, _fired_in_lane.y)
	return boosts

## [param game] 的每条有效路径同时各发一次，重合路线只增加后续脉冲数。
func _fire_lasers(game: MainGameManager) -> void:
	var manager: ZombieManager = game.zombie_manager # 合流复核地形行，兼容阶段性脱落。
	var lane: int = owner.lane # 同一时间表以原始攻击行为基准。
	var rows: Array[ZombieRow] = manager.all_zombie_rows # 实际攻击行基线。
	var center_height: float = laser_muzzles[1].global_position.y # 以中间口型取得当前齐射的统一入行高度。
	var source_y: float = rows[lane].zombie_create_position.global_position.y # 本行基准高度。
	var direction: Vector2 = _direction(1) # 高能沿各自的轨道水平贯穿。
	var view: Rect2 = BloomerangFlightQuery.screen_rect(self) # 同帧三路共用一个实际镜头范围。
	for side: int in [0, 2]: # 并入外侧配额，不把重合的三道光同时画在一起。
		if _laser_rounds[side] > 0 and not manager.is_lane_open(lane + side - 1):
			_laser_rounds[1] += _laser_rounds[side]
			_laser_rounds[side] = 0
	for ray: int in range(3): # 每路每个刻点只结算一次。
		if _laser_rounds[ray] <= 0 or not _shot.is_active():
			continue
		_laser_rounds[ray] -= 1
		var target_lane: int = lane + ray - 1 # 此路相对当前原株的攻击行。
		var row: ZombieRow = rows[target_lane] # 读真实生成线而非按固定格宽估算。
		var muzzle: Marker2D = laser_muzzles[ray] # 本路从实际开火的口型中心出光。
		var lane_shift: float = row.zombie_create_position.global_position.y - source_y # 用真实行距投影坡面。
		var rail_end := Vector2(_edge_x(row, view, direction.x), center_height + lane_shift) # 支线入行后的水平轨道。
		var laser: Bullet000NormBase = _laser_scene.instantiate() # 独立脉冲，不为每个命中复制弹体。
		laser.init_bullet(_parameters(muzzle.global_position, direction, target_lane, true))
		bullets.add_child(laser)
		laser.call("fire", muzzle, rail_end, game.main_game_slope, lane, lane_shift, LANE_TINTS[ray],
			_pulse_interval, _impact_rules != null and _impact_rules.requires_forward_order())

## 返回 [param row] 对应 [param view] 内外的战斗边界；[param forward] 决定朝向。
func _edge_x(row: ZombieRow, view: Rect2, forward: float) -> float:
	return maxf(row.zombie_create_position.global_position.x, view.end.x) if forward >= 0.0 else view.position.x

## [param origin]、[param direction]、[param target_lane] 是实际出膛数据。
## [param enhanced] 时同批共用冻结来源和命中词条，避免每枚重取复杂战场状态。
func _parameters(origin: Vector2, direction: Vector2, target_lane: int, enhanced: bool) -> Dictionary:
	if not enhanced:
		var native: Dictionary = get_bullet_paras(origin, direction) # 原版沿用父类参数。
		native[Bullet000NormBase.E_InitParasAttr.BulletLane] = target_lane
		return native
	return {
		Bullet000NormBase.E_InitParasAttr.IsActivateLane: true,
		Bullet000NormBase.E_InitParasAttr.BulletLane: target_lane,
		Bullet000NormBase.E_InitParasAttr.Direction: direction,
		Bullet000NormBase.E_InitParasAttr.Position: bullets.to_local(origin),
		Bullet000NormBase.E_InitParasAttr.CanAttackPlantState: can_attack_plant_status,
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: can_attack_zombie_status,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: _shot.damage_multiplier,
		Bullet000NormBase.E_InitParasAttr.AttackContext: _shot.attack_context,
		Bullet000NormBase.E_InitParasAttr.AttackValidity: _shot_guard,
		Bullet000NormBase.E_InitParasAttr.ImpactEffect: _shot_impact,
	}
