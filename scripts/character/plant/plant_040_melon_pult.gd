## 转职西瓜沿用原生抛物线投手和离手帧；多发计划冻结在真实攻击中。
extends Plant000Base
class_name Plant040MelonPult

## 原生地面定位与敌对目标资格。
const Ground = preload("res://scripts/adventure/research/cabbage_landing.gd")
## 幻影蓄力只使用现有画布。
const Phantom = preload("res://scripts/adventure/research/melon_phantom_visual.gd")
## 转职标记和弹体使用同一组命中行为。
enum Power { SCATTER = 1, HEAVY = 2, SHATTER = 4, KNOCKBACK = 8, BURST = 16, STUN = 32, KRATOS = 64, FORMATION = 128 }

## 克拉托斯的固定蓄力时长，单位游戏秒。
const CHARGE_SECONDS: float = 1.0
## 同一次齐射的相邻西瓜离手间隔，单位游戏秒。
const MELON_SPACING: float = 0.04
## 列阵的两轮完整齐射错峰，单位游戏秒。
const SALVO_SPACING: float = 0.28
## 邻行索敌沿用本行原生射线的前向长度。
const SIGHT_DISTANCE: float = 1000.0
## 仅此株投掷动画结束时解除本轮的 OneShot 占用。
const THROW_ANIMATION: StringName = &"MelonPult_shooting"
## 全战场每物理步允许实例化的转职瓜数；超出顺延，不丢已登记的瓜。
const SPAWN_LIMIT: int = 12
## 弹体容器独占的帧号和当前帧已占用的发射配额。
const SPAWN_BUDGET: StringName = &"_melon_promotion_spawn_budget"

## 一个射击方向，列阵可多次复用。空目标时仍保留真实格和瞄准点。
class Toss:
	## 锁定敌人，变为友军或退场时改飞预定落点。
	var target: Character000Base
	## 预定格供动态棋盘重新投影空行和重磅的固定落点。
	var cell: PlantCell
	## 目标为空或失效时使用的瞄准点。
	var aim: Vector2
	## 逻辑攻击行，落点与当前平台重投影时更新。
	var row: int

## 原生动画、索敌和攻击计时入口。
@onready var attack_component: AttackComponentBulletMelon = $AttackComponent
## 真实的篮中西瓜，在动画离手帧给出发射起点。
@onready var _held_melon: Sprite2D = $Body/BodyCorrect/Melonpult_mellon
## 仅来自入树前冻结的冒险卡。
var _powers: int = 0
## 正在蓄力的游戏秒数；负值表示没有活跃蓄力。
var _charge_elapsed: float = -1.0
## 活跃原生甩篮动作，在下一次计时到期前禁止重入。
var _swing_active: bool = false
## 从蓄力或甩篮开始持有的轮次门禁，禁止旧动画跨场补发。
var _windup_shot: RepeaterShotContext
## 此次原生离手捕获的战场归因和真实数值。
var _shot: RepeaterShotContext
## 每轮齐射的独立瞄准表，仅复制索引与时间，不复制落点数据。
var _pattern: Array[Toss] = []
## 含列阵附加轮次的总瓜数；只在实际发射后递增游标。
var _toss_count: int = 0
## 下一枚瓜在本轮的序号。
var _toss_index: int = 0
## 已排定的投掷离手时间，以首次离手为零秒。
var _salvo_elapsed: float = 0.0
## 后续弹沿用首个真实离手位置相对母株的坐标，平台移动会一同跟随。
var _release_socket: Vector2

## [param events] 为研究卡冻结入场时解析的词条，一阶只会有一个选项。
func configure_promotions(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 每本书独立启用词条。
		match String(event.kind):
			"melon_scatter": _powers |= Power.SCATTER
			"melon_heavy": _powers |= Power.HEAVY
			"melon_shatter": _powers |= Power.SHATTER
			"melon_knockback": _powers |= Power.KNOCKBACK
			"melon_burst": _powers |= Power.BURST
			"melon_stun": _powers |= Power.STUN
			"melon_kratos": _powers |= Power.KRATOS
			"melon_formation": _powers |= Power.FORMATION

## 正常出战保留投手组件；仅转职植株安装蓄力及多发逻辑。
func ready_norm_signal_connect() -> void:
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)
	set_physics_process(false)
	if _powers == 0:
		return
	attack_component.prepare_volley = _prepare_attack
	attack_component.shoot_override = _release_volley
	attack_component.animation_tree.animation_finished.connect(_finish_swing)
	if _powers & Power.KRATOS:
		body.draw.connect(_draw_charge)
	if _powers & Power.SCATTER:
		attack_component.target_override = _choose_scatter_target
		attack_component.set_requires_target(false)

## 原生时钟到期后选择目标。高攻速时不截断已经承诺的齐射、蓄力与甩篮。
func _prepare_attack() -> void:
	if is_death or is_cold_frozen() or not attack_component.is_attack_res or _swing_active \
			or _charge_elapsed >= 0.0 or _toss_index < _toss_count:
		return
	var target: Character000Base = attack_component._choose_pult_target() # 普通和散射各用自己的检测器。
	if not Ground.can_hit(target, attack_component.can_attack_zombie_status):
		return
	_windup_shot = RepeaterShotContext.from_plant(self)
	if _windup_shot == null:
		return
	if _powers & Power.KRATOS:
		_charge_elapsed = 0.0
		body.queue_redraw()
		set_physics_process(true)
	else:
		_start_swing(target)

## [param target] 已通过当前战场和命中状态检查，只有原生动画方法轨会离手。
func _start_swing(target: Character000Base) -> void:
	_swing_active = true
	attack_component.play_melon_windup(target)

## [param animation_name] 只消费原生投掷动画的收尾。
func _finish_swing(animation_name: StringName) -> void:
	if animation_name == THROW_ANIMATION:
		_swing_active = false
		_windup_shot = null

## [param delta] 推进游戏秒；冰冻时停在当前蓄力进度及投掷间隔。
func _physics_process(delta: float) -> void:
	var frozen: bool = is_cold_frozen() # 零速只暂停有效排程，过期轮次仍在下方回收。
	if _charge_elapsed >= 0.0:
		if is_death or _windup_shot == null or not _windup_shot.is_active() or not attack_component.is_attack_res:
			_charge_elapsed = -1.0
			_windup_shot = null
		elif not frozen:
			_charge_elapsed += delta
			if _charge_elapsed + 0.000001 >= CHARGE_SECONDS:
				_charge_elapsed = -1.0
				var target: Character000Base = attack_component._choose_pult_target() # 蓄满时允许重新取得仍有效的目标。
				if Ground.can_hit(target, attack_component.can_attack_zombie_status):
					_start_swing(target)
				else:
					_windup_shot = null
		body.queue_redraw()
	if _toss_index < _toss_count and (not frozen or is_death or _shot == null or not _shot.is_active()):
		_salvo_elapsed += delta
		_send_due()
	var charged_glow: bool = _retains_charge_glow() # 蓄满到真正离手前保留亮弧并跟随篮子。
	if charged_glow or ((_powers & Power.KRATOS) != 0 and _swing_active):
		body.queue_redraw()
	set_physics_process(_charge_elapsed >= 0.0 or _toss_index < _toss_count or charged_glow)

## 蓄满后的甩篮仍显示完整光弧，真正离手或换轮时清除。
func _retains_charge_glow() -> bool:
	return (_powers & Power.KRATOS) != 0 and _swing_active and not is_death \
		and _windup_shot != null and _windup_shot.is_active()

## 在篮中瓜的画面中心叠一层逐渐收拢的幻影蓄力，不修改原动作贴图。
func _draw_charge() -> void:
	if _charge_elapsed >= 0.0 or _retains_charge_glow():
		var progress: float = _charge_elapsed / CHARGE_SECONDS if _charge_elapsed >= 0.0 else 1.0 # 未离手的满蓄力显示最高亮度。
		Phantom.draw_charge(body, body.to_local(_melon_socket()), progress)

## 返回真实投篮里瓜的中心；动画隐藏篮中瓜后，仍保留该释放帧的几何位置。
func _melon_socket() -> Vector2:
	return _held_melon.to_global(_held_melon.get_rect().get_center())

## 返回本行原生目标优先、否则相邻行离家最近的敌人。
func _choose_scatter_target() -> Character000Base:
	var game: MainGameManager = Global.main_game # 使用真实的攻击行。
	if not is_instance_valid(game):
		return null
	var targets: Dictionary[int, Character000Base] = _scatter_targets(game.zombie_manager) # 最多三个已选方向。
	if targets.has(lane):
		return targets[lane]
	var best: Character000Base # 相邻两行有目标时选 X 更靠前的敌人。
	for candidate: Character000Base in targets.values(): # 这里没有空行占位。
		if best == null or candidate.global_position.x < best.global_position.x:
			best = candidate
	return best

## 在 [param manager] 的本行及相邻行取各自的一个敌人；不为单颗弹扫描全盘。
func _scatter_targets(manager: ZombieManager) -> Dictionary[int, Character000Base]:
	var targets: Dictionary[int, Character000Base] = {} # 只包含实际目标，空行由齐射计划补齐。
	var fallback: Character000Base = attack_component.detect_component.update_first_enemy() # 本行墓碑只在无可用普通目标时使用。
	for candidate: Character000Base in attack_component.detect_component.get_all_enemy_can_be_attacked(): # 本行保留 Boss 及原生碰撞检测。
		if not candidate.is_in_group(&"lobber_secondary_targets") and Ground.can_hit(candidate, attack_component.can_attack_zombie_status):
			if not targets.has(lane) or candidate.global_position.x < targets[lane].global_position.x:
				targets[lane] = candidate
	if not targets.has(lane) and Ground.can_hit(fallback, attack_component.can_attack_zombie_status):
		targets[lane] = fallback
	for row: int in range(maxi(0, lane - 1), mini(lane + 2, manager.all_zombies_2d.size())): # 边路永远不生成盘外行。
		if row == lane or not manager.is_lane_open(row):
			continue
		for reference: Variant in manager.all_zombies_2d[row]: # 相邻行从在场名册取活敌。
			if not is_instance_valid(reference) or not Ground.can_hit(reference, attack_component.can_attack_zombie_status):
				continue
			var x: float = reference.hurt_box_component.global_position.x # 和本行的原生检测面用同一个前向距离。
			if x < global_position.x - 16.0 or x > global_position.x + SIGHT_DISTANCE:
				continue
			if not targets.has(row) or x < targets[row].hurt_box_component.global_position.x:
				targets[row] = reference
	return targets

## 只在真正离手时抽取一次重磅、计数列阵，并冻结整轮伤害与锁定信息。
func _release_volley() -> void:
	if is_death or is_cold_frozen() or _toss_index < _toss_count or attack_component._aimed_lane < 0:
		return
	if ((_powers & Power.KRATOS) != 0 and not _swing_active) \
			or (_swing_active and (_windup_shot == null or not _windup_shot.is_active())):
		return
	_shot = RepeaterShotContext.from_plant(self)
	if _shot == null:
		return
	_windup_shot = null
	if _powers & Power.KRATOS:
		body.queue_redraw()
	var primary: Character000Base = attack_component.last_target_enemy if is_instance_valid(attack_component.last_target_enemy) else null # 对象退场后使用锁定快照。
	var aim: Vector2 = attack_component.last_target_enemy_global_pos # 保留普通锁定失效时的落点。
	var target_row: int = attack_component._aimed_lane # 无行的僵王使用植物的出射行。
	if Ground.can_hit(primary, attack_component.can_attack_zombie_status):
		aim = primary.hurt_box_component.global_position
		target_row = primary.lane if primary.lane >= 0 else target_row
	else:
		primary = null
	_pattern.clear()
	if _powers & Power.SCATTER:
		_plan_scatter(aim)
	elif (_powers & Power.HEAVY) != 0 and randf() < 0.50:
		_plan_heavy(primary, aim, target_row)
	else:
		_add_toss(primary, aim, target_row)
	_toss_count = _pattern.size() * _volley_count()
	_toss_index = 0
	_salvo_elapsed = 0.0
	_release_socket = to_local(_melon_socket())
	attack_component.signal_shoot_bullet.emit()
	_send_due()
	set_physics_process(_toss_index < _toss_count)

## 本行和实际可用的相邻行各一颗。无目标的方向以 [param aim] 的横坐标瞄准。
func _plan_scatter(aim: Vector2) -> void:
	var manager: ZombieManager = _shot.game.zombie_manager # 由正式棋盘判断行是否存在。
	var targets: Dictionary[int, Character000Base] = _scatter_targets(manager) # 甩篮后单次更新三行目标。
	for row: int in [lane, lane - 1, lane + 1]: # 本行先发，两个侧向瓜顺次扇开。
		if not manager.is_lane_open(row):
			continue
		var target: Character000Base = targets.get(row) # 空行仍然获得一发。
		var point: Vector2 = target.hurt_box_component.global_position if target != null \
			else Ground.foot_at(_shot, null, aim.x, row) - Vector2(0, 30) # 空行从同列真实地面抬到受击高度。
		_add_toss(target, point, row)

## 对 [param primary] 所在的 [param row] 在 [param aim] 附近铺六个落点。
## 先用中心，再用其余可用邻格；角落不足六格时才绕回使用已有格。
func _plan_heavy(primary: Character000Base, aim: Vector2, row: int) -> void:
	var foot: Vector2 = Ground.foot_at(_shot, primary, aim.x, row) # 受击位置与地面格分开。
	var center: PlantCell = _shot.board.cell_at_ground_point(foot, row) # 高低地、动态甲板保留权威格。
	if center == null:
		center = _shot.board.nearest_cell(foot, row)
	var cells: Array[PlantCell] = _shot.board.neighbors(center) if center != null else [] # 3×3 的有效同板邻接。
	cells.erase(center)
	var manager: ZombieManager = _shot.game.zombie_manager # 已坠落的攻击行不计入炮阵。
	cells = cells.filter(func(cell: PlantCell) -> bool: return manager.is_lane_open(cell.combat_lane))
	cells.shuffle()
	if center != null:
		cells.push_front(center)
	_add_toss(primary, aim, row, center)
	for index: int in range(1, 6): # 首颗锁定主体，其余向不同格地面抛射。
		var cell: PlantCell = cells[index % cells.size()] if not cells.is_empty() else null # 盘外无格时仍完成六发。
		_add_toss(null, aim, cell.combat_lane if cell != null else row, cell)

## [param target] 是可选锁定；[param point]、[param row] 和 [param cell] 组成落空时的世界锚点。
func _add_toss(target: Character000Base, point: Vector2, row: int, cell: PlantCell = null) -> void:
	var toss := Toss.new() # 同轮列阵反复读取这份瞄准数据。
	toss.target = target
	toss.aim = point
	toss.row = row
	toss.cell = cell
	_pattern.append(toss)

## 使用植物的逻辑列计数；本列所有存活西瓜投手（含自身）各贡献一次额外齐射。
func _volley_count() -> int:
	if (_powers & Power.FORMATION) == 0 or not is_instance_valid(plant_cell):
		return 1
	var count: int = 1 # 自身提供基础齐射。
	for row: int in range(_shot.board.extent.x): # 一次离手最多查询同列的有效地址。
		var cell: PlantCell = _shot.board.cell_at(Vector2i(row, plant_cell.row_col.y)) # 稀疏棋盘不会填充空格。
		if cell == null:
			continue
		for plant: Plant000Base in cell.living_plants(): # 已铲除或正在退场者不贡献次数。
			if plant is Plant040MelonPult:
				count += 1
	return count

## 发出当前已到期的瓜。全战场共用实例化预算，未发部分顺延；一组齐射只响一次发射声。
func _send_due() -> void:
	if _shot == null or not _shot.is_active() or is_death or _pattern.is_empty():
		_toss_index = _toss_count
	else:
		var host: Node2D = _shot.game.bullets # 配额随着战场弹体容器一起释放。
		var frame: int = Engine.get_physics_frames() # 每物理步只更新一次发射上限。
		var quota: Vector2i = host.get_meta(SPAWN_BUDGET, Vector2i(-1, 0)) # 元数据不持有任何弹体。
		if quota.x != frame:
			quota = Vector2i(frame, 0)
		while _toss_index < _toss_count and quota.y < SPAWN_LIMIT:
			var within: int = _toss_index % _pattern.size() # 同一轮中从中心或本行开始。
			@warning_ignore("integer_division")
			var repeat: int = _toss_index / _pattern.size() # 第几轮列阵齐射，整数分组。
			if _salvo_elapsed + 0.000001 < repeat * SALVO_SPACING + within * MELON_SPACING:
				break
			quota.y += 1
			host.set_meta(SPAWN_BUDGET, quota)
			_toss_index += 1
			_throw(_pattern[within], within == 0)
			if not _shot.is_active() or is_death:
				_toss_index = _toss_count
				break
	if _toss_index >= _toss_count:
		_shot = null
		_pattern.clear()

## 发射原生西瓜。[param toss] 可跟随活敌或实际移动格，[param first] 决定是否播放本轮甩篮声。
func _throw(toss: Toss, first: bool) -> void:
	var target: Character000Base = toss.target if is_instance_valid(toss.target) and Ground.can_hit(toss.target, attack_component.can_attack_zombie_status) else null # 离场快照不会复活目标。
	var row: int = target.lane if target != null and target.lane >= 0 else toss.row # 跟随已经换行的目标。
	var aim: Vector2 = target.hurt_box_component.global_position if target != null else toss.aim # 仍真实瞄向受击点。
	if target == null and is_instance_valid(toss.cell):
		row = toss.cell.combat_lane
		aim = toss.cell.get_spawn_global_position() - Vector2(0, 30)
	if not _shot.game.zombie_manager.is_lane_open(row):
		return
	var origin: Vector2 = to_global(_release_socket) # 对齐上一帧真实篮口并继承当前平台位移。
	var bullet := Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet012Melon).instantiate() as Bullet012Melon # 保留原生碰撞及落地特效。
	bullet.configure_promotion((_powers & Power.SHATTER) != 0, (_powers & Power.KNOCKBACK) != 0, \
		(_powers & Power.STUN) != 0, (_powers & Power.KRATOS) != 0, target == null and is_instance_valid(toss.cell))
	attack_component.signal_bullet_instantiated.emit(bullet)
	var damage: float = _shot.damage_multiplier # 爆碎 +30% 已由冻结卡加入，翻倍分别乘算。
	if _powers & Power.BURST:
		damage *= 2.0
	if _powers & Power.KRATOS:
		damage *= 2.0
	bullet.init_bullet({
		Bullet000NormBase.E_InitParasAttr.IsActivateLane: true,
		Bullet000NormBase.E_InitParasAttr.BulletLane: row,
		Bullet000NormBase.E_InitParasAttr.Position: _shot.game.bullets.to_local(origin),
		Bullet000NormBase.E_InitParasAttr.Direction: Vector2.RIGHT,
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: attack_component.can_attack_zombie_status,
		Bullet000NormBase.E_InitParasAttr.Enemy: target,
		Bullet000NormBase.E_InitParasAttr.EnemyGloPos: aim,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: damage,
		Bullet000NormBase.E_InitParasAttr.AttackContext: _shot.attack_context,
		Bullet000NormBase.E_InitParasAttr.AttackValidity: _shot.is_active,
	})
	_shot.game.bullets.add_child(bullet)
	if first:
		attack_component.play_throw_sfx(origin)
