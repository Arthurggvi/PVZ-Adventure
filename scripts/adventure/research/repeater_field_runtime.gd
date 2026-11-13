## 同一战场的持续场结算时钟；辉夜跨弹体共用60Hz去重，地狱仍按独立整秒吸取。
extends Node2D
class_name RepeaterFieldRuntime

## 战斗伤害固定60Hz，渲染帧数不改变每秒结算次数。
const STEP: float = 1.0 / 60.0
## 允许浮点整秒边界正确兑现最后一跳。
const EPSILON: float = 0.000001
## 辉夜每次接触的基础伤害，不按星屑数或场数放大。
const KAGUYA_DAMAGE: int = 10
## 当前战场唯一节点名；新场只登记数据，不新建结算时钟。
const NODE_NAME: StringName = &"RepeaterFields"
## 活跃场的时间、来源与同源视觉轨迹。
var _fields: Array[RepeaterFieldState] = []
## 尚未消费的战斗时间余量，场景暂停时保持。
var _accumulator: float = 0.0
## 最近实际战斗物理步长，视觉插值同步战斗倍速而非假定现实时间一倍速。
var _last_delta: float = STEP

## 在 [param shot] 原战场登记 [param kind] 场；[param position]、[param lane] 均来自真实命中。
static func spawn_field(kind: StringName, position: Vector2, lane: int, shot: RepeaterShotContext) -> void:
	if shot == null or not shot.is_active() or kind not in [&"hell", &"kaguya"]:
		return
	var runtime: RepeaterFieldRuntime = shot.game.bullets.get_node_or_null(NodePath(NODE_NAME)) as RepeaterFieldRuntime # 同场所有辉夜共享时钟。
	if runtime == null:
		runtime = RepeaterFieldRuntime.new()
		runtime.name = NODE_NAME
		shot.game.bullets.add_child(runtime)
	runtime._fields.append(RepeaterFieldState.create(runtime, kind, position, lane, shot))
	runtime.set_physics_process(true)
	runtime.set_process(true)

## 休眠节点不轮询战场；第一次生成持续场才启用。
func _ready() -> void:
	set_physics_process(false)
	set_process(false)

## [param delta] 是可暂停的物理战斗秒数；不以每帧调用次数代替伤害时钟。
func _physics_process(delta: float) -> void:
	_last_delta = maxf(0.0, delta)
	_accumulator += delta
	while _accumulator + EPSILON >= STEP and not _fields.is_empty():
		_accumulator = maxf(0.0, _accumulator - STEP)
		_tick()
	if _fields.is_empty():
		_accumulator = 0.0
		set_physics_process(false)
		set_process(false)

## 每个子步先统一推进场，再合并辉夜接触，最后撤销到期场；末跳不会被提前释放吞掉。
func _tick() -> void:
	for field: RepeaterFieldState in _fields.duplicate(): # 同步死亡可改变战局，逐场重新验证。
		if not field.shot.is_active():
			_retire(field)
			continue
		field.age = minf(field.lifetime, field.age + STEP)
		if field.kind == &"hell" and field.age + EPSILON >= field.next_drain:
			field.next_drain += 1.0
			_drain(field)
	var contacts: Dictionary[int, Dictionary] = RepeaterFieldQueries.kaguya_contacts(_fields) # 所有重叠碎片共用一次接触集合。
	var hit_scope := CombatHitScope.new() # 转伤后的真正承伤者在扣血前共用本子步唯一资格。
	for entry: Dictionary in contacts.values(): # 伤害回调可能结束战局或销毁后续目标。
		var target: Character000Base = entry.target # 本次已确认接触的实体。
		var shot: RepeaterShotContext = entry.shot # 首个接触来源持有本次伤害归属。
		if shot.is_active() and _valid_enemy(target):
			target.be_attacked_bullet(KAGUYA_DAMAGE, BulletRegistry.AttackMode.Norm,
				true, false, 0, -1, null, hit_scope)
	for field: RepeaterFieldState in _fields.duplicate(): # 实际结束在末跳之后，视觉年龄与寿命保持一致。
		if not field.shot.is_active() or field.age + EPSILON >= field.lifetime:
			_retire(field)
		else:
			field.render_at(field.age)

## 渲染只在两个战斗时刻之间采样；[param _delta] 不参与伤害、吸取或寿命结算。
func _process(_delta: float) -> void:
	var interpolation: float = Engine.get_physics_interpolation_fraction() * _last_delta # 视觉与战斗倍速共用实际步长。
	for field: RepeaterFieldState in _fields: # 显式视觉时间可暂停，不读取Shader全局TIME。
		field.render_at(minf(field.lifetime, field.age + _accumulator + interpolation))

## 对 [param field] 周围3×3敌人各吸取一次；按真正损失治疗原株，不复用目标预估伤害。
func _drain(field: RepeaterFieldState) -> void:
	var shot: RepeaterShotContext = field.shot # 本次吸取固定的来源快照。
	var center: Vector2 = field.center_at(field.age) # 漩涡当前实际位置与视觉一致。
	var areas: Array[Area2D] = RepeaterFieldQueries.area(shot, center, field.lane, 3.0) # 复用真实格距、受击框与公共筛选。
	for target: Character000Base in CombatExplosion.plant_blast_targets(areas, field.lane, 1, 31): # 同一敌人多受击框只吸取一次。
		if not shot.is_active():
			break
		if not _valid_enemy(target) or target is EnemyStructureBase:
			continue
		var damage: int = maxi(0, roundi(float(target.hp_component.max_hp) * 0.05)) # 只取本体上限，护甲不进入百分比分母。
		var receipt: Dictionary = {} # 保护者代伤也在原伤害链返回真实损失。
		target.be_attacked_bullet(damage, BulletRegistry.AttackMode.Norm, true, false, 0, -1, receipt)
		var actual_loss: int = int(receipt.get("actual_loss", 0)) # 无敌、格挡和过量伤害不能制造额外治疗。
		if actual_loss <= 0 or not shot.is_same_battle():
			continue
		shot.heal_original(actual_loss)
		var recipient: Character000Base = receipt.get("recipient") as Character000Base # 链条连向真正承伤者，包括保护者。
		if is_instance_valid(recipient) and recipient.is_inside_tree():
			RepeaterImpactVisual.chain(self, center, recipient.hurt_box_component.global_position)

## [param target] 在同步结算前仍必须可受击；已死亡、魅惑与待删除目标不重复扣血。
static func _valid_enemy(target: Character000Base) -> bool:
	return is_instance_valid(target) and not target.is_death and not target.is_hypno \
		and not target.is_queued_for_deletion() and target.is_inside_tree() \
		and is_instance_valid(target.hp_component) and is_instance_valid(target.hurt_box_component) \
		and target.hurt_box_component.is_enabling

## 从唯一集合移除 [param field] 并回收对应纯视觉节点。
func _retire(field: RepeaterFieldState) -> void:
	field.dispose()
	_fields.erase(field)
