## 窝瓜的普通落地与窝瓜王共用伤害回执和攻击后结算。只有多次落地需要战场节点继续持有。
extends Node
class_name AdventureSquashAttack

## 无氧训练归属于实际出战卡及 UID，更换卡面身份不会沿用旧值。
const TRAINING_STATE: StringName = &"squash_training_state"
## 抛飞可作用于原生受击位中的各类敌人，实际免控由角色组件决定。
const CONTROL_STATUSES: int = 63
## 一枚小窝瓜从出现到落地的游戏秒数。
const FALL_TIME: float = 0.18
## 确认本次落地之后再出现下一枚的间隔，单位为游戏秒。
const DROP_GAP: float = 0.055
## 密集命中逐批结算真实伤害与阳光，限制每帧提交的生命和掉落事务。
const WORK_ITEMS_PER_FRAME: int = 12
## 单次预算耗时目标，单位为微秒；单个原生伤害不可被切开。
const WORK_BUDGET_USEC: int = 4000
## 现有爆炸资源只在领袖真正结算时加载。
const LEADER_FX: String = "res://resources/combat/jackbox_explosion_profile.tres"

## 只允许在发招时的战场、轮次和阶段继续结算。
var _battle: RepeaterShotContext
## 本次攻击的互斥词条和参数。
var _rules: Dictionary[String, Dictionary]
## 原始种植格，供整轮召唤和愤恨使用。
var _home_id: StringName
## 愤恨完整继承的独立卡片配方。
var _profile: PlantSpawnProfile
## 愤恨保持原株的模仿者材质状态。
var _imitater_material: bool
## 已含星级、光环与本株训练的普通砸击伤害。
var _damage: int
## 未放大的原生压砸伤害，用于窝瓜王单击 Boss 上限。
var _base_damage: int
## 已含出战加成的领袖爆炸，Boss 上限独立计算。
var _leader_damage: int
## 从原生落地组件读取的敌方可受击状态。
var _statuses: int
## 查询僵王和设施用的原生碰撞掩码。
var _mask: int
## 一轮内实际已击杀的实例编号，各只发放一次奖励。
var _credited: Dictionary[int, bool] = {}
## 任一压砸或终结爆炸有实际 Boss 血池损失时置真。
var _boss_hit: bool = false
## 有界结算还在继续时，普通窝瓜可能已完成原生退场。
var _native_consumed: bool = false
## 本轮震撼按受效者记录剩余可叠加时长。
var _shock_until: Dictionary[int, float] = {}
## 本轮经过的活动战斗秒数，菜单暂停不累积。
var _elapsed: float = 0.0
## 窝瓜王的原生立绘部件模板，无生命、碰撞或攻击脚本。
var _body_template: Node2D
## 底部下落阴影使用的原生纹理。
var _shadow_texture: Texture2D
## 本轮已选的格子，选择同优先级目标时尽量分散。
var _used_cells: Dictionary[StringName, bool] = {}
## 当前下落且跟随地块运动的单枚纯表现节点。
var _fall_root: Node2D
## 当前下落仍所对应的真实格子。
var _fall_cell: PlantCell
## 游戏场景中按需要复用矩形查询。
var _rect := RectangleShape2D.new()
## 一击致死前保存实际承伤者的世界位置。
var _death_point: Vector2 = Vector2.INF

## 取出实际出战卡 [param uid] 的当前倍率，然后按 [param rule] 增加下一株的训练。
static func take_training(uid: String, rule: Dictionary) -> float:
	var game: MainGameManager = Global.main_game # 独立卡槽拥有自己的状态，库存不保存训练。
	if not is_instance_valid(game) or game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return 1.0
	var slots: CardSlotBattle = game.card_manager.card_slot_battle # 仅查真正出战的同 UID 卡。
	if not is_instance_valid(slots):
		return 1.0
	var card: Card = slots.find_plant_card_by_uid(uid) # 同物种的其他卡不会代领。
	if not is_instance_valid(card):
		return 1.0
	var state: Dictionary = card.get_meta(TRAINING_STATE, {}) # 保留原 UID，允许槽位以后换另一张卡。
	var percent: int = int(state.get("next", 100)) if state.get("uid", "") == uid else 100 # 第一株为 100%。
	card.set_meta(TRAINING_STATE, {"uid": uid, "next": mini(int(rule["cap"]), percent + int(rule["gain"]))})
	return percent * 0.01

## [param plant] 的原生落地在 [param battle] 中结算，[param rules] 来自出战快照。
## 一般命中同拍结算，密集命中把后续批次留给原战局。
static func land(plant: Plant018Squash, battle: RepeaterShotContext, rules: Dictionary[String, Dictionary]) -> void:
	var attack := AdventureSquashAttack.new() # 原生退场不提前终止已开始的一次攻击。
	attack._capture(plant, battle, rules)
	var lane: int = plant.lane # 普通压砸保留原生同行限制。
	var at: Vector2 = plant.global_position # 实际落点可能与原种植格不同。
	var cell: PlantCell = battle.board.cell_at_ground_point(at, lane) # 盘外落点由真实格距换算。
	var targets: Array[Character000Base] = CombatExplosion.plant_blast_targets(
		plant.area_2d_squash_attack.get_overlapping_areas(), lane, 0, attack._statuses)
	var source: WeakRef = weakref(plant) # 分帧后原株可能已完成落水或死亡。
	battle.game.bombs.add_child(attack)
	plant.signal_character_death.connect(attack._record_native_removal.bind(source), CONNECT_ONE_SHOT)
	attack._run_native(source, targets, cell, at, lane)

## 原株 [param source] 的正常退场可交给已排队的攻击，铲除时不复制。
func _record_native_removal(source: WeakRef) -> void:
	var plant := source.get_ref() as Plant018Squash # 不借引用延长场上实体寿命。
	_native_consumed = is_instance_valid(plant) and plant.is_can_death_language

## 完成源自 [param source] 的 [param targets] 单次落地和 [param cell]、[param at]、[param lane] 的后续效果。
func _run_native(source: WeakRef, targets: Array[Character000Base], cell: PlantCell, at: Vector2, lane: int) -> void:
	await _land(targets, cell, at, lane, 1.0, -1)
	await _after_attack(cell, at, lane)
	if _needs_retry():
		var plant := source.get_ref() as Plant018Squash # 原生退场若尚未发生，由原株在退场时再通知。
		if is_instance_valid(plant) and not plant.is_death:
			plant.arm_resentment(_battle)
		elif _native_consumed:
			enqueue_retry(_battle, _home_id, _profile, _imitater_material)
	queue_free()

## 由 [param plant] 的原生起跳 cue 开始窝瓜王，沿用 [param battle] 与 [param rules]。
static func start_king(plant: Plant018Squash, battle: RepeaterShotContext,
		rules: Dictionary[String, Dictionary]) -> void:
	var attack := AdventureSquashAttack.new() # 母株消耗后，结算由当前战场保留。
	attack._capture(plant, battle, rules)
	var source := plant.body.get_node(^"BodyCorrect") as Node2D # 只取窝瓜原有姿态和贴图，不复制受击组件。
	attack._body_template = source.duplicate(0) as Node2D
	attack._body_template.transform = plant.global_transform.affine_inverse() * source.global_transform
	attack._body_template.hide()
	attack._shadow_texture = plant.shadow.texture
	battle.game.bombs.add_child(attack)
	attack.add_child(attack._body_template)
	attack._run_king.call_deferred()

## 冻结 [param plant] 的原格、完整配方和攻击数值，之后使用 [param battle] 和 [param rules]。
func _capture(plant: Plant018Squash, battle: RepeaterShotContext, rules: Dictionary[String, Dictionary]) -> void:
	_battle = battle
	_rules = rules
	_home_id = plant.plant_cell.cell_id
	_profile = plant.plant_spawn_profile
	_imitater_material = plant.is_imitater_material
	_base_damage = plant.attack_value
	_damage = plant.promotion_damage(_base_damage)
	_statuses = plant.can_attack_zombie_status
	_mask = plant.area_2d_squash_attack.collision_mask
	_leader_damage = plant.promotion_damage(int(rules.get("squash_leader", {}).get("damage", 0)))

## [param delta] 为活动战斗秒，供本轮震撼叠加及移动地格的落点同步。
func _physics_process(delta: float) -> void:
	if not _battle.is_active():
		queue_free()
		return
	_elapsed += delta
	if is_instance_valid(_fall_root) and is_instance_valid(_fall_cell):
		_fall_root.global_position = _fall_cell.get_spawn_global_position()

## 窝瓜王等待每一次真实落地后再选下一格；整轮结束只施放一次四转效果。
func _run_king() -> void:
	var rule: Dictionary = _rules["squash_king"] # 每次半伤，Boss 的固定上限源自原始压砸。
	var cap: int = floori(_base_damage * float(rule["boss_cap"])) # 每枚落地独立封顶。
	var fraction: float = rule["fraction"] # 一次小窝瓜与原始整次攻击的比例。
	for index: int in range(int(rule["count"])): # 每次下降有独立姿态、伤害和出场间隔。
		var home: PlantCell = _battle.board.cell_by_id(_home_id) if _battle.is_active() else null # 每次读当前仍在场的原格。
		if home == null:
			queue_free()
			return
		var choices: Array[PlantCell] = _square(home, home.get_spawn_global_position(), home.combat_lane, 1) # 只选实际存在的相邻格。
		var cell: PlantCell = _choose_drop(choices) # 使用这一次出场时仍存活的敌人。
		if cell == null:
			break
		await _show_fall(cell, index).finished
		if not _battle.is_active():
			queue_free()
			return
		if is_instance_valid(cell) and _battle.board.cell_by_id(cell.cell_id) == cell:
			var landing: Vector2 = cell.get_spawn_global_position() # 支持落下期间会移动的格子。
			var targets: Array[Character000Base] = _grid_targets([cell], _statuses, true) # 落地时冻结这一下的候选。
			_show_impact(cell)
			_fall_root = null
			_fall_cell = null
			await _land(targets, cell, landing, cell.combat_lane, fraction, cap)
		else:
			_fall_root.queue_free()
			_fall_root = null
			_fall_cell = null
		await get_tree().create_timer(DROP_GAP, false, true).timeout
	var home: PlantCell = _battle.board.cell_by_id(_home_id) if _battle.is_active() else null # 四转以母株的召唤中心为准。
	if home != null:
		await _after_attack(home, home.get_spawn_global_position(), home.combat_lane)
		if _needs_retry():
			enqueue_retry(_battle, _home_id, _profile, _imitater_material)
	await get_tree().create_timer(0.19, false, true).timeout # 保留最后一次回弹和消散。
	queue_free()

## 从 [param choices] 优先挑选有敌人的格，重复命中仅在没有其他合适目标时发生。
func _choose_drop(choices: Array[PlantCell]) -> PlantCell:
	var occupied: Array[PlantCell] = [] # 当前实敌的地块，排除频繁投向上一只已经死亡的僵尸。
	for target: Character000Base in _grid_targets(choices, _statuses, true): # 只查九宫格涉及的行和实际受击区域。
		var cell: PlantCell # 普通僵尸按脚点，跨行僵王按受击中心。
		if target is Zombie000Base:
			cell = BoardQueries.ground_cell_from(_battle.board, target.global_position, target.lane, choices)
		else:
			cell = _special_target_cell(target, choices)
		if cell != null and not occupied.has(cell):
			occupied.append(cell)
	var pool: Array[PlantCell] = occupied if not occupied.is_empty() else choices # 无目标才用真正的随机格。
	var unused: Array[PlantCell] = [] # 相同条件下分散落点。
	for cell: PlantCell in pool:
		if not _used_cells.has(cell.cell_id):
			unused.append(cell)
	if not unused.is_empty():
		pool = unused
	if pool.is_empty():
		return null
	var chosen: PlantCell = pool.pick_random() # 随机只在合格优先级中发生。
	_used_cells[chosen.cell_id] = true
	return chosen

## [param target] 是跨格僵王或设施；在 [param choices] 内以能真正砸中的格子为准。
func _special_target_cell(target: Character000Base, choices: Array[PlantCell]) -> PlantCell:
	var preferred: PlantCell = _battle.board.nearest_cell(target.global_position, target.lane) # 脚点靠近的格子优先，受击框可以离脚点很远。
	if choices.has(preferred) and _special_targets([preferred], _statuses).has(target):
		return preferred
	for cell: PlantCell in choices: # 只在少数跨行受击框上检查非首选格。
		if cell != preferred and _special_targets([cell], _statuses).has(target):
			return cell
	return null

## 在 [param cell] 为 [param index] 号小窝瓜生成一段下落。返回由战场暂停控制的补间。
func _show_fall(cell: PlantCell, index: int) -> Tween:
	_fall_cell = cell
	_fall_root = Node2D.new()
	_fall_root.z_index = 45
	add_child(_fall_root)
	_fall_root.global_position = cell.get_spawn_global_position()
	var shadow_sprite := Sprite2D.new() # 原影子从小到大，与本次落点保持对齐。
	shadow_sprite.texture = _shadow_texture
	shadow_sprite.scale = Vector2(0.56, 0.6)
	shadow_sprite.modulate.a = 0.22
	_fall_root.add_child(shadow_sprite)
	var air := Node2D.new() # 将下落位移包在原生立绘之外，保留每个部件的相对姿态。
	air.name = &"Pose"
	air.position = Vector2(16.0 if index % 2 == 0 else -16.0, -112.0 - float(index % 3) * 10.0)
	air.scale = Vector2(0.93, 1.06)
	_fall_root.add_child(air)
	var model := _body_template.duplicate(0) as Node2D # 仅在这枚窝瓜开始下落时实例化。
	model.show()
	air.add_child(model)
	var tween: Tween = _fall_root.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel(true) # 下落末段加速。
	tween.tween_property(air, "position", Vector2.ZERO, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(shadow_sprite, "scale", Vector2(0.92, 0.78), FALL_TIME)
	tween.tween_property(shadow_sprite, "modulate:a", 0.46, FALL_TIME)
	return tween

## 在 [param cell] 播放原压砸音效、弹性压扁和水花，原图随后自行淡出。
func _show_impact(cell: PlantCell) -> void:
	var anchor: Node2D = _fall_root # 这一枚结束后仍可回弹，下一枚拥有独立载体。
	anchor.global_position = cell.get_spawn_global_position()
	var air := anchor.get_node(^"Pose") as Node2D # 只有表现，攻击恰好在开始压扁前完成。
	var tween: Tween = anchor.create_tween() # 已经落地的少量表现可与下一枚开始下落短暂重叠。
	tween.tween_property(air, "scale", Vector2(1.24, 0.70), 0.045)
	tween.tween_property(air, "scale", Vector2(0.98, 0.92), 0.075)
	tween.parallel().tween_property(anchor, "modulate:a", 0.0, 0.13)
	tween.tween_callback(anchor.queue_free)
	SoundManager.play_character_SFX(&"gargantuar_thump")
	if cell.get_spawn_terrain_type() == CharacterRegistry.ZombieRowType.Pool:
		var splash := SceneRegistry.SPLASH.instantiate() as Node2D # 原泳池落地动画随战场容器释放。
		_battle.game.bombs.add_child(splash)
		splash.global_position = cell.get_spawn_global_position()
		splash.z_index = anchor.z_index

## [param targets] 受到这次落地。[param cell]、[param at] 和 [param lane] 定位震撼。
## [param fraction] 为砸击倍率，[param cap] 为该次对僵王的伤害上限。
func _land(targets: Array[Character000Base], cell: PlantCell, at: Vector2, lane: int, fraction: float, cap: int) -> void:
	var contacted: bool = await _damage_targets(targets, roundi(_damage * fraction), cap, false) # 多碰撞框只消费一次原生命中。
	if contacted and _rules.has("squash_shock") and _battle.is_active():
		await _apply_control(cell, at, lane, _rules["squash_shock"], false)

## 在 [param cell] 或 [param at] 对应的 [param lane] 完成整轮攻击后的四转效果。
func _after_attack(cell: PlantCell, at: Vector2, lane: int) -> void:
	if not _battle.is_active():
		return
	if _rules.has("squash_quake"):
		await _apply_control(cell, at, lane, _rules["squash_quake"], true)
	if _rules.has("squash_leader"):
		var rule: Dictionary = _rules["squash_leader"] # 排名伤害可提高普通爆炸，Boss 封顶基于原始 1000。
		var cells: Array[PlantCell] = _square(cell, at, lane, int(rule["radius"]))
		CombatExplosion.emit_visuals(_battle.game.bombs, load(LEADER_FX) as CombatExplosionProfile, at)
		await _damage_targets(_grid_targets(cells, CONTROL_STATUSES, true), _leader_damage,
			floori(float(rule["damage"]) * float(rule["boss_cap"])), true)

## 对 [param targets] 启动 [param damage] 点压砸或 [param blast] 爆炸，[param boss_cap] 为 -1 时保留原版伤害。
## 返回普通僵尸受击或 Boss 有效受击是否发生；真实死者另外由生命路由记账。
func _damage_targets(targets: Array[Character000Base], damage: int, boss_cap: int, blast: bool) -> bool:
	var scope := CombatHitScope.new() # 一次压砸可命中多个目标，转伤保护者只结算一次。
	scope.before_death = _remember_death
	var context: PlantAttackContext = _battle.attack_context # 出战卡属性先于派生伤害的 Boss 限制。
	var contacted: bool = false # 设施销毁不触发震撼或阻止愤恨。
	var started: int = Time.get_ticks_usec() # 每段共享真实时间预算和单帧工作数量。
	var processed: int = 0 # 包含失效候选，避免异常密集的空转。
	for reference: Variant in targets: # 前一击可能已经令后续目标死亡。
		if _work_spent(started, processed):
			await _next_work_frame()
			started = Time.get_ticks_usec()
			processed = 0
		processed += 1
		if not _battle.is_active():
			break
		if not is_instance_valid(reference):
			continue
		var target: Character000Base = reference # 重新核对实际碰撞目标。
		if not CombatExplosion.can_hit_plant_blast(target, -1, -1, CONTROL_STATUSES if blast else _statuses):
			continue
		_death_point = Vector2.INF
		var amount: int = context.modify_damage(damage, target) if context != null else damage # 逐个实际目标应用原出战修正。
		var armor: float = context.armor_multiplier if context != null else 1.0 # 仅影响防具，不改变身体伤害类型。
		var casualty: Character000Base # 本次击杀者可能是保护者。
		if target is Zombie000Base:
			contacted = true
			casualty = target.be_bomb(amount, true, armor, scope) if blast else target.be_squash(amount, armor, scope)
		elif target is ZB000Base:
			var receipt: Dictionary = {} # 关闭受击窗口、全免或无伤害都不算有效 Boss 命中。
			if boss_cap >= 0:
				amount = mini(amount, boss_cap)
			if blast:
				amount = target.ash_damage_received(amount)
			target.be_attacked_bullet(amount, BulletRegistry.AttackMode.Penetration, false, false, 0, -1, receipt, scope)
			var hit: bool = int(receipt.get("actual_loss", 0)) > 0 # 压砸接触无敌窗口不会误判成功。
			contacted = contacted or hit
			_boss_hit = _boss_hit or hit
			casualty = receipt.get("casualty") as Character000Base
		else:
			target.be_attacked_bullet(amount, BulletRegistry.AttackMode.Penetration, false, false)
		if context != null:
			context.resolve_kill(casualty)
		_credit(casualty)
	return contacted

## 从实际承伤的 [param target] 保存扣血前的尸体落点。
func _remember_death(target: Character000Base) -> void:
	_death_point = target.global_position

## 为本轮首次死亡的 [param casualty] 兑现一次廉价作物奖励。
func _credit(casualty: Character000Base) -> void:
	if not is_instance_valid(casualty) or not casualty.is_death:
		return
	var id: int = casualty.get_instance_id() # 身份去重跨越同轮六次压砸及终结爆炸。
	if _credited.has(id):
		return
	_credited[id] = true
	if _rules.has("squash_cheap") and _battle.is_same_battle():
		var at: Vector2 = _death_point if _death_point.is_finite() else casualty.global_position # 原生位移不会移动击杀掉落。
		BattleSunDrop.spawn(_battle.game, at, int(_rules["squash_cheap"]["sun"]))

## [param rule] 在 [param cell]、[param at] 与 [param lane] 定位范围。[param quake] 为真时叠加本轮剩余震撼。
func _apply_control(cell: PlantCell, at: Vector2, lane: int, rule: Dictionary, quake: bool) -> void:
	var cells: Array[PlantCell] = _square(cell, at, lane, int(rule["radius"])) # 震撼和地震各自读取真实棋盘范围。
	var started: int = Time.get_ticks_usec() # 眩晕计时器和位移也按相同预算分批启动。
	var processed: int = 0 # 消费本批目标数，进入后续物理帧时重置。
	for reference: Variant in _grid_targets(cells, CONTROL_STATUSES, false): # Boss 不适用普通僵尸控制。
		if _work_spent(started, processed):
			await _next_work_frame()
			started = Time.get_ticks_usec()
			processed = 0
		processed += 1
		if not _battle.is_active():
			return
		if not is_instance_valid(reference):
			continue
		var zombie := reference as Zombie000Base # 只在筛选后进入原生位移和眩晕。
		if zombie == null or zombie.is_death or zombie.retiring_from_battle \
				or zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder:
			continue
		var id: int = zombie.get_instance_id() # 记录本轮的震撼，不改动其他来源的计时器。
		var duration: float = rule["stun"] # 独立效果的持续秒数。
		var remaining: float = maxf(0.0, float(_shock_until.get(id, 0.0)) - _elapsed) if quake else 0.0 # 只附加本轮仍有效的震撼秒数。
		if not AdventurePlantNegativeEffects.apply(zombie, AdventurePlantNegativeEffects.Kind.STUN, 0, duration + remaining):
			continue
		var pitch: Vector2 = _battle.pitch_at(zombie.global_position, zombie.lane) # 按目标的位置换算横向格宽。
		zombie.move_component.apply_forced_displacement(Vector2(pitch.x * float(rule["distance"]), 0.0),
			0.37, maxf(18.0, pitch.y * 0.44))
		if not quake:
			_shock_until[id] = _elapsed + duration

## 等到下一物理步。菜单暂停时用会随战场暂停的时钟等待，避免续批在暂停中扣血。
func _next_work_frame() -> void:
	await get_tree().physics_frame
	if get_tree().paused and _battle.is_active():
		await get_tree().create_timer(0.001, false, true).timeout

## [param started] 为本段起点（微秒），[param processed] 为当前已处理项；首项总能执行。
static func _work_spent(started: int, processed: int) -> bool:
	return processed >= WORK_ITEMS_PER_FRAME or (processed > 0 and Time.get_ticks_usec() - started >= WORK_BUDGET_USEC)

## 从 [param center] 获取同平台的正方形邻格。盘外以 [param at] 与 [param lane] 保留落点。
func _square(center: PlantCell, at: Vector2, lane: int, radius: int) -> Array[PlantCell]:
	var cells: Array[PlantCell] = [] # 只包含实际存在并符合行列的地块。
	if is_instance_valid(center):
		for cell: PlantCell in _battle.board.neighbors(center, radius): # 显式邻接也必须落在技能要求的行列差内。
			if cell.board_definition.surface_id == center.board_definition.surface_id \
					and absi(cell.row_col.x - center.row_col.x) <= radius and absi(cell.row_col.y - center.row_col.y) <= radius:
				cells.append(cell)
	else:
		var width: float = _battle.pitch_at(at, lane).x # 不将板外的中心吸附到过远的内场。
		for cell: PlantCell in _battle.board.cells():
			if absi(cell.combat_lane - lane) <= radius and absf(cell.get_spawn_global_position().x - at.x) <= (radius + 0.5) * width:
				cells.append(cell)
	return cells

## 只在 [param cells] 对应的行收集 [param statuses] 中的普通敌人。
## [param special] 允许额外查询僵王及设施的真实碰撞框。
func _grid_targets(cells: Array[PlantCell], statuses: int, special: bool) -> Array[Character000Base]:
	var targets: Array[Character000Base] = [] # 随后结算时再检查存活，遍历中不修改登记表。
	var rows: Dictionary[int, Array] = {} # 每行只走一次，棋盘缺格用原生精确脚点判断。
	for cell: PlantCell in cells:
		if not rows.has(cell.combat_lane):
			rows[cell.combat_lane] = [] as Array[PlantCell]
		rows[cell.combat_lane].append(cell)
	var manager: ZombieManager = _battle.game.zombie_manager # 只读真实的敌方行登记。
	for lane: int in rows:
		if lane < 0 or lane >= manager.all_zombies_2d.size():
			continue
		for zombie: Zombie000Base in manager.all_zombies_2d[lane]: # 已魅惑者不会进入有效候选。
			if CombatExplosion.can_hit_plant_blast(zombie, lane, 0, statuses) \
					and BoardQueries.ground_cell_from(_battle.board, zombie.global_position, lane, rows[lane]) != null:
				targets.append(zombie)
	if special:
		targets.append_array(_special_targets(cells, statuses))
	return targets

## 用 [param cells] 和 [param statuses] 取得实际重叠的跨格僵王与设施。
func _special_targets(cells: Array[PlantCell], statuses: int) -> Array[Character000Base]:
	var targets: Array[Character000Base] = [] # 普通僵尸由脚点索引收集。
	var game: MainGameManager = _battle.game # 没有特殊目标时不做一次覆盖许多普通僵尸的物理查询。
	if cells.is_empty() or (game.zombie_manager.get_living_bosses().is_empty()
			and game.get_tree().get_nodes_in_group(EnemyStructureBase.GROUP).is_empty()):
		return targets
	var rect: Rect2 = BoardQueries.bounds(cells) # 使用世界中的受击几何，不依靠僵王行号。
	_rect.size = rect.size
	var hits: Array[Area2D] = CombatExplosion.query_shape(game.get_world_2d().direct_space_state, _rect,
		Transform2D(0.0, rect.get_center()), _mask, true)
	for target: Character000Base in CombatExplosion.plant_blast_targets(hits, -1, -1, statuses):
		if not target is Zombie000Base:
			targets.append(target)
	return targets

## 一次整轮没有真实击杀、也没有有效 Boss 命中时才可以生成替身。
func _needs_retry() -> bool:
	return _rules.has("squash_resentment") and _credited.is_empty() and not _boss_hit and _battle.is_active()

## 在 [param battle] 安排一个沿用 [param profile] 的替身。
## [param home_id] 必须是原格，[param material] 保留模仿者本体的表现。
static func enqueue_retry(battle: RepeaterShotContext, home_id: StringName, profile: PlantSpawnProfile, material: bool) -> void:
	if not battle.is_active() or profile == null:
		return
	battle.game.zombie_manager.periodic_updates.enqueue_battle_spawn(_spawn_retry.bind(battle, home_id, profile, material))

## 在 [param battle] 中重查 [param home_id] 的地形和占用，并按 [param profile] 与 [param material] 生成。
static func _spawn_retry(battle: RepeaterShotContext, home_id: StringName, profile: PlantSpawnProfile, material: bool) -> void:
	if not battle.is_active():
		return
	var home: PlantCell = battle.board.cell_by_id(home_id) # 技能生成仍遵守真实摆放事务，不驱逐他人或穿越换场。
	if is_instance_valid(home) and not home.is_queued_for_deletion():
		home.create_plant(CharacterRegistry.PlantType.P018Squash, false, true, material, false,
			profile, PlantCell.PlacementOrigin.Spawned)
