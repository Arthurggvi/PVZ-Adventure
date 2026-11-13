## 发射子弹的原生攻击组件；攻击专用倍率只影响攻击时钟和攻击动画分支。
extends AttackComponentBase
class_name AttackComponentBulletBase

## 常规攻击混合树中独立的攻击分支，不改变待机、生产或成长动画的父级时标。
const ATTACK_ANIMATION_RATE_PROPERTY: StringName = &"parameters/TimeScale 2/scale"
## 同株动画树，原生超时仍通过 OneShot 请求触发射击。
@onready var animation_tree: AnimationTree = $"../AnimationTree"
## 保留进度、手动暂停与零速语义的原生攻击冷却。
@onready var bullet_attack_cd_timer: SpeedTimer = $BulletAttackCdTimer
## 角色原有速度因素乘积；与攻击专用来源分开保存，避免给其他行为加速。
var _owner_speed_product: float = 1.0
## 以来源实例 ID 保存相对攻速加成，撤销来源不会覆盖其他来源。
var _attack_rate_sources: Dictionary[int, float] = {}
## 攻击来源的合成倍率，1 表示没有额外攻速。
var _attack_rate_multiplier: float = 1.0
## 场景是否具有独立攻击分支；缺少该属性时只调整攻击时钟。
var _has_attack_animation_rate: bool = false
## 就绪时读取一次的攻击分支原始倍率，刷新或重挂不会重复乘算。
var _attack_animation_base: float = 1.0
## 持续范围攻击的单次执行入口，空值使用原生动画发射；不创建额外计时器。
var _continuous_attack: Callable
## 持续模式的固定战斗秒周期，不受正向角色速度或攻击专用倍率影响。
var _continuous_interval: float = 0.5

## 可攻击的植物状态位，初始化时继承检测组件设置。
var can_attack_plant_status: int = 1
## 可攻击的僵尸状态位，初始化时继承检测组件设置。
var can_attack_zombie_status: int = 1
## 是否按行约束子弹命中，初始化时继承检测组件设置。
var is_lane: bool = true
## 动画树中请求一次原生攻击的参数路径。
@export var attack_para: StringName = &"parameters/OneShot/request"
## 正常速度下的基础攻击间隔，单位为秒。
@export var attack_cd: float = 1.5
## 原生射击创建的子弹类型。
@export var attack_bullet_type: BulletRegistry.BulletType = BulletRegistry.BulletType.Bullet001Pea
## 一次射击使用的弹口，各弹口与检测区域方向一一对应。
@export var markers_2d_bullet: Array[Marker2D]
@export_group("发射子弹音效")
## 原生射击播放的角色音效名。
@export var attack_sfx: StringName = &"Throw"
## 子弹已实例化但尚未初始化时发出，供单株效果补充弹体行为。
signal signal_bullet_instantiated(bullet: Bullet000Base)
## 一次原生射击开始时发出，不按弹口数量重复发送。
signal signal_shoot_bullet
## 物种可提供一次齐射实现，保留同一套攻击时钟与动画触发入口。
var shoot_override: Callable
## 当前战斗的子弹容器，子弹初始化位置以该容器局部坐标表示。
var bullets: Node2D

## 初始化原生攻击周期，缓存攻击分支原值，再合成已有角色和攻击来源倍率。
func _ready() -> void:
	super()
	bullet_attack_cd_timer.base_wait_time = attack_cd
	for property: Dictionary in animation_tree.get_property_list(): # 只读取真实存在的动态动画参数。
		if StringName(property.get("name", "")) == ATTACK_ANIMATION_RATE_PROPERTY:
			_has_attack_animation_rate = true
			_attack_animation_base = float(animation_tree.get(ATTACK_ANIMATION_RATE_PROPERTY))
			break
	owner_update_speed(GlobalUtils.get_dic_product(owner.influence_speed_factors))
	if is_instance_valid(Global.main_game):
		bullets = Global.main_game.bullets
	can_attack_plant_status = detect_component.can_attack_plant_status
	can_attack_zombie_status = detect_component.can_attack_zombie_status
	is_lane = detect_component.is_lane

## [param speed_product] 为角色原有速度乘积；攻击来源不会反写角色速度或其他行为计时器。
func owner_update_speed(speed_product: float):
	_owner_speed_product = speed_product
	_refresh_attack_rate()

## [param source_id] 为有效来源实例 ID；[param bonus] 为相对攻速加成，0 或负数撤销来源。
## 重复设置幂等；非有限数值忽略，调用方负责先合成同种不叠加词条。
func set_attack_rate_source(source_id: int, bonus: float) -> void:
	if source_id <= 0 or not is_finite(bonus):
		return
	var next_bonus: float = maxf(0.0, bonus) # 非正值统一表示清除本来源。
	if float(_attack_rate_sources.get(source_id, 0.0)) == next_bonus:
		return
	if next_bonus == 0.0:
		_attack_rate_sources.erase(source_id)
	else:
		_attack_rate_sources[source_id] = next_bonus
	_attack_rate_multiplier = 1.0
	for amount: float in _attack_rate_sources.values(): # 各独立来源按相对攻速加成相加。
		_attack_rate_multiplier += amount
	_refresh_attack_rate()

## SpeedTimer 自行保留进度及暂停状态；独立攻击分支只乘一次攻击倍率，父级时标保持原生控制。
func _refresh_attack_rate() -> void:
	if not is_instance_valid(bullet_attack_cd_timer):
		return
	var rate: float = _owner_speed_product * _attack_rate_multiplier # 普通攻击保留既有速度来源合成。
	if _continuous_attack.is_valid():
		rate = 1.0 if _owner_speed_product > 0.0 else 0.0
	bullet_attack_cd_timer.set_speed_scale(rate)
	if _has_attack_animation_rate:
		animation_tree.set(ATTACK_ANIMATION_RATE_PROPERTY, _attack_animation_base * _attack_rate_multiplier)

## [param interval] 是正的固定战斗秒周期；[param callback] 为空时恢复原生动画攻击。
## 切换模式才重置进度；持续攻击仍由同一个SpeedTimer保持暂停、零速和离树语义。
func configure_continuous_attack(interval: float, callback: Callable) -> void:
	if callback.is_valid() and (not is_finite(interval) or interval <= 0.0):
		push_error("持续攻击周期必须为有限正数")
		return
	_continuous_attack = callback
	_continuous_interval = interval
	bullet_attack_cd_timer.stop()
	bullet_attack_cd_timer.base_wait_time = interval if callback.is_valid() else attack_cd
	_refresh_attack_rate()
	set_requires_target(not callback.is_valid())

## 仅归还 [param callback] 对应的持续模式，旧控制器离场不能覆盖后来安装的回调。
func clear_continuous_attack(callback: Callable) -> void:
	if _continuous_attack == callback:
		configure_continuous_attack(attack_cd, Callable())

## 开始原生攻击；持续模式完整等待固定周期，普通模式保留首次随机等待。
func attack_start():
	super()
	if bullet_attack_cd_timer.is_stopped():
		if _continuous_attack.is_valid():
			bullet_attack_cd_timer.start_scaled(_continuous_interval)
		else:
			bullet_attack_cd_timer.start_scaled(maxf(randf_range(0, attack_cd / 3.0), 0.001))
			# 修改后续基础周期不会重置当前短等待，也不会留下迟到重启的协程。
			bullet_attack_cd_timer.base_wait_time = attack_cd

## 结束原生攻击并取消当前等待，不清除角色或技能来源倍率。
func attack_end():
	super()
	bullet_attack_cd_timer.stop()
	set_cancel_attack()

## 同一时钟只执行一种攻击：持续脉冲直接结算，普通发射仍等待动画方法轨道。
func _on_bullet_attack_cd_timer_timeout() -> void:
	if _continuous_attack.is_valid():
		if is_enabling and is_attack_res:
			_continuous_attack.call()
		return
	animation_tree.set(attack_para, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## 保留物种覆盖的取消入口，基础组件不强制打断正在播放的攻击动画。
func set_cancel_attack():
	pass

## 动画调用的一次射击；暂停行动的僵尸不发射，物种齐射覆盖仍使用原入口。
func _shoot_bullet():
	if _continuous_attack.is_valid():
		return
	if owner is Zombie000Base and owner.is_action_suspended():
		return
	if shoot_override.is_valid():
		shoot_override.call()
		return
	signal_shoot_bullet.emit()
	for i: int in range(markers_2d_bullet.size()): # 每个弹口独立创建并初始化一颗子弹。
		var bullet: Bullet000Base = Global.bullet_registry.get_bullet_scenes(attack_bullet_type).instantiate() # 原生注册表中的弹体。
		signal_bullet_instantiated.emit(bullet)
		var bullet_paras: Dictionary[Bullet000NormBase.E_InitParasAttr, Variant] = get_bullet_paras(markers_2d_bullet[i].global_position, detect_component.ray_area_direction[i]) # 本弹口的初始化快照。
		bullet.init_bullet(bullet_paras)
		bullets.add_child(bullet)
		play_throw_sfx()

## [param marker_2d_bullet_glo_pos] 为弹口世界坐标；[param ray_direction] 为该弹口的射击方向。
## 返回原生命中参数及本次攻击上下文；非植物来源不生成植物词条快照。
func get_bullet_paras(marker_2d_bullet_glo_pos: Vector2, ray_direction: Vector2) -> Dictionary[Bullet000NormBase.E_InitParasAttr, Variant]:
	return {
		Bullet000NormBase.E_InitParasAttr.IsActivateLane: is_lane,
		Bullet000NormBase.E_InitParasAttr.BulletLane: owner.lane,
		Bullet000NormBase.E_InitParasAttr.Position: bullets.to_local(marker_2d_bullet_glo_pos),
		Bullet000NormBase.E_InitParasAttr.Direction: ray_direction,
		Bullet000NormBase.E_InitParasAttr.CanAttackPlantState: can_attack_plant_status,
		Bullet000NormBase.E_InitParasAttr.CanAttackZombieState: can_attack_zombie_status,
		Bullet000NormBase.E_InitParasAttr.DamageMultiplier: (
			(owner as Plant000Base).battle_damage_multiplier
			if owner is Plant000Base else 1.0),
		Bullet000NormBase.E_InitParasAttr.AttackContext: (
			(owner as Plant000Base).capture_attack_context()
			if owner is Plant000Base else null),
	}

## 播放当前原生攻击音效，不参与攻速或伤害计算。
func play_throw_sfx():
	SoundManager.play_character_SFX(attack_sfx)
