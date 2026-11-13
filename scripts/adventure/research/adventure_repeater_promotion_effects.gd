## 双发转职按原生射击动画发弹；每轮增弹只插入单株私有方法轨道。
extends Node
class_name AdventureRepeaterPromotionEffects

## 最多四转，每个已选变种恰占四分之一抽签区间。
const MAX_VARIANTS: int = 4
## 当前实际双发植株；不从卡槽寻找同名替代者。
var _plant: Plant008PeaShooterDouble
## 原生索敌、攻击时钟与弹口组件。
var _attack: AttackComponentBulletBase
## 按转职顺序冻结的变种，重复配置不增加弹数或概率。
var _variants: Array[StringName] = []
## 本株原动画库和私有动画库，撤销时只归还自己的修改。
var _volley: Dictionary = {}

## [param plant] 是入树前植株；[param events] 是该株冻结的转职事件。
func configure(plant: Plant008PeaShooterDouble, events: Array[Dictionary]) -> void:
	_plant = plant
	for event: Dictionary in events: # 只接纳八种正式变种，每转一个，不允许重复累加。
		var kind := StringName(str(event.get("variant", ""))) # 本书绑定的单一弹体类型。
		if kind in [&"frost", &"ember", &"shock", &"detonation", &"morning", &"hell", &"kaguya", &"hades"] \
				and not _variants.has(kind) and _variants.size() < MAX_VARIANTS:
			_variants.append(kind)

## 同株搬迁后仍使用原控制器；较晚重新入树时再补回已经归还的绑定。
func _enter_tree() -> void:
	if is_instance_valid(_plant) and _plant.is_node_ready():
		_bind.call_deferred()

## 等待原株及其动画组件全部就绪，避免子节点先就绪时读取空的 onready 成员。
func _ready() -> void:
	if not is_instance_valid(_plant):
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 在同一原生发射入口安装变种；没有转职的普通双发不会创建控制器。
func _bind() -> void:
	if not is_instance_valid(_plant) or _plant.is_death or _variants.is_empty():
		return
	_attack = _plant.attack_component
	if is_instance_valid(_attack) and _attack.shoot_override == _shoot:
		return
	if not is_instance_valid(_attack) or _attack.shoot_override.is_valid():
		push_error("双发转职需要空闲的原生发射入口")
		return
	_volley = RepeaterVolleyAnimation.install(_plant, _variants.size())
	if _volley.is_empty():
		return
	_attack.shoot_override = _shoot
	_attack.signal_change_is_attack.connect(_on_attack_state)

## 每个原生或增补方法键只发一颗；单次四等分抽签不会被后一本书覆盖。
func _shoot() -> void:
	if not is_instance_valid(_plant) or _plant.is_death or _plant.is_queued_for_deletion() \
			or not is_instance_valid(_attack) or not _attack.is_enabling or not _attack.is_attack_res:
		return
	var shot: RepeaterShotContext = RepeaterShotContext.from_plant(_plant) # 每次实际发射的战场与来源快照。
	if shot == null or not shot.is_active() or not is_instance_valid(_attack.bullets):
		return
	var ticket: int = randi_range(0, MAX_VARIANTS - 1) # 每个已选变种固定百分之二十五，余下区间仍是普通豌豆。
	var kind: StringName = _variants[ticket] if ticket < _variants.size() else &"" # 唯一命中区间，不叠加变种。
	_attack.signal_shoot_bullet.emit()
	for index: int in range(_attack.markers_2d_bullet.size()): # 保留原生弹口与方向的对应关系。
		if index >= _attack.detect_component.ray_area_direction.size():
			break
		var bullet: Bullet000NormBase = RepeaterProjectileFactory.create(kind, shot) # 只创建原生派生场景。
		if bullet == null:
			continue
		_attack.signal_bullet_instantiated.emit(bullet)
		if not is_instance_valid(_plant) or _plant.is_death or _plant.is_queued_for_deletion() \
				or not _attack.is_attack_res:
			bullet.free()
			break
		var parameters: Dictionary = _attack.get_bullet_paras(_attack.markers_2d_bullet[index].global_position,
			_attack.detect_component.ray_area_direction[index]) # 所有伤害来源在这一颗弹中冻结一次。
		parameters[Bullet000NormBase.E_InitParasAttr.AttackContext] = shot.attack_context
		parameters[Bullet000NormBase.E_InitParasAttr.DamageMultiplier] = shot.damage_multiplier
		bullet.init_bullet(parameters)
		if not shot.is_active():
			bullet.free()
			break
		_attack.bullets.add_child(bullet)
		_attack.play_throw_sfx()

## [param active] 为原生索敌与行动许可；停止攻击即中止旧片段，不能把残余增弹带到下一轮。
func _on_attack_state(active: bool) -> void:
	if not active and is_instance_valid(_attack) and is_instance_valid(_attack.animation_tree):
		_attack.animation_tree.set(_attack.attack_para, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

## 同帧重新挂载可能临时离树，延后确认真实移除才归还私有资源。
func _exit_tree() -> void:
	_release_if_detached.call_deferred()

## 只撤销自己的回调、信号和动画库，不能覆盖后来安装的其他控制器。
func _release_if_detached() -> void:
	if is_inside_tree():
		return
	if is_instance_valid(_attack):
		if _attack.shoot_override == _shoot:
			_attack.shoot_override = Callable()
		if _attack.signal_change_is_attack.is_connected(_on_attack_state):
			_attack.signal_change_is_attack.disconnect(_on_attack_state)
	RepeaterVolleyAnimation.release(_volley)
