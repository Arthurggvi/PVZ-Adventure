## 管理同一战场的瞄准、流光时钟、折射队列和明星落点；阶段失效后不再发出派生伤害。
extends Node2D

## 瞄准索敌只有需要重定向的物理步才刷新。
const AimIndex = preload("res://scripts/adventure/research/starfruit_aim_index.gd")
## 落星和命中特效由一个画布批量绘制。
const Visual = preload("res://scripts/adventure/research/starfruit_visual.gd")
## 流光的接触采样率，使用游戏秒。
const FLOW_STEP: float = 1.0 / 30.0
## 单步最多派发三次折射亡语，多余的保序延迟到下一步。
const REFRACTIONS_PER_STEP: int = 3
## 从天缘到落点的飞行时间。
const FALL_TIME: float = 0.61
## 两圈红星发出的时间差。
const SECOND_RING: float = 0.15

## 待溅射的星圈只保存来源与实际世界落点。
class Ring:
	## 派生弹的战斗来源。
	var shot: RepeaterShotContext
	## 本次发射的世界坐标。
	var origin: Vector2
	## 发射的真实行。
	var lane: int
	## 沿用原出手的词条。
	var traits: int

## 一个活僵尸在本轮的首次有效折射来源，跨轮后可被新星弹替换。
class Refraction:
	## 当时的卡牌与战斗快照。
	var shot: RepeaterShotContext
	## 传给死亡时溅出的普通星弹。
	var traits: int

## 预警、坠落和两次溅射共享的单颗明星。
class Meteor:
	## 第三次齐射的攻击快照。
	var shot: RepeaterShotContext
	## 被随机选中的真正敌人，落地前可重新确认其当前格。
	var target: Character000Base
	## 真实落点格。敌人离场时仍结算落到的格子。
	var cell: PlantCell
	## 从夜空进入的世界坐标。
	var entry: Vector2
	## 当前已飞行的游戏秒数。
	var age: float = 0.0
	## 原齐射词条供所有红星使用。
	var traits: int
	## 已落地后只等待第二圈。
	var landed: bool = false
	## 红星共用的引爆值回调。
	var detonation: Dictionary
	## 已处在坠落格内的角色由600点坠落结算，红星从其身边向外扩散。
	var landing_targets: Dictionary[int, bool] = {}

## 单次死亡标记，保护者代伤时标记其本身。
const BLOOM_KEY: StringName = &"_starfruit_refraction_bloomed"
## 明星坠落的固定格伤。
const METEOR_DAMAGE: int = 600
## 延迟实例化弹体时复用原生 PackedScene。
var _star_scene: PackedScene
## 当前所属战场。
var _game: MainGameManager
## 同一物理步共享的精确索引。
var _aim := AimIndex.new()
## 只持有当前有接触的流光星弹，离场后由时钟回收记录。
var _flow: Dictionary[int, Bullet008Star] = {}
## 两次接触样本之间的战斗时钟。
var _flow_clock: float = 0.0
## 一个敌人只登记一个死亡回调，避免多株和多受击区重复溅射。
var _marked: Dictionary[int, Refraction] = {}
## 保留在物理通知之外生成星弹的顺序。
var _rings: Array[Ring] = []
## 释放过的队首索引，分批推进时不逐条移动队列。
var _ring_head: int = 0
## 所有正在坠落或等待第二圈的明星。
var _meteors: Array[Meteor] = []
## 共用特效画布，无活动收据即停止刷新。
var _visual: Visual

## [param game] 的弹道容器中至多存在一个杨桃运行时。
static func for_battle(game: MainGameManager) -> Node2D:
	var runtime := game.bullets.get_node_or_null(^"StarFruitRuntime") as Node2D # 与旧战场自然一并离场。
	if runtime == null:
		runtime = (load("res://scripts/adventure/research/starfruit_battle_runtime.gd") as Script).new()
		runtime.name = "StarFruitRuntime"
		runtime._game = game
		runtime._visual = Visual.for_bullets(game.bullets)
		game.bullets.add_child(runtime)
	return runtime

## 首次实际攻击才初始化，不进入启动场景的常驻资源。
func _ready() -> void:
	_star_scene = Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet008Star)
	set_physics_process(false)

## 从 [param origin] 朝 [param ray] 发射 [param kind]。用 [param shot] 冻结伤害和词条。
## [param attack] 只在植物原生齐射中提供，在初始化前发布原生子弹事件。
## [param limit] 控制范围，[param velocity_scale] 区分星环，[param lane] 为派生弹落点行。
## [param detonation] 专给同一颗明星的两圈红星。
func launch(shot: RepeaterShotContext, origin: Vector2, ray: Vector2, traits: int, kind: Bullet008Star.Kind,
		attack: AttackComponentBulletBase = null, limit: float = 2000.0, velocity_scale: float = 1.0, lane: int = -1,
		detonation: Dictionary = {}) -> Bullet008Star:
	var star := _star_scene.instantiate() as Bullet008Star # 复用真实星弹的碰撞、位移和受击处理。
	if attack != null:
		attack.signal_bullet_instantiated.emit(star)
	star.init_bullet({
		Bullet000NormBase.E_InitParasAttr.IsActivateLane: false,
		Bullet000NormBase.E_InitParasAttr.BulletLane: shot.lane if lane < 0 else lane,
		Bullet000NormBase.E_InitParasAttr.Position: _game.bullets.to_local(origin),
		Bullet000NormBase.E_InitParasAttr.Direction: ray,
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: Zombie000Base.E_BeAttackStatusZombie.IsNorm,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: shot.damage_multiplier,
		Bullet000NormBase.E_InitParasAttr.AttackContext: shot.attack_context,
		Bullet000NormBase.E_InitParasAttr.AttackValidity: shot.is_active,
	})
	star.max_distance = limit
	star.speed *= velocity_scale * (1.38 if kind == Bullet008Star.Kind.BLUE else (1.13 if kind == Bullet008Star.Kind.VIOLET else 1.0))
	star.configure_promotion(self, shot, traits, kind, detonation, _visual)
	_game.bullets.add_child(star)
	return star

## 取 [param star] 在锁定时刻最近的地面目标，[param excluded] 包含已命中的实例。
func lock_star(star: Bullet008Star, excluded: Dictionary[int, bool]) -> void:
	_aim.refresh(_game)
	var index: int = _aim.nearest(star.global_position, excluded) # 各弹起点不同，距离仍按该弹精确比较。
	if index < 0:
		return
	var point: Node2D = _aim.point_at(index) # 留存真实受击中心，无需再次访问角色子树。
	if not is_instance_valid(point):
		return
	star.set_aim_target(_aim.target_at(index), point)
	_visual.add_turn(star.global_position, star.direction, (point.global_position - star.global_position).normalized(), Bullet008Star.TINTS[star.kind])

## [param star] 进入真实受击区后注册定频结算。
func track_flow(star: Bullet008Star) -> void:
	_flow[star.get_instance_id()] = star
	set_physics_process(true)

## [param point] 与 [param tint] 仅送往统一的命中画布。
func flash_hit(point: Vector2, tint: Color) -> void:
	_visual.add_flash(point, tint, false)

## 被 [param shot] 的 [param traits] 击中的 [param target] 只会排队一次死亡星圈。
func mark_refraction(target: Zombie000Base, shot: RepeaterShotContext, traits: int) -> void:
	if not shot.is_active() or target.get_meta(BLOOM_KEY, false):
		return
	var identity: int = target.get_instance_id() # 多受击盒和重复命中共用同一死亡记录。
	if target.is_death or target.is_queued_for_deletion():
		_queue_refraction(target, shot, traits)
		return
	var previous: Refraction = _marked.get(identity) # 新阶段的第一次命中可覆盖过期登记。
	if previous != null and previous.shot.is_active():
		return
	if previous == null:
		target.hp_component.before_death.connect(_on_marked_death.bind(target), CONNECT_ONE_SHOT)
		target.tree_exiting.connect(_on_marked_exit.bind(target, identity))
	var mark := Refraction.new() # 每个活目标只需保存一套死亡星圈来源。
	mark.shot = shot
	mark.traits = traits
	_marked[identity] = mark

## [param target] 的真实死亡通知；[param _cause] 不影响是否放出星圈。
func _on_marked_death(_cause: CombatHitScope.DeathCause, target: Zombie000Base) -> void:
	var identity: int = target.get_instance_id() # 先释放登记再排队，防止同步伤害重入。
	var mark: Refraction = _marked.get(identity) # 可能已在沿途退场时清除。
	_marked.erase(identity)
	if mark != null:
		_queue_refraction(target, mark.shot, mark.traits)

## [param target] 换行时只重挂节点，真离场才丢弃 [param identity]。
func _on_marked_exit(target: Zombie000Base, identity: int) -> void:
	if not target.is_changing_lane:
		_marked.erase(identity)

## 从 [param target] 的最后受击位置排入一圈普通星；跨轮的 [param shot] 不继承 [param traits]。
func _queue_refraction(target: Zombie000Base, shot: RepeaterShotContext, traits: int) -> void:
	if not shot.is_active() or target.is_hypno or target.retiring_from_battle or target.get_meta(BLOOM_KEY, false):
		return
	target.set_meta(BLOOM_KEY, true)
	var ring := Ring.new() # 在物理受击通知中只记录数据，不加入碰撞体。
	var point: Node2D = AimIndex.aim_point(target) # 星圈从真正被击倒的受击处散开。
	ring.origin = point.global_position if is_instance_valid(point) else target.global_position
	ring.shot = shot
	ring.lane = target.lane
	ring.traits = traits
	_rings.append(ring)
	set_physics_process(true)

## 每三次普通攻击为 [param shot] 均匀挑一个棋盘内敌人，保存 [param traits]。
func cast_meteor(shot: RepeaterShotContext, traits: int) -> void:
	var chosen: Character000Base # 蓄水池抽样只占用一个槽位。
	var cell: PlantCell # 最终选中单位的地块。
	var eligible: int = 0 # 每个合法单位同等概率。
	var candidates: Array = _game.zombie_manager.all_zombies_1d + _game.zombie_manager.get_living_bosses() # 只在第三次攻击查看注册表。
	for target: Character000Base in candidates: # 跳过未进棋盘以及已退出战斗的单位。
		if not _can_be_meteor_target(target):
			continue
		var place: PlantCell = shot.board.cell_at_ground_point(target.global_position, target.lane) # 真实脚点必须在格内。
		if place == null:
			continue
		eligible += 1
		if randi_range(1, eligible) == 1:
			chosen = target
			cell = place
	if cell == null:
		return
	var meteor := Meteor.new() # 每颗巨星共享两圈红星和一次伤害归属。
	meteor.shot = shot
	meteor.target = chosen
	meteor.cell = cell
	meteor.traits = traits
	var top: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * Vector2(0, -95) # 从可见天空以上开始。
	var foot: Vector2 = cell.get_spawn_global_position() # 当前格用于计算天边斜入的位置。
	meteor.entry = Vector2(foot.x - 260.0, minf(top.y, foot.y - 350.0))
	meteor.detonation = {"on_detonate": RepeaterAreaEffects.detonate.bind(shot), "landing_targets": meteor.landing_targets}
	_meteors.append(meteor)
	set_physics_process(true)

## [param target] 必须为已进战斗的活敌，空中单位仍可作为明星的地面落点来源。
static func _can_be_meteor_target(target: Character000Base) -> bool:
	return is_instance_valid(target) and not target.is_death and not target.is_hypno \
		and not target.is_queued_for_deletion() and target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and not (target is Zombie000Base and target.retiring_from_battle)

## [param delta] 推进接触采样与派生队列；没有事务时整套战斗更新休眠。
func _physics_process(delta: float) -> void:
	if not _flow.is_empty():
		_flow_clock += delta
		while _flow_clock >= FLOW_STEP - 0.000001 and not _flow.is_empty():
			_flow_clock -= FLOW_STEP
			for id: int in _flow.keys(): # 不在遍历原字典时删掉已分离的弹。
				var star: Variant = _flow[id] # 比流光更早销毁时引用可能失效。
				if not is_instance_valid(star) or not star.tick_flow_contacts():
					_flow.erase(id)
	if _flow.is_empty():
		_flow_clock = 0.0
	for _index: int in range(mini(REFRACTIONS_PER_STEP, _rings.size() - _ring_head)): # 大量同时死亡时分帧发射。
		var ring: Ring = _rings[_ring_head] # 保留同一帧的实际死亡顺序。
		_rings[_ring_head] = null
		_ring_head += 1
		if ring.shot.is_active():
			_visual.add_flash(ring.origin, Color(1.0, 0.76, 0.24), true)
			_release_ring(ring.shot, ring.origin, ring.lane, ring.traits, Bullet008Star.Kind.GOLD, 0.22, 1.03)
	if _ring_head == _rings.size():
		_rings.clear()
		_ring_head = 0
	elif _ring_head >= 192 and _ring_head * 2 >= _rings.size():
		_rings = _rings.slice(_ring_head)
		_ring_head = 0
	_visual.begin_meteors()
	for index: int in range(_meteors.size() - 1, -1, -1): # 反向回收完成或跨阶段的明星。
		if not _advance_meteor(_meteors[index], delta):
			_meteors.remove_at(index)
	_visual.end_meteors()
	if _flow.is_empty() and _rings.is_empty() and _meteors.is_empty():
		set_physics_process(false)

## 推进 [param meteor] 的这一步 [param delta]。在碰撞通知之外提交落地伤害与红星。
func _advance_meteor(meteor: Meteor, delta: float) -> bool:
	var shot: RepeaterShotContext = meteor.shot # 不读取现有卡片或复活的母株。
	if not shot.is_active():
		return false
	meteor.age += delta
	if not meteor.landed and _can_be_meteor_target(meteor.target):
		var updated: PlantCell = shot.board.cell_at_ground_point(meteor.target.global_position, meteor.target.lane) # 移动目标进入新格时更新落点。
		if is_instance_valid(updated):
			meteor.cell = updated
	var cell: PlantCell = meteor.cell # 最后一块确定的地块可能已随棋盘变化离场。
	if not is_instance_valid(cell) or cell.is_queued_for_deletion() or cell.board != shot.board:
		return false
	var foot: Vector2 = cell.get_spawn_global_position() # 绘制跟随真实地块变换。
	if meteor.age < FALL_TIME:
		_visual.add_meteor(meteor.entry, foot, meteor.age / FALL_TIME)
		return true
	var burst: Vector2 = foot + Vector2(0, -36) # 红星从落点正上方展开，碰撞位于单位躯干。
	if not meteor.landed:
		meteor.landed = true
		_meteor_damage(meteor)
		_visual.add_meteor_burst(foot, shot.board.local_pitch(cell))
		SoundManager.play_character_SFX(&"CherryBomb", self, foot, 2)
		EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(4.0, 6.0), 0.18, 22.0])
		_release_ring(shot, burst, cell.combat_lane, meteor.traits, Bullet008Star.Kind.RED, 0.0, 1.39, meteor.detonation)
	if meteor.age < FALL_TIME + SECOND_RING:
		return true
	_release_ring(shot, burst, cell.combat_lane, meteor.traits, Bullet008Star.Kind.RED,
		TAU / 24.0, 1.03, meteor.detonation)
	return false

## [param meteor] 在真实脚点所属格固定打600点，同一实际承伤者每次落地只被结算一次。
func _meteor_damage(meteor: Meteor) -> void:
	var shot: RepeaterShotContext = meteor.shot # 使用原射手的可选攻击与击杀上下文。
	var cell: PlantCell = meteor.cell # 只打本格，邻格和空洞不参与。
	var scope := CombatHitScope.new() # 防具代伤可能汇合到同一实体。
	var candidates: Array = _game.zombie_manager.all_zombies_2d[cell.combat_lane] + _game.zombie_manager.get_living_bosses() # 伤害回调可改变原生列表。
	for target: Character000Base in candidates: # 受击前再次确认仍为同一格活敌。
		if not shot.is_active():
			break
		if not _can_be_meteor_target(target) or target.lane != cell.combat_lane \
				or shot.board.cell_at_ground_point(target.global_position, cell.combat_lane) != cell:
			continue
		meteor.landing_targets[target.get_instance_id()] = true
		var damage: int = shot.attack_context.modify_damage(METEOR_DAMAGE, target) if shot.attack_context != null else METEOR_DAMAGE # 基础固定格伤不重复乘星弹伤害。
		if target is Zombie000Base:
			var receipt: Dictionary = {} # 致死的保护者也可兑现折射。
			var casualty: Zombie000Base = (target.hp_component as HpComponentZombie).apply_hit(damage,
				BulletRegistry.AttackMode.Real, true, false, true, 1.0, 0, -1, receipt, scope) # 不让多受击区重复结算。
			shot.on_kill(casualty)
			var actual: Variant = receipt.get("recipient") # 只标记本次真实命中的角色。
			if meteor.traits & Bullet008Star.Trait.REFRACT and not receipt.get("duplicate_hit", false) and is_instance_valid(actual):
				mark_refraction(actual, shot, meteor.traits)
		elif target is ZB000Base and scope.try_claim(target):
			target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Real, true, false)
			if target.is_death:
				shot.on_kill(target)

## 以 [param origin] 为中心按 [param angle] 等距发射一圈。红星继承 [param detonation]。
## [param shot]、[param lane] 与 [param traits] 冻结战斗归属，[param speed_scale] 用于让两圈可见分离。
func _release_ring(shot: RepeaterShotContext, origin: Vector2, lane: int, traits: int,
		kind: Bullet008Star.Kind, angle: float, speed_scale: float, detonation: Dictionary = {}) -> void:
	var count: int = 12 if kind == Bullet008Star.Kind.RED else 10 # 明星的两圈留半角错位。
	var distance: float = maxf(180.0, shot.cell_pitch.x * (3.2 if kind == Bullet008Star.Kind.RED else 2.45)) # 亡语在局部传播。
	for index: int in range(count): # 每个星体走自己的实际径向弹道。
		var direction: Vector2 = Vector2.RIGHT.rotated(angle + float(index) * TAU / count) # 第一圈与第二圈不会重叠。
		launch(shot, origin + direction * 25.0, direction, traits, kind, null, distance, speed_scale, lane, detonation)
