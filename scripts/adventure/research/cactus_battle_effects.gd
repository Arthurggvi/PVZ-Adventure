## 仙人掌的战斗局部事件。每场仅一个调度器，状态和完整伤害独立于视觉预算。
extends Node2D

## 场景内唯一运行时节点。
const NODE_NAME := &"CactusBattleEffects"
## 复用出战芦苇的帧动画与池。实际放电前不加载源素材。
const REED_PATH := "res://scripts/character/plant/lightning_reed_effect_pool.gd"
## 芦苇原电弧横向长度，动画延续到真实受击点。
const NATIVE_BOLT_LENGTH: float = 104.0
## 芦苇原始标准电击音色，密集时在战场中合并播放。
const SHOCK_AUDIO := "res://assets/adventure/plants/lightning_reed/sfx/fire.tres"
## 实录雷击的起裂与低频余响，首次可见落雷时载入。
const THUNDER_AUDIO := "res://resources/audio/sfx/cactus_thunder_strike.wav"
## 每只受创僵尸的附着尖刺。
const Quills = preload("res://scripts/adventure/research/cactus_wound_quills.gd")
## 整场集中绘制的枪口、扇面和惊雷叠层提示。
const Layer = preload("res://scripts/adventure/research/cactus_effect_layer.gd")
## 落雷主干和同帧视口高闪，共用一套本场画布。
const ThunderStrike = preload("res://scripts/adventure/research/cactus_thunder_strike.gd")
## 真实站位和受击点的局部查询。
const TargetGrid = preload("res://scripts/adventure/research/cactus_target_grid.gd")
## 同一目标两次感电启动之间需要的游戏秒数。
const SHOCK_COOLDOWN: float = 0.3
## 各段电弧沿近似芦苇的错峰节奏显示，单位为游戏秒。
const HOP_GAP: float = 0.066
## 感电不算起点，只打之后三位敌人。
const HOPS: int = 3
## 每跳固定为芦苇基础伤害。
const SHOCK_DAMAGE: int = 10
## 凑够五层才兑现一笔命中格子内所有适用敌人的伤害。
const THUNDER_LAYERS: int = 5
## 每次对实际落点格发动的原始伤害值。
const THUNDER_DAMAGE: int = 1800
## 亡语圈覆盖360度，射程由尖刺本身限制。
const BLOOM_SHOTS: int = 12
## 每个物理步允许推进的电链数，超出预算进入下一步。
const CHAIN_BUDGET: int = 48
## 每个物理步允许兑现的亡语和落雷总数。
const AREA_BUDGET: int = 8
## 每步最多显示三段原生电弧动画，多余的跳跃保留战斗结算。
const REED_VISUAL_BUDGET: int = 3
## 合并持续提示音的间隔，单位为游戏秒。
const AUDIO_GAP: float = 0.11
## 共享的空中/地面状态位。
const State = Zombie000Base.E_BeAttackStatusZombie
## 统一负面效果门面的类型。
const Kind = AdventurePlantNegativeEffects.Kind

## 仅当敌人真正拥有感电、惊雷或亡语标记时分配。
class Marks:
	## 最近施加感电的攻击，离开原战局会失效。
	var shock: RepeaterShotContext
	## 下次感电允许触发的战斗时刻。
	var shock_ready: float = 0.0
	## 这只敌人首次被泛滥命中时的来源。
	var flood: RepeaterShotContext
	## 本次死亡只能排一次亡语。
	var bloomed: bool = false
	## 同一敌人跨射击者累积的惊雷点数。
	var thunder: int = 0
	## 惊雷的轮次身份变化时清空未结算层数。
	var thunder_shot: RepeaterShotContext

## 一道已触发电链，以有界的次序记录跳跃。
class Chain:
	## 原本的感电标记快照。
	var shot: RepeaterShotContext
	## 上一跳的原生受击形状中心。
	var point: Vector2
	## 上一跳在真实棋盘上的脚点。
	var foot: Vector2
	## 上一跳所在的逻辑行。
	var lane: int
	## 当前段最早可以发生的时间。
	var due: float
	## 逻辑起点与已命中的接触身份。
	var visited := PackedInt64Array()
	## 转伤后的实际承伤者也不得被同一条链重复命中。
	var scope := CombatHitScope.new()

## 已冻结的亡语或惊雷触发；战斗命中回调中只写该事件。
class AreaEvent:
	## 原标记与最终伤害归属。
	var shot: RepeaterShotContext
	## 惊雷有格子时优先使用当前位置；亡语沿用死者落点。
	var cell: PlantCell
	## 亡语发射时所使用的死者世界位置。
	var position: Vector2
	## 亡语弹继承死者的逻辑行。
	var lane: int
	## 亡语弹实际可以命中的僵尸状态位。
	var states: int
	## 冻结的死者创伤层数，由一整圈弹体共用。
	var wounds: int

## 唯一的正式战场，由该节点父级共同释放。
var _game: MainGameManager
## 原生战斗时钟；暂停期间不统计冷却。
var _clock: float = 0.0
## 角色只按实例号登记，在离树事件中摘除。
var _marks: Dictionary[int, Marks] = {}
## 已感电角色的数量，用于在最后一个标记退出后停止物理回调。
var _shocked_count: int = 0
## 防止某条感电链自己的伤害再次递归激发电链。
var _inside_shock: bool = false
## 循环推进的电链队列，使用游标避免反复移动长数组。
var _chains: Array[Chain] = []
## 电链队列中下一个尚未检查的事件下标。
var _chain_head: int = 0
## 等待兑现的亡语和落雷，使用同样的有界推进。
var _areas: Array[AreaEvent] = []
## 下一笔应该结算的区域事件下标。
var _area_head: int = 0
## 局部候选缓存只在该步真的处理感电时刷新。
var _grid := TargetGrid.new()
## 头less验证与实际图形使用同一玩法，只有后者绘制特效。
var _draw_effects: bool
## 首次发射后按需建立的集中绘制层。
var _layer: Layer
## 本物理步剩下的芦苇动画显示预算。
var _visible_bolts: int = 0
## 电弧短音的下次允许时间。
var _audio_ready: float = 0.0
## 感电沿用芦苇音色，只在第一次播放时加载。
var _electric_audio: AudioStream
## 本场第一道可见惊雷初始化的全高绘制层。
var _thunder_strike: ThunderStrike
## 与落雷主效果同步播放的实录声。
var _thunder_audio: AudioStream
## 最近一次实际处理的本地结算耗时，供密集场景回归采样。
var last_resolution_usec: int = 0

## 保存本节点所处的真实 [param game]。由首次射出的原生仙人掌挂到该战场。
func _init(game: MainGameManager) -> void:
	name = NODE_NAME
	_game = game

## 空闲场景无需物理计时；无图形环境不创建绘制资源。
func _ready() -> void:
	_draw_effects = DisplayServer.get_name() != "headless"
	if _draw_effects:
		_layer = Layer.new()
		add_child(_layer)
	set_physics_process(false)

## 应用通过正式门面的 [param kind]，从 [param shot] 继承原战局。[param amount] 为需要叠加的层数。
func apply_status(target: Zombie000Base, kind: Kind, amount: int, shot: RepeaterShotContext) -> bool:
	if shot == null or not shot.is_active() or shot.game != _game or target.is_death:
		return false
	if kind == Kind.CACTUS_WOUND:
		_add_wound(target, amount)
		return true
	var id: int = target.get_instance_id() # 同一目标来自多株的状态仍共用。
	var state: Marks = _marks_for(target, id) # 第一条非创伤标记按需分配。
	if kind == Kind.CACTUS_SHOCK:
		if state.shock == null:
			_shocked_count += 1
			target.hp_component.combat_health_lost.connect(_on_shocked_loss.bind(id))
			set_physics_process(true)
			_flash(Layer.Style.CHARGE, TargetGrid.impact_point(target), Vector2.RIGHT, Color("7fd9ff"))
		state.shock = shot
	else:
		_add_thunder(target, state, shot, amount)
	return true

## 追加 [param target] 的整数创伤，共用 [param amount] 对应的可见上限。
func _add_wound(target: Zombie000Base, amount: int) -> void:
	var hp: HpComponent = target.hp_component # 不在每次受击时搬运视觉状态。
	var before: int = hp.cactus_wound_stacks # 达到视觉上限后无须再写画布。
	hp.cactus_wound_stacks += amount
	if not _draw_effects or before >= Quills.MAX_SPIKES * Quills.STACKS_PER_SPIKE:
		return
	var quills := target.get_node_or_null(^"CactusWoundQuills") as Quills # 每只受伤僵尸最多一个容器。
	if quills == null:
		quills = Quills.new()
		quills.name = &"CactusWoundQuills"
		quills.setup(target)
		target.add_child(quills)
	quills.show_stacks(hp.cactus_wound_stacks)

## 记录一次 [param target] 与 [param shot] 的泛滥命中。若本击已经致死，同样可以立刻排队。
func mark_flood(target: Zombie000Base, shot: RepeaterShotContext) -> void:
	if shot == null or not shot.is_active() or not is_instance_valid(target) or target.retiring_from_battle:
		return
	var id: int = target.get_instance_id() # 一只僵尸一轮死亡最多开放一次。
	var state: Marks = _marks_for(target, id) # 与本目标的其他状态共用记录。
	if state.flood == null and not target.is_death:
		target.hp_component.before_death.connect(_on_flood_death.bind(id), CONNECT_ONE_SHOT)
	if state.flood == null or not state.flood.is_same_battle():
		state.flood = shot
	if target.is_death:
		_queue_bloom(target, state)

## 取或创建 [param target] 的 [param id] 对应状态。
func _marks_for(target: Zombie000Base, id: int) -> Marks:
	var state: Marks = _marks.get(id) # 已标记者不重复连接信号。
	if state == null:
		state = Marks.new()
		_marks[id] = state
		target.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)
	return state

## [param id] 离开战场后移除角色状态；已经开始的攻击仍可完成。
func _forget(id: int) -> void:
	var state: Marks = _marks.get(id) # 场景退出过程允许先清掉运行时。
	if state != null and state.shock != null:
		_shocked_count -= 1
	_marks.erase(id)

## [param loss] 是原生确认的实际损失；每个 [param id] 按自己的冷却触发电链。
func _on_shocked_loss(loss: int, id: int) -> void:
	if loss <= 0 or _inside_shock or not is_instance_id_valid(id):
		return
	var state: Marks = _marks.get(id) # 目标遭到致死一击也可从最后坐标放电。
	if state == null or state.shock == null or _clock + 0.000001 < state.shock_ready or not state.shock.is_active():
		return
	var target := instance_from_id(id) as Zombie000Base # 只在正式僵尸离树之前取一次起点。
	if target == null or target.retiring_from_battle or target.is_hypno:
		return
	state.shock_ready = _clock + SHOCK_COOLDOWN
	var chain := Chain.new() # 起点不吃自己发出的电链。
	chain.shot = state.shock
	chain.point = TargetGrid.impact_point(target)
	chain.foot = target.global_position
	chain.lane = target.lane
	chain.due = _clock
	chain.visited.append(id)
	chain.scope.try_claim(target)
	_chains.append(chain)

## [param _cause] 沿用原生命观察口；[param id] 是已经被泛滥命中过的目标。
func _on_flood_death(_cause: CombatHitScope.DeathCause, id: int) -> void:
	if is_instance_id_valid(id):
		var target := instance_from_id(id) as Zombie000Base # 此时伤害尚未卸载死者的装备和部件。
		var state: Marks = _marks.get(id) # 领取第一次击杀的亡语资格。
		if target != null and state != null:
			_queue_bloom(target, state)

## 捕获 [param target] 与 [param state] 的死亡瞬间，等下一步再创建具有碰撞的弹体。
func _queue_bloom(target: Zombie000Base, state: Marks) -> void:
	if state.bloomed or target.retiring_from_battle or target.is_hypno or not state.flood.is_active():
		return
	state.bloomed = true
	var wave := AreaEvent.new() # 亡语保留最后的落点、层数与出战倍率。
	wave.shot = state.flood
	wave.wounds = target.hp_component.cactus_wound_stacks
	wave.lane = target.lane
	wave.states = State.IsNorm | State.IsJump | (State.IsSky if target.curr_be_attack_status == State.IsSky else 0)
	wave.position = TargetGrid.impact_point(target) if target.curr_be_attack_status == State.IsSky else target.global_position + Vector2(0.0, -27.0)
	_areas.append(wave)
	set_physics_process(true)

## [param target] 已被本发尖刺杀死。只兑现 [param shot] 的最后一层，尸体不会保留新状态。
func finish_thunder_on_lethal_hit(target: Zombie000Base, shot: RepeaterShotContext) -> void:
	var state: Marks = _marks.get(target.get_instance_id()) # 只有这次命中之前真实积下四层才能落雷。
	if state != null and state.thunder == THUNDER_LAYERS - 1 and state.thunder_shot.is_same_battle() \
			and shot.is_active() and not target.is_hypno and not target.retiring_from_battle:
		_add_thunder(target, state, shot, 1)

## 为 [param target] 的 [param state] 叠加 [param amount] 层惊雷，达到阈值时按实际占格兑现。
func _add_thunder(target: Zombie000Base, state: Marks, shot: RepeaterShotContext, amount: int) -> void:
	if state.thunder_shot == null or not state.thunder_shot.is_same_battle():
		state.thunder = 0
	state.thunder_shot = shot
	state.thunder += amount
	if state.thunder < THUNDER_LAYERS:
		if _draw_effects:
			_flash(Layer.Style.THUNDER_MARK, TargetGrid.impact_point(target),
				Vector2(state.thunder, 0), Color("ffe18b"))
		return
	state.thunder -= THUNDER_LAYERS
	var cell: PlantCell = _game.board.cell_at_ground_point(target.global_position, target.lane) # 盘外或洞格没有落雷面。
	if not is_instance_valid(cell):
		return
	var storm := AreaEvent.new() # 只保存权威格子引用，运动平台仍在当前落点。
	storm.shot = shot
	storm.cell = cell
	_areas.append(storm)
	set_physics_process(true)

## [param delta] 推进原生战斗秒数；每个物理步只处理固定数量的重型事件。
func _physics_process(delta: float) -> void:
	_clock += delta
	if _areas.is_empty() and _chains.is_empty():
		last_resolution_usec = 0
		if _shocked_count <= 0:
			set_physics_process(false)
		return
	_visible_bolts = REED_VISUAL_BUDGET
	var started: int = Time.get_ticks_usec() # 采样真实队列工作，不计休眠时间。
	for _event: int in range(mini(AREA_BUDGET, _areas.size() - _area_head)): # 同步亡语产生的后续事件下步再加入。
		var area: AreaEvent = _areas[_area_head] # 顺序兑现视觉与伤害。
		_areas[_area_head] = null
		_area_head += 1
		if not area.shot.is_active():
			continue
		if is_instance_valid(area.cell):
			_strike_cell(area)
		elif area.states != 0:
			_bloom(area)
	for _step: int in range(mini(CHAIN_BUDGET, _chains.size() - _chain_head)): # 不扫描尚未进入预算的尾部。
		var chain: Chain = _chains[_chain_head] # 每次至多推进一跳，再送回轮转队尾。
		_chains[_chain_head] = null
		_chain_head += 1
		if not chain.shot.is_active():
			continue
		if chain.due > _clock or _advance_chain(chain):
			_chains.append(chain)
	if _area_head > 0 and (_area_head >= 128 or _area_head == _areas.size()):
		_areas = _areas.slice(_area_head)
		_area_head = 0
	if _chain_head > 0 and (_chain_head >= 128 or _chain_head == _chains.size()):
		_chains = _chains.slice(_chain_head)
		_chain_head = 0
	last_resolution_usec = Time.get_ticks_usec() - started
	if _shocked_count <= 0 and _areas.is_empty() and _chains.is_empty():
		set_physics_process(false)

## 处理 [param chain] 下一次寻找并命中最近邻。返回是否仍需要放出下一段。
func _advance_chain(chain: Chain) -> bool:
	_grid.refresh(_game)
	var pitch: Vector2 = chain.shot.cell_pitch.max(Vector2.ONE) # 横竖距离参考施加者的实际棋盘格距。
	var target: Zombie000Base = _grid.nearest(chain.foot.x, chain.lane, pitch, chain.visited) # 只从当前局部邻域选一只。
	if target == null:
		return false
	var point: Vector2 = TargetGrid.impact_point(target) # 即使本击致死，下一跳仍从这个位置发出。
	chain.visited.append(target.get_instance_id())
	_show_arc(chain.point, point)
	chain.point = point
	chain.foot = target.global_position
	chain.lane = target.lane
	chain.due = _clock + HOP_GAP
	_inside_shock = true
	target.be_attacked_bullet(SHOCK_DAMAGE, BulletRegistry.AttackMode.Real, true, false, 0, -1, null, chain.scope)
	_inside_shock = false
	return chain.visited.size() <= HOPS

## 对 [param area] 所登记的真实脚下格施加一次独立落雷。先保存这一格的快照。
func _strike_cell(area: AreaEvent) -> void:
	var cell: PlantCell = area.cell # 盘面变动后按格子本身的位置兑现。
	var row: int = cell.row_col.x # 相邻行或同列其他格不会受伤。
	if row < 0 or row >= _game.zombie_manager.all_zombies_2d.size():
		return
	_present_thunder(cell)
	var targets: Array[Character000Base] = [] # 只收集这一格，伤害回调不会改变同步迭代。
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_2d[row]: # 仅遍历同一攻击行。
		if TargetGrid.targetable(zombie) and _game.board.cell_at_ground_point(zombie.global_position, row) == cell:
			targets.append(zombie)
	for boss: ZB000Base in _game.zombie_manager.get_living_bosses(): # 僵王可受邻近落雷伤害，依旧使用自身阶段门禁。
		if _game.board.cell_at_ground_point(boss.global_position, row) == cell:
			targets.append(boss)
	var scope := CombatHitScope.new() # 同一落雷不会对共享保护者重复消费一击。
	for reference: Variant in targets: # 同时支持普通僵尸或有阶段窗口的僵王。
		if not area.shot.is_active():
			break
		if is_instance_valid(reference) and not reference.is_death and not reference.is_queued_for_deletion():
			reference.be_attacked_bullet(THUNDER_DAMAGE, BulletRegistry.AttackMode.Real, true, false, 0, -1, null, scope)

## 从死者 [param area] 处发射覆盖一整圈的真实尖刺，可穿到邻行；命中只传播冻结层数。
func _bloom(area: AreaEvent) -> void:
	_flash(Layer.Style.BLOOM, area.position, Vector2.RIGHT, Color("d176ff"))
	var scene: PackedScene = Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet007Cactus) # 与母株共用投射场景。
	var origin: Vector2 = _game.bullets.to_local(area.position) # 转换到战场真实弹体容器。
	# 同一回调顺序初始化，所有尖刺只读取各自的发射值。
	var params: Dictionary[Bullet000NormBase.E_InitParasAttr, Variant] = {
		Bullet000NormBase.E_InitParasAttr.IsActivateLane: false,
		Bullet000NormBase.E_InitParasAttr.BulletLane: area.lane,
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: area.states,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: area.shot.damage_multiplier,
		Bullet000NormBase.E_InitParasAttr.AttackContext: area.shot.attack_context,
		Bullet000NormBase.E_InitParasAttr.AttackValidity: area.shot.is_active,
	}
	for i: int in range(BLOOM_SHOTS): # 弹针固定间隔，每圈完全覆盖360度。
		var ray: Vector2 = Vector2.from_angle(i * TAU / BLOOM_SHOTS) # 以尸体碰撞处作为真实出射点。
		var bullet := scene.instantiate() as BulletLinear007Cactus # 圈弹不能再标记泛滥。
		params[Bullet000NormBase.E_InitParasAttr.Direction] = ray
		params[Bullet000NormBase.E_InitParasAttr.Position] = origin + ray * 8.0
		bullet.configure_promotion(self, area.shot, 0, null, 0.0, area.wounds)
		bullet.init_bullet(params)
		_game.bullets.add_child(bullet)

## 复用芦苇的原生电弧帧，从 [param from] 到 [param at] 缩放和旋转。
func _show_arc(from: Vector2, at: Vector2) -> void:
	if not _draw_effects or _visible_bolts <= 0:
		return
	_visible_bolts -= 1
	var host: Node2D = _game.bullets # 与芦苇共享战场特效池和已生成的纹理。
	var effects: Node = host.get_node_or_null(^"LightningReedEffectPool") # 当前战斗可能已有芦苇。
	if effects == null:
		var script: Script = load(REED_PATH) as Script # 真正出现感电才读取原电弧表现。
		effects = script.new()
		effects.name = &"LightningReedEffectPool"
		host.add_child(effects)
	var bolt: Node2D = effects.play(&"bolt", from, 1) # 芦苇一阶的冰蓝色电弧。
	var ray: Vector2 = at - from # 对准真实目标点，不吸附到棋盘格。
	bolt.global_rotation = ray.angle()
	bolt.scale.x = maxf(1.0, ray.length()) / NATIVE_BOLT_LENGTH
	_flash(Layer.Style.CHARGE, at, Vector2.RIGHT, Color("abecff"))
	_play_shock_sound(at)

## 在 [param at] 播放原有感电电弧短音，一簇重叠电弧按首跳合声。
func _play_shock_sound(at: Vector2) -> void:
	if _clock < _audio_ready:
		return
	_audio_ready = _clock + AUDIO_GAP
	if _electric_audio == null:
		_electric_audio = load(SHOCK_AUDIO) as AudioStream
	if _electric_audio != null:
		SoundManager.play_world_sfx(_electric_audio, self, at, -9.0, 1.14, &"cactus_arc")

## 按 [param cell] 的真实脚点接地。短时间内同屏多格落雷，共用一次全景闪光、震动与声音。
func _present_thunder(cell: PlantCell) -> void:
	if not _draw_effects:
		return
	if _thunder_strike == null:
		_thunder_strike = ThunderStrike.new()
		add_child(_thunder_strike)
	var foot: Vector2 = cell.get_spawn_global_position() # 地面余晖与棋盘认定的落点共用坐标。
	if not _thunder_strike.strike(foot, cell.get_global_rect().size):
		return
	EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(4.5, 7.0), 0.23, 23.0])
	if _thunder_audio == null:
		_thunder_audio = load(THUNDER_AUDIO) as AudioStream
	if _thunder_audio != null:
		SoundManager.play_world_sfx(_thunder_audio, self, foot, -2.0, 1.0, &"cactus_thunder", true, 5)

## [param at] 是枪口，[param facing] 为射出方向，[param powers] 决定色彩，扇形 [param fan] 有独立轮廓。
func muzzle(at: Vector2, facing: Vector2, powers: int, fan: bool) -> void:
	_flash(Layer.Style.FAN if fan else Layer.Style.SHOT, at, facing, BulletLinear007Cactus.primary_color(powers))

## 在 [param at] 显示 [param powers] 或 [param ring] 的短促命中亮片。
func spike_hit(at: Vector2, powers: int, ring: bool) -> void:
	_flash(Layer.Style.HIT, at, Vector2.RIGHT, BulletLinear007Cactus.primary_color(powers, ring))

## 将 [param style]、[param at]、[param facing] 和 [param tint] 转给图形层；玩法不依赖该层存在。
func _flash(style: Layer.Style, at: Vector2, facing: Vector2, tint: Color) -> void:
	if _layer != null:
		_layer.trigger(style, at, facing, tint)
