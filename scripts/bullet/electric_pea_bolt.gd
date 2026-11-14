## 每枚电球的半秒放电结算及独立电弧表现。
extends RefCounted
class_name ElectricPeaBolt

## 原版电弧和芦苇命中资源。
const EFFECTS: PackedScene = preload("res://scenes/character/plant/electric_peashooter_bolt.tscn")
## 对电弧及命中采用实际出手等阶的配色。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 每次放电的半径，以棋盘实际横向格宽为单位。
const RANGE_CELLS: float = 2.0
## 原版单道电弧显示的游戏秒数。
const DURATION: float = 0.15
## 原版电弧图像的参考长度，单位为世界像素。
const LENGTH: float = 91.0
## 放电提示音；同一轮多道弧只播一次。
const SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/bolt_fire.tres")


## 从 [param origin] 以 [param lane] 附近为放电范围；[param shot] 提供战斗来源，[param damage] 已计入弹体伤害比例。
static func discharge(shot: ElectricPeaShotContext, origin: Vector2, lane: int, damage: int) -> void:
	var candidates := ElectricPeaFlightQuery.all_targets(shot.game) # 直接命中和后续跳跃共用本轮敌方候选。
	var zombies: Array[Character000Base] = [] # 优先随机选僵尸。
	var structures: Array[Character000Base] = [] # 设施补足原始电弧名额。
	var radius_squared: float = pow(RANGE_CELLS * shot.cell_pitch.x, 2.0) # 格宽按发射位置换算。
	for target: Character000Base in candidates: # 几何距离与真实攻击行共同限制放电范围。
		var impact: Vector2 = ElectricPeaFlightQuery.target_position(target) # 僵王根节点可能不在真实落点。
		if origin.distance_squared_to(impact) > radius_squared 				or (not target is ZB000Base and absi(shot.target_lane(target, impact) - lane) > 1):
			continue
		if target is EnemyStructureBase:
			structures.append(target)
		else:
			zombies.append(target)
	zombies.shuffle()
	structures.shuffle()
	zombies.append_array(structures)
	var visited: Dictionary[int, bool] = {} # 原始命中后才进入跳跃，避免抢占同轮主目标。
	var scope := CombatHitScope.new() # 防止不同电弧经保护者转移后重复扣同一实体。
	var impacts: Array[Vector2] = [] # 有实伤的原始电弧落点。
	var lanes: Array[int] = [] # 各个落点对应的攻击行。
	var strikes: int = 0 # 无敌碰撞仍保持原生放电名额与表现。
	var receipt: Dictionary = {} # 重用同一份回执，跳跃额外排除实际承伤的保护者。
	for reference: Variant in zombies: # 受击回调可能同步释放后续候选。
		if strikes >= shot.promotions.bolt_targets or not shot.is_active():
			break
		if not is_instance_valid(reference) or not ElectricPeaFlightQuery.can_hit(reference):
			continue
		var target: Character000Base = reference # 此时目标尚可读取落点和身份。
		var impact: Vector2 = ElectricPeaFlightQuery.target_position(target) # 扣血前保存，兼容致死命中。
		var impact_lane: int = shot.target_lane(target, impact) # 折射从该落点所在行开始。
		visited[target.get_instance_id()] = true
		if strikes == 0:
			SoundManager.play_sfx_with_pool(SOUND, -18.0)
		strikes += 1
		_show(shot, origin, impact)
		if shot.hit(target, damage, ElectricPeaShotContext.HitKind.ARC, scope, receipt) > 0:
			var recipient: Variant = receipt.get("recipient") # 转伤对象也不能在此轮被跳跃重复击中。
			if is_instance_valid(recipient):
				visited[recipient.get_instance_id()] = true
			impacts.append(impact)
			lanes.append(impact_lane)
	if shot.promotions.jump_cells <= 0.0:
		return
	for index: int in range(impacts.size()): # 每段原始实伤电弧最多折射一次，派生弧不再进入此列表。
		_jump(shot, impacts[index], lanes[index], damage, candidates, visited, scope)


## 从 [param origin] 所在 [param lane] 向最近的候选折射。
## [param shot] 和 [param damage] 沿用原弧；[param candidates]、[param visited] 与 [param scope] 共用本轮结算。
static func _jump(shot: ElectricPeaShotContext, origin: Vector2, lane: int, damage: int,
		candidates: Array[Character000Base], visited: Dictionary[int, bool], scope: CombatHitScope) -> void:
	var nearby: Array[Character000Base] = [] # 首个真正承伤的候选消耗唯一跳跃名额。
	for reference: Variant in candidates: # 同轮已经打过的目标不会被折射重复命中。
		if not is_instance_valid(reference) or not ElectricPeaFlightQuery.can_hit(reference) 				or visited.has(reference.get_instance_id()):
			continue
		var target: Character000Base = reference # 初筛采用芦苇的行差和横向格距。
		var impact: Vector2 = ElectricPeaFlightQuery.target_position(target) # 查真实受击位置。
		if absi(shot.target_lane(target, impact) - lane) <= 1 				and absf(impact.x - origin.x) <= shot.promotions.jump_cells * shot.cell_pitch.x:
			nearby.append(target)
	nearby.sort_custom(func(a: Character000Base, b: Character000Base) -> bool: # a、b 为按落点距离比较的目标。
		return ElectricPeaFlightQuery.target_position(a).distance_squared_to(origin) 			< ElectricPeaFlightQuery.target_position(b).distance_squared_to(origin))
	for reference: Variant in nearby: # 免疫或已由保护者接走的候选不能产生折射表现。
		if not shot.is_active():
			return
		if not is_instance_valid(reference) or not ElectricPeaFlightQuery.can_hit(reference):
			continue
		var target: Character000Base = reference # 回调后重新确认候选仍有效。
		var target_id: int = target.get_instance_id() # 致死后仍需登记原目标。
		var impact: Vector2 = ElectricPeaFlightQuery.target_position(target) # 致死命中也保留电弧终点。
		if shot.hit(target, damage, ElectricPeaShotContext.HitKind.JUMP, scope) <= 0:
			continue
		visited[target_id] = true
		if shot.is_active():
			_show(shot, origin, impact)
		return


## 用 [param shot] 的配色从 [param origin] 到 [param impact] 绘制共享电弧及命中动画。
static func _show(shot: ElectricPeaShotContext, origin: Vector2, impact: Vector2) -> void:
	var bolt: Node2D = _spawn_effect(shot, &"bolt", origin) # 电弧资源的横轴对齐真实两端。
	var direction: Vector2 = impact - origin # 方向和距离决定表现的旋转及长度。
	bolt.global_rotation = direction.angle()
	bolt.scale.x = maxf(1.0, direction.length()) / LENGTH
	_spawn_effect(shot, &"hit", impact)


## 在 [param shot] 的战场于 [param at] 播放 [param clip]；返回独立动画节点并在播完后释放。
static func _spawn_effect(shot: ElectricPeaShotContext, clip: StringName, at: Vector2) -> Node2D:
	var effect: Node2D = EFFECTS.instantiate() as Node2D # 原资源自带换色和动画结构。
	PromotionArt.apply_to_effect(effect, shot.appearance_rank)
	shot.game.bullets.add_child(effect)
	effect.global_position = at
	effect.z_index = 350
	var player: AnimationPlayer = effect.get_node(^"AnimationPlayer") as AnimationPlayer # 每段动画独立回收。
	player.animation_finished.connect(func(_clip: StringName) -> void: effect.queue_free(), CONNECT_ONE_SHOT) # _clip 是结束的动画名。
	var rate: float = player.get_animation(clip).length / DURATION if clip == &"bolt" else 1.0 # 命中保留原动画速度。
	player.play(clip, -1.0, rate)
	return effect