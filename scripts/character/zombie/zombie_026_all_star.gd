extends Zombie000Base
class_name Zombie026AllStar
## 使用 PvZ2 5.8.1 的独立全明星动作和生命配置。

## 每个实例只尝试一次擒抱，死亡时停止后续攻击。
enum ChargeState { CHARGING, TACKLING, SPENT, DEAD }

## 原版冲锋速度为每秒 0.5 格，换算为本项目移动组件的倍率。
const CHARGE_SPEED := 2.0
## 原版普通行走速度为每秒 0.16 格，换算为本项目移动组件的倍率。
const SPENT_SPEED := 0.64
## PvZ2 ZombieModernAllStarDefault 的 SmashDamage。
const TACKLE_DAMAGE := 1500

## 负责全部出战和展示动作的唯一播放器。
@onready var _visual_animation: AnimationPlayer = $AnimationPlayer
## 随原始 PAM 头盔姿态移动，用于黄油定位和死亡掉头。
@onready var _head_anchor: Marker2D = $Body/AllStarVisual/HeadAnchor
## 普通死亡时从头部位置抛出的原版头盔连头部精灵。
@onready var _head_drop: ZombieDropBase = $Body/HeadDrop
## 播放原始擒抱帧上的撞击音效。
@onready var _tackle_sound: AudioStreamPlayer2D = $TackleSound
## 仅实战入场播放的项目哨声。
@onready var _entrance_whistle: AudioStreamPlayer = $EntranceWhistle

## 当前冲锋、擒抱、步行或死亡状态。
var charge_state: ChargeState = ChargeState.CHARGING
## 擒抱开始时锁定的植物或友方屏障；在动作接触帧处理。
var _tackle_target: Character000Base
## 防止擒抱动画关键帧在同一次动作里重复结算。
var _tackle_hit_applied := false


## 在父类初始化黄油锚点前指定全明星自己的头部。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/AllStarVisual/HeadAnchor")])
	_visual_animation.animation_finished.connect(_on_visual_animation_finished)
	super()


## 战前预览、图鉴和卡片使用待机姿态。
func ready_show() -> void:
	super()
	_play_action(&"idle")


## 连接出战事件，并以冲锋状态进场。
func ready_norm_signal_connect() -> void:
	super()
	_entrance_whistle.play()
	attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
	attack_component.detect_component.signal_can_attack.connect(_on_charge_contact)
	attack_component.signal_change_is_attack.connect(_on_attack_state_changed)
	hp_component.signal_hp_component_death.connect(_on_death)
	signal_character_be_hypno.connect(_retire_charge)
	_set_move_speed(CHARGE_SPEED)
	_play_action(&"run")


## 冲锋首次撞到植物或屏障时停步并锁定目标。
func _on_charge_contact() -> void:
	if charge_state != ChargeState.CHARGING or is_death or is_hypno:
		return
	# 检测组件在发出接触信号前已选定可攻击的目标。
	var target: Character000Base = attack_component.detect_component.enemy_can_be_attacked
	if (target is Plant000Base or target is FriendlyBattleBarrier) and not target.is_death:
		_tackle_target = target
		_tackle_hit_applied = false
		charge_state = ChargeState.TACKLING
		_set_move_speed(0.0)
		_play_action(&"tackle")
	elif attack_component.detect_component.brain != null or attack_component.detect_component.pot != null:
		_retire_charge()


## PAM 第 474 帧结算一次擒抱；若撞死目标则保留压扁表现。
func _on_visual_tackle_hit() -> void:
	if charge_state != ChargeState.TACKLING or _tackle_hit_applied or is_death:
		return
	_tackle_hit_applied = true
	_set_move_speed(SPENT_SPEED)
	# 擒抱只命中本次锁定且仍可接触的实体，出手前已冻住的植物同样跳过。
	var target := _tackle_target # 冲锋首次接触时锁定的目标。
	if is_instance_valid(target) and not target.is_death and not target.is_queued_for_deletion() \
			and (not target is Plant000Base or not target.is_cold_frozen()):
		if target is FriendlyBattleBarrier:
			target.be_zombie_eat(TACKLE_DAMAGE, self)
			return
		target.be_attacked_bullet(TACKLE_DAMAGE, BulletRegistry.AttackMode.Penetration, true, false, 0, -1, null,
			CombatHitScope.for_plant_attack(self, CombatHitScope.PlantImpact.CRUSH))
		if is_instance_valid(target) and target.is_death:
			target.body.be_flattened_body()


## PAM 第 470 帧的擒抱音效事件。
func _on_original_tackle_sound() -> void:
	if charge_state == ChargeState.TACKLING:
		_tackle_sound.play()


## [param action] 完成播放的原始动作名；擒抱结束后恢复行走，倒地后淡出尸体。
func _on_visual_animation_finished(action: StringName) -> void:
	if charge_state == ChargeState.TACKLING and action == &"tackle":
		_retire_charge()
	elif charge_state == ChargeState.DEAD and action == &"die":
		_fade_and_remove()


## 擒抱完成或被魅惑后恢复普通行走和啃咬。
func _retire_charge() -> void:
	if charge_state == ChargeState.SPENT or charge_state == ChargeState.DEAD:
		return
	_tackle_target = null
	charge_state = ChargeState.SPENT
	_set_move_speed(SPENT_SPEED)
	attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)
	_sync_spent_action()


## [param _attacking] 最新攻击状态；这里只在结束冲锋后同步步行和啃咬动画。
func _on_attack_state_changed(_attacking: bool) -> void:
	if charge_state == ChargeState.SPENT:
		_sync_spent_action()


## 按已更新的检测状态选择步行或啃咬动作。
func _sync_spent_action() -> void:
	# 使用实际啃咬状态，保持动画与攻击组件一致。
	var desired: StringName = &"eat" if is_attack else &"walk"
	if _visual_animation.current_animation != desired or not _visual_animation.is_playing():
		_play_action(desired)


## 常规死亡按 PAM 播放无头倒地；灰烬、吞食等由各自的死亡入口处理。
func _on_death() -> void:
	_tackle_target = null
	charge_state = ChargeState.DEAD
	_set_move_speed(0.0)
	_entrance_whistle.stop()
	_tackle_sound.stop()
	if not is_can_death_language:
		return
	signal_update_speed.disconnect(anim_component.owner_update_speed)
	_visual_animation.speed_scale = 1.0
	_drop_helmeted_head()
	_play_action(&"die")


## 按死亡前最后一帧的头部位置、缩放和翻面抛出戴盔的头。
func _drop_helmeted_head() -> void:
	# 拷贝头部世界矩阵，离开身体后仍保持原来的姿态和朝向。
	var head_pose := _head_anchor.global_transform
	_head_drop.global_transform = Transform2D(0.0, head_pose.origin)
	# 单张原始头部精灵同时包含头和头盔，按中心旋转。
	var head_sprite: Sprite2D = _head_drop.get_child(0)
	head_sprite.global_transform = head_pose
	_head_drop.ground_y = global_position.y - head_pose.origin.y +			- head_sprite.texture.get_height() * head_pose.y.length() * 0.5
	_head_drop.visible = true
	_head_drop.acitvate_it()


## [param action] 应立即应用首帧的原始动作，防止切换时残留上一个动作的姿态。
func _play_action(action: StringName) -> void:
	_visual_animation.play(action)
	_visual_animation.advance(0.0)


## [param speed] 相对本项目基础速度的移动倍率。
func _set_move_speed(speed: float) -> void:
	move_component.update_only_move_speed(speed)
