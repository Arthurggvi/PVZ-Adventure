## 仙人掌原生高低动画与冻结转职齐射。
extends AttackComponentBulletBase
class_name AttackComponentBulletCactus

## 原生低形态射击子动画的速率。
const LOW_RATE := &"parameters/StateMachine/BlendTree/TimeScale/scale"
## 原生高形态射击子动画的速率。
const HIGH_RATE := &"parameters/StateMachine/BlendTree 2/TimeScale/scale"
## 原动作的播放倍率；额外攻速仅乘射击子动画。
const NATIVE_SHOOT_SPEED: float = 3.0
## 五连发在基础速度下每两发间隔的游戏秒数。
const BURST_GAP: float = 0.115
## 连发内部最多按此速率加快，避免弹针重叠成一条线。
const BURST_MAX_RATE: float = 1.75
## 扇形总开角60度，最外两颗落在角度边界。
const FAN_HALF_ANGLE: float = PI / 6.0
## 发射几何与攻击技能使用同一枚原生弹体。
const Power = BulletLinear007Cactus.Power
## 只在原生仙人掌出战时使用这一战场运行时。
const BattleEffects = preload("res://scripts/adventure/research/cactus_battle_effects.gd")

## 动画状态机的目标形态。
var is_rise: bool = false
## 本株可应用的弹体或齐射词条。
var _powers: int = 0
## 高低形态共用的转职攻速百分点。
var _flat_attack_bonus: float = 0.0
## 散射计数只在原生射击事件成功发出后递增。
var _volley_count: int = 0
## 当前五连发剩余的子弹数。
var _burst_remaining: int = 0
## 当前五连发到下颗的基础秒数。
var _burst_left: float = 0.0
## 齐射开始时冻结的战场与来源。
var _shot: RepeaterShotContext
## 本轮的空中追踪对象，低形态为空。
var _air_target: Zombie000Base
## 当前齐射开始时的高低形态，不在半途改变目标位。
var _volley_states: int = 1

## 原生探测能同时看到地面与空中；普通子弹只打当前形态对应的目标。
func _ready() -> void:
	super()
	can_attack_zombie_status = Zombie000Base.E_BeAttackStatusZombie.IsNorm
	set_physics_process(false)
	if _powers != 0:
		shoot_override = _fire_promotion_volley
		_refresh_form_rate()

## 植物入树前冻结 [param events]，攻速在真实射击组件就绪后安装。
func configure_promotions(events: Array[Dictionary]) -> void:
	for effect: Dictionary in events: # 已通过研究目录的物种与等级校验。
		_flat_attack_bonus += float(effect.get("attack_rate", 0.0))
		match effect.kind:
			"cactus_guided": _powers |= Power.GUIDED
			"cactus_pierce": _powers |= Power.PIERCE
			"cactus_wound": _powers |= Power.WOUND
			"cactus_shock": _powers |= Power.SHOCK
			"cactus_flood": _powers |= Power.FLOOD
			"cactus_thunder": _powers |= Power.THUNDER
			"cactus_burst": _powers |= Power.BURST
			"cactus_scatter": _powers |= Power.SCATTER

## 沿用原生射击时钟。射击专用调速不会修改升降与待机。
func _refresh_attack_rate() -> void:
	super()
	if _powers == 0 or not is_instance_valid(animation_tree):
		return
	var low_bonus: float = 0.5 if (_powers & Power.GUIDED) != 0 else 0.0 # 制导的地面专用部分。
	animation_tree.set(LOW_RATE, NATIVE_SHOOT_SPEED * (_attack_rate_multiplier + (low_bonus if is_rise else 0.0)))
	animation_tree.set(HIGH_RATE, NATIVE_SHOOT_SPEED * (_attack_rate_multiplier - (0.0 if is_rise else low_bonus)))

## 切换 [param value] 为动画即将进入的形态；用新形态调整时钟而保留已有进度。
func on_cactus_update_is_rise(value: bool) -> void:
	if is_rise == value:
		return
	is_rise = value
	if _powers != 0:
		_refresh_form_rate()

## 形态与二、三转独立加点，全部按攻速百分点相加。
func _refresh_form_rate() -> void:
	var ground_bonus: float = 0.5 if not is_rise and (_powers & Power.GUIDED) != 0 else 0.0 # 只加速低形态。
	set_attack_rate_source(get_instance_id(), _flat_attack_bonus + ground_bonus)

## 攻击周期到期后请求当前形态的原生射击动画。
func _on_bullet_attack_cd_timer_timeout() -> void:
	if owner.is_cold_frozen():
		return
	if is_rise:
		animation_tree.set("parameters/StateMachine/BlendTree 2/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		animation_tree.set("parameters/StateMachine/BlendTree/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## 原生取消入口覆盖两种形态；正在飞行的尖刺不依赖施法者。
func set_cancel_attack() -> void:
	animation_tree.set("parameters/StateMachine/BlendTree/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	animation_tree.set("parameters/StateMachine/BlendTree 2/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

## 升降结束后依据 [param value] 更新攻击状态位。
func update_bullet_can_attack_zombie_status(value: bool) -> void:
	can_attack_zombie_status = Zombie000Base.E_BeAttackStatusZombie.IsSky if value else Zombie000Base.E_BeAttackStatusZombie.IsNorm

## 沿用原发射事件、弹口与射线。迟到的回调只能在当前正式战局生成子弹。
func _fire_promotion_volley() -> void:
	if not is_enabling or owner.is_death or _burst_remaining > 0:
		return
	var capture: RepeaterShotContext = RepeaterShotContext.from_plant(owner) # 整轮共用同一份不持有母株的快照。
	if capture == null or not is_instance_valid(bullets):
		return
	_shot = capture
	_volley_states = can_attack_zombie_status
	_air_target = null
	if (_powers & Power.GUIDED) != 0 and (_volley_states & Zombie000Base.E_BeAttackStatusZombie.IsSky) != 0:
		# 与原生伸展检测保持同一目标资格，锁定这一轮的可见空中目标。
		if detect_component.judge_zombie_in_sky():
			_air_target = detect_component.enemy_can_be_attacked as Zombie000Base
	_volley_count += 1
	var fan: bool = (_powers & Power.SCATTER) != 0 and _volley_count % 4 == 0 # 每三次普通攻击后是一次扇形。
	signal_shoot_bullet.emit()
	play_throw_sfx()
	_emit_shots(10 if fan else 1)
	if (_powers & Power.BURST) != 0:
		_burst_remaining = 4
		_burst_left = BURST_GAP
		set_physics_process(true)
	else:
		_clear_volley()

## 推进本轮五连发。[param delta] 属于战斗时间，冻结保留余量，死亡与外部禁用取消后续发射。
func _physics_process(delta: float) -> void:
	if _shot == null or not _shot.is_active() or owner.is_death or not is_enabling:
		_clear_volley()
		return
	if owner.is_cold_frozen():
		return
	_burst_left -= delta * minf(BURST_MAX_RATE, _owner_speed_product * _attack_rate_multiplier)
	while _burst_left <= 0.0 and _burst_remaining > 0:
		_emit_shots(1)
		_burst_remaining -= 1
		_burst_left += BURST_GAP
	if _burst_remaining == 0:
		_clear_volley()

## 清掉尚未发出的部分；已发子弹保留出手时的快照。
func _clear_volley() -> void:
	_burst_remaining = 0
	_shot = null
	_air_target = null
	set_physics_process(false)

## 在当前弹口发出 [param count] 颗实际弹体；散射均匀覆盖前方扇形。
func _emit_shots(count: int) -> void:
	var runtime := bullets.get_node_or_null(NodePath(BattleEffects.NODE_NAME)) as BattleEffects # 整个战场只创建一次。
	if runtime == null:
		runtime = BattleEffects.new(_shot.game)
		bullets.add_child(runtime)
	var mouth: Vector2 = markers_2d_bullet[0].global_position # 使用当前形态动画的原生弹口。
	var forward: Vector2 = detect_component.ray_area_direction[0].normalized() # 保留坡面的原生发射方向。
	var paras: Dictionary[Bullet000NormBase.E_InitParasAttr, Variant] = get_bullet_paras(mouth, forward) # 只读地复用同一轮的基础参数。
	paras[Bullet000NormBase.E_InitParasAttr.AttackContext] = _shot.attack_context
	paras[Bullet000NormBase.E_InitParasAttr.AttackValidity] = _shot.is_active
	paras[Bullet000NormBase.E_InitParasAttr.CanAttackZombieState] = _volley_states
	var target: Zombie000Base = _air_target if is_instance_valid(_air_target) else null # 已退场的锁定目标不传入强类型入口。
	if count > 1 or target != null:
		paras[Bullet000NormBase.E_InitParasAttr.IsActivateLane] = false
	var scene: PackedScene = Global.bullet_registry.get_bullet_scenes(attack_bullet_type) # 沿用现有投射物资源。
	for index: int in range(count): # 依次初始化实际发射的尖刺。
		var angle: float = lerpf(-FAN_HALF_ANGLE, FAN_HALF_ANGLE, float(index) / float(count - 1)) if count > 1 else 0.0
		var bullet := scene.instantiate() as BulletLinear007Cactus # 同一原生尖刺支持各路线。
		paras[Bullet000NormBase.E_InitParasAttr.Direction] = forward.rotated(angle)
		signal_bullet_instantiated.emit(bullet)
		bullet.configure_promotion(runtime, _shot, _powers, target, 0.21 if count > 1 else 0.0)
		bullet.init_bullet(paras)
		bullets.add_child(bullet)
	runtime.muzzle(mouth, forward, _powers, count > 1)
