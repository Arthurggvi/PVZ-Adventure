extends AttackComponentBulletPultBase
class_name AttackComponentBulletCorn
## 玉米投手的原生装填与离手。转职将冷却额度与可见的甩篮周期分开。

## 保留约0.21秒的最快装填时间，让原生甩篮帧有足够时间出现在画面中。
const MAX_THROW_CLIP_RATE: float = 4.0
## 同一甩篮内批量离手的两轮之间略微错开，第一轮仍贴离手帧。
const BATCH_SPACING: float = 0.016
## 无穷高攻速时的表现错峰到此为止，攻击轮数继续累积。
const BATCH_SPREAD: float = 0.16
## 仅消费原生玉米投掷动画完成信号。
const THROW_ANIMATION: StringName = &"Cornpult_shooting"

## 投射黄油的概率
@export_range(0,1,0.01) var p_butter:float = 0.5
## body中的黄油节点
@export var sprite_2d_butter_in_body:Sprite2D
## 原生篮中的粒弹位置随真正甩篮变化，与固定弹口分开。
@onready var _kernel_in_basket: Sprite2D = $"../Body/BodyCorrect/Cornpult_kernal"
## 转职齐射启用独立的可见动作，普通原版不需要累计冷却。
var _readable_throw: bool = false
## 每轮原生冷却到账一次，等待下一次甩篮提交。
var _ready_volleys: int = 0
## 当前 OneShot 从开始装填到完整回收期间保持占用。
var _swing_active: bool = false
## 当前动作只消费一次离手，重入信号不会重复把同一批弹投出。
var _released: bool = false
## 本次原生离手的世界坐标；仅在调用投掷覆盖时有效。
var _release_point := Vector2.INF
## 当前同一甩篮内的轮次序号，用于表现错峰和音效合并。
var _batch_index: int = 0

## 为转职开启完整甩篮。保留原有树和方法轨道，最多连接一次完成信号。
func enable_readable_throws() -> void:
	if _readable_throw:
		return
	_readable_throw = true
	animation_tree.animation_finished.connect(_finish_swing)
	_refresh_attack_rate()

## 完整攻速继续驱动原计时器，只对转职玉米的画面时标单独换算。
func _refresh_attack_rate() -> void:
	super()
	if not _readable_throw:
		return
	var promotion: float = float(owner.influence_speed_factors.get(
		Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate, 1.0)) # 含固定转职与赌徒累积。
	var body_rate: float = _owner_speed_product / promotion if promotion > 0.0 else 0.0 # 冻结、减速等控制继续驱动根时标。
	owner.anim_component.owner_update_speed(body_rate)
	var world_root: float = body_rate * owner.anim_component.animation_origin_speed # 计算真正传到甩篮分支的动作时标。
	var attack_rate: float = _attack_animation_base * promotion * _attack_rate_multiplier # 正常攻速下保持原有动作节奏。
	animation_tree.set(ATTACK_ANIMATION_RATE_PROPERTY, minf(attack_rate, MAX_THROW_CLIP_RATE / maxf(1.0, world_root)))

## 原生时钟每到期交付一次额度。动作占用期间继续记账，当前甩篮不会被重新启动。
func _on_bullet_attack_cd_timer_timeout() -> void:
	if not _readable_throw:
		super()
		return
	if not is_attack_res or _owner_speed_product <= 0.0 or owner.is_death:
		return
	_ready_volleys += 1
	_begin_ready_swing()

## 本行失去攻击资格后回收尚未承诺的额度，正在播放的一次原生动作可自然收尾。
func attack_end() -> void:
	super()
	_ready_volleys = 0

## 只在已经回收甩篮、确有目标和冷却额度时启动一轮动作。
func _begin_ready_swing() -> void:
	if _swing_active or _ready_volleys == 0 or not is_attack_res or _owner_speed_product <= 0.0 \
			or not is_instance_valid(owner) or owner.is_death or not is_inside_tree():
		return
	var target: Character000Base = _choose_pult_target() # 沿用原生瞄准或黄油日的三行入口。
	if not is_instance_valid(target):
		_ready_volleys = 0
		return
	last_target_enemy = target
	last_target_enemy_global_pos = target.hurt_box_component.global_position
	_aimed_lane = target.lane if target.lane >= 0 else owner.lane
	_ready_volleys -= 1
	_swing_active = true
	_released = false
	animation_tree.set(attack_para, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## [param animation_name] 为本轮原生动作完成信号，下一轮需等混合节点完成收尾。
func _finish_swing(animation_name: StringName) -> void:
	if animation_name != THROW_ANIMATION or not _swing_active:
		return
	_swing_active = false
	_kernel_in_basket.modulate.a = 1.0
	if not _released and is_attack_res:
		_ready_volleys += 1
	if _ready_volleys > 0:
		_begin_ready_swing.call_deferred()


## 原生装填帧选择可见弹药，其他到期轮次仍独立抽取各自的原版弹种。
func random_choose_butter_or_corn() -> void:
	attack_bullet_type = _roll_native_payload()
	var butter: bool = attack_bullet_type == BulletRegistry.BulletType.Bullet011Butter # 篮中只表现当前装填结果。
	sprite_2d_butter_in_body.visible = butter
	if _readable_throw:
		_kernel_in_basket.modulate.a = 0.0 if butter else 1.0

## 每个原生普通轮次独立抽取黄油，绿色食品已将概率降为零。
func _roll_native_payload() -> BulletRegistry.BulletType:
	return BulletRegistry.BulletType.Bullet011Butter if randf() < p_butter else BulletRegistry.BulletType.Bullet010Corn

## 原生离手帧先固定篮中弹体的真实中心，再兑现已经到期的炮弹轮次。
func _shoot_bullet() -> void:
	if not _readable_throw or not _swing_active:
		super()
		sprite_2d_butter_in_body.visible = false
		return
	if _released or owner.is_death or owner.is_cold_frozen():
		return
	_released = true
	var volley_count: int = 1 + _ready_volleys # 已开始的这次装填和积累至离手的额外轮次。
	_ready_volleys = 0
	var payload: Sprite2D = sprite_2d_butter_in_body \
		if attack_bullet_type == BulletRegistry.BulletType.Bullet011Butter else _kernel_in_basket # 对齐此帧真正装填的图形。
	_release_point = payload.to_global(payload.get_rect().get_center())
	for index: int in range(volley_count): # 不重播动画，每轮仍走正常独立的游戏判定。
		_batch_index = index
		if index > 0:
			attack_bullet_type = _roll_native_payload()
		super()
	_batch_index = 0
	_release_point = Vector2.INF
	sprite_2d_butter_in_body.visible = false

## 返回当前篮中弹体中心；普通发射辅助路径仍能使用原生标记。
func release_origin() -> Vector2:
	return _release_point if _release_point.is_finite() else markers_2d_bullet[0].global_position

## 返回本轮共享甩篮时的显示错峰，正常单轮投掷返回零。
func release_delay() -> float:
	return minf(float(_batch_index) * BATCH_SPACING, BATCH_SPREAD)

## 同一可见甩篮只播放一次发射声。
func is_first_animated_volley() -> bool:
	return _batch_index == 0
