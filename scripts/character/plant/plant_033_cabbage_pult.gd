## 转职卷心菜继续从原生离手帧发射，在单株内排定额外投掷。
extends Plant000Base
class_name Plant033CabbagePult

## 统一处理同一战场内的特殊落点。
const Landing = preload("res://scripts/adventure/research/cabbage_landing.gd")
## 卷心菜弹体脚本与原抛投场景一起惰性载入。
const Cabbage = preload("res://scripts/bullet/bullet_009_cabbage.gd")
## 四种特殊效果可独立同时触发，额外投掷词条只控制这一轮排程。
enum Power { GOLD = 1, TRIPLE = 2, HELL = 4, SPLIT = 8, HOMERUN = 16, AGAIN = 32, BLACK = 64, BOOST = 128 }
## 每轮主目标的三连投间隔，单位游戏秒。
const TRIPLE_INTERVAL: float = 0.145
## 再来紧接本次投掷，保留可见的弹道间距。
const AGAIN_DELAY: float = 0.067
## 裂叶在多个方位间错开少量时间。
const SPLIT_INTERVAL: float = 0.038

## 排定的一次离手，锁定者离场后仍保留当时的真实落点。
class Toss:
	## 仍可追踪的对象。
	var target: Character000Base
	## 投掷组件原生使用的受击锚点。
	var aim: Vector2
	## 上次确认的实际脚点，与受击锚点分开。
	var foot: Vector2
	## 该弹到达的行。
	var row: int
	## 从本轮开始到离手的游戏秒数。
	var at: float

## 原生动画、检测和目标快照。
@onready var attack_component: AttackComponentBulletPultBase = $AttackComponent
## 当前卡冻结的转职词条。
var _powers: int = 0
## 本轮快照，母株退场前已发弹体可继续使用。
var _shot: RepeaterShotContext
## 本轮的有限投掷队列，最多三发主投、五发裂叶和各一次补投。
var _pending: Array[Toss] = []
## 本轮排程时间，空队列停止更新。
var _elapsed: float = 0.0
## 实际发射所需的共用范围命中与特效。
var _landing: Node2D

## [param events] 是入树前从出战卡解析出的卷心菜词条。
func configure_promotions(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 当前阶选择在卡片事务内已经校验。
		match String(event.kind):
			"cabbage_gold": _powers |= Power.GOLD
			"cabbage_triple": _powers |= Power.TRIPLE
			"cabbage_hell": _powers |= Power.HELL
			"cabbage_split": _powers |= Power.SPLIT
			"cabbage_homerun": _powers |= Power.HOMERUN
			"cabbage_again": _powers |= Power.AGAIN
			"cabbage_black": _powers |= Power.BLACK
			"cabbage_two_hundred": _powers |= Power.BOOST

## 正式战斗才安装转职；裂叶通过原攻击时钟查询相邻行。
func ready_norm_signal_connect() -> void:
	super()
	signal_update_speed.connect(attack_component.owner_update_speed)
	set_physics_process(false)
	if _powers == 0:
		return
	attack_component.shoot_override = _release_volley
	if _powers & Power.SPLIT:
		attack_component.target_override = _choose_split_primary
		attack_component.set_requires_target(false)

## 有本行敌人时保留原生左侧优先，空行使用相邻的有效僵尸。
func _choose_split_primary() -> Character000Base:
	var best: Character000Base = null # 本行的自然索敌优先于邻行。
	for candidate: Character000Base in attack_component.detect_component.get_all_enemy_can_be_attacked(): # 保留僵王和障碍入口。
		if candidate.is_in_group(&"lobber_secondary_targets"):
			continue
		if best == null or candidate.hurt_box_component.global_position.x < best.hurt_box_component.global_position.x:
			best = candidate
	if best != null:
		return best
	var candidates: Array[Zombie000Base] = _nearby_targets(1, null) # 只取最近一个有效邻行目标。
	return candidates[0] if not candidates.is_empty() else attack_component.detect_component.update_first_enemy()

## 在本行和相邻行选出最多 [param limit] 个前方活目标，[param omit] 已被锁定。
func _nearby_targets(limit: int, omit: Character000Base) -> Array[Zombie000Base]:
	var results: Array[Zombie000Base] = [] # 始终保持小规模有序候选，无需排序整行。
	var manager: ZombieManager = Global.main_game.zombie_manager # 只在一次攻击开始时读取战场登记。
	for row: int in range(maxi(0, lane - 1), mini(lane + 2, manager.all_zombies_2d.size())): # 包含棋盘边行。
		if not manager.is_lane_open(row):
			continue
		for reference: Variant in manager.all_zombies_2d[row]: # 退场对象先校验再使用。
			if not is_instance_valid(reference) or reference == omit or reference.global_position.x < global_position.x \
					or not Landing.can_hit(reference, attack_component.can_attack_zombie_status):
				continue
			var index: int = results.size() # 新目标比现有后排更靠前时插入。
			while index > 0 and reference.global_position.x < results[index - 1].global_position.x:
				index -= 1
			if index >= limit:
				continue
			if results.size() == limit:
				results.pop_back()
			results.insert(index, reference)
	return results

## 一轮只做一次三连投和裂叶判定，每次原定投掷独立抽取一次补投。
func _release_volley() -> void:
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(self) # 额外弹共享本轮伤害与轮次。
	if shot == null or attack_component._aimed_lane < 0:
		return
	_send_due(INF) # 即使外部攻速极高，也先发完上轮以保持单轮队列上限。
	_shot = shot
	_landing = Landing.for_battle(shot.game)
	_elapsed = 0.0
	var primary: Character000Base = attack_component.last_target_enemy if is_instance_valid(attack_component.last_target_enemy) else null # 原生蓄力时锁定。
	var count: int = 3 if (_powers & Power.TRIPLE) != 0 and randf() < 0.5 else 1 # 三连投仍只算同一轮。
	for index: int in range(count): # 多发按固定间隔顺次离手。
		_plan_toss(primary, attack_component.last_target_enemy_global_pos, attack_component._aimed_lane, index * TRIPLE_INTERVAL)
	if _powers & Power.SPLIT:
		var extras: Array[Zombie000Base] = _nearby_targets(5, primary) # 去掉主目标且不重复分配。
		if not extras.is_empty():
			var total: int = randi_range(1, extras.size()) # 仅在当前实际可锁定的范围内抽取。
			for index: int in range(total): # 各目标独立拥有自己的落点。
				var other: Zombie000Base = extras[index] # 裂叶从离家最近的可用目标开始。
				_plan_toss(other, other.hurt_box_component.global_position, other.lane, (index + 1) * SPLIT_INTERVAL)
	_pending.sort_custom(func(a: Toss, b: Toss) -> bool: return a.at < b.at)
	attack_component.signal_shoot_bullet.emit()
	_send_due(0.0)

## 将 [param target] 和落点 [param aim]、[param row] 排入 [param at] 秒，补投继承瞄准且独立抽取弹种。
func _plan_toss(target: Character000Base, aim: Vector2, row: int, at: float) -> void:
	var toss := Toss.new() # 每次原定投掷只建一份起射数据。
	toss.target = target
	toss.aim = aim
	toss.foot = Landing.foot_at(_shot, target, aim.x, row)
	toss.row = row
	toss.at = at
	_pending.append(toss)
	if (_powers & Power.AGAIN) != 0 and randf() < 0.5:
		var followup := Toss.new() # 补投直接入队，不再次触发任何排程词条。
		followup.target = toss.target
		followup.aim = toss.aim
		followup.foot = toss.foot
		followup.row = toss.row
		followup.at = at + AGAIN_DELAY
		_pending.append(followup)

## 推进 [param delta] 个游戏秒；冻结时暂停剩余投掷。
func _physics_process(delta: float) -> void:
	if not is_cold_frozen():
		_elapsed += delta
		_send_due(_elapsed)

## 发送到 [param now] 为止已到期的投掷。未发送的旧批次无法穿过阶段边界。
func _send_due(now: float) -> void:
	if _shot == null or not _shot.is_active() or is_death:
		_pending.clear()
	while not _pending.is_empty() and _pending[0].at <= now:
		_throw(_pending.pop_front())
	set_physics_process(not _pending.is_empty())
	if _pending.is_empty():
		_shot = null

## 发出 [param toss]，目标仍有效时取当前真实受击点，离场时使用先前快照。
func _throw(toss: Toss) -> void:
	var marks: Array[Marker2D] = attack_component.markers_2d_bullet # 始终从原生弹口发出。
	var origin: Vector2 = marks[0].global_position # 实际离手时的世界坐标。
	var flags: int = _roll_payload() # 每一发的特殊概率独立。
	var bullet := Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet009Cabbage).instantiate() as Cabbage # 不创建第二份弹体场景。
	var target: Character000Base = toss.target if is_instance_valid(toss.target) and Landing.can_hit(toss.target, attack_component.can_attack_zombie_status) else null # 移除、魅惑、退场时使用原落点。
	var row: int = target.lane if target != null and target.lane >= 0 else toss.row # 跟随仍有效的换行目标。
	var point: Vector2 = target.hurt_box_component.global_position if target != null else toss.aim # 从新帧取轨迹终点。
	bullet.configure(_landing, _shot, flags, (_powers & Power.BOOST) != 0, toss.foot)
	attack_component.signal_bullet_instantiated.emit(bullet)
	bullet.init_bullet({
		Bullet000NormBase.E_InitParasAttr.IsActivateLane: true,
		Bullet000NormBase.E_InitParasAttr.BulletLane: row,
		Bullet000NormBase.E_InitParasAttr.Position: _shot.game.bullets.to_local(origin),
		Bullet000NormBase.E_InitParasAttr.Direction: Vector2.RIGHT,
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: attack_component.can_attack_zombie_status,
		Bullet000NormBase.E_InitParasAttr.Enemy: target,
		Bullet000NormBase.E_InitParasAttr.EnemyGloPos: point,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: _shot.damage_multiplier,
		Bullet000NormBase.E_InitParasAttr.AttackContext: _shot.attack_context,
		Bullet000NormBase.E_InitParasAttr.AttackValidity: _shot.is_active,
	})
	_shot.game.bullets.add_child(bullet)
	attack_component.play_throw_sfx(origin)

## 只为已习得的特殊词条抽取各自30%概率。
func _roll_payload() -> int:
	var flags: int = 0 # 同一发可同时获得多种词条。
	if (_powers & Power.GOLD) != 0 and randf() < 0.3:
		flags |= Landing.Payload.GOLD
	if (_powers & Power.HELL) != 0 and randf() < 0.3:
		flags |= Landing.Payload.HELL
	if (_powers & Power.HOMERUN) != 0 and randf() < 0.3:
		flags |= Landing.Payload.HOMERUN
	if (_powers & Power.BLACK) != 0 and randf() < 0.3:
		flags |= Landing.Payload.BLACK
	return flags
