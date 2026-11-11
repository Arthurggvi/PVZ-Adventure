extends Zombie000Base
class_name Zombie027Explorer
## 复用 PvZ2 5.8.1 的探险家动作、燃烧表现及火把状态。

## 原版 MaxTorchReach，限制点燃火把时攻击框向前偏移的像素数。
const MAX_TORCH_REACH := 37.0
## 原版 Play_Zomb_Egypt_Explorer_Mvmt_Burn 的音频。
const TORCH_BURN_SFX := preload("res://assets/adventure/zombies/explorer/explorer_torch_burn.wav")
## 被火把烧掉的植物位置上播放的一次性原版动效。
const PLANT_BURN := preload("res://scenes/character/zombie/explorer_plant_burn.tscn")

## 播放原版 PAM 中的动作和啃食接触帧。
@onready var _visual_animation: AnimationPlayer = $AnimationPlayer
## 包含原版身体部件、独立火焰图层和碰撞定位点。
@onready var _visual: Node2D = $Body/ExplorerVisual
## 原版动画中内侧后脚与火把头的水平距离，记录于局部 X 坐标。
@onready var _torch_reach: Marker2D = $Body/ExplorerVisual/TorchReach
## 头部锚点，供黄油和死亡时的头部掉落使用。
@onready var _head_anchor: Marker2D = $Body/ExplorerVisual/HeadAnchor
## 普通死亡时抛出的原版头部精灵。
@onready var _head_drop: ZombieDropBase = $Body/HeadDrop
## 同时负责普通啃咬和点燃植物的攻击范围。
@onready var _attack_shape: CollisionShape2D = $AttackComponent/DetectComponent/Area2d/CollisionShape2D
## 熄灭火把时恢复的普通攻击框中心。
@onready var _bite_center_x: float = _attack_shape.position.x
## 最近一次请求更新的攻击框 X 坐标，避免碰撞回调内重复更新。
@onready var _requested_attack_x: float = _bite_center_x

## 是否持有点燃的火把；寒冷消退后保持熄灭，直到受到火伤。
var _torch_lit := true


## 黄油采用专用头部锚点；预览实例不进行战斗判定。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/ExplorerVisual/HeadAnchor")])
	_visual_animation.animation_finished.connect(_on_visual_animation_finished)
	set_physics_process(false)
	super()


## 图鉴和战前展示播放持火把待机动作。
func ready_show() -> void:
	super()
	_play_action(&"idle")


## 出战时以持火把行走开始，并监听正常死亡。
func ready_norm_signal_connect() -> void:
	super()
	# 探险家使用实际啃咬状态，而不是单纯的索敌结果来更新移动和受击框。
	attack_component.signal_change_is_attack.disconnect(
		move_component.update_move_factor.bind(MoveComponent.E_MoveFactor.IsAttack))
	attack_component.signal_change_is_attack.disconnect(hurt_box_component.change_area_attack_appear)
	hp_component.signal_hp_component_death.connect(_on_death)
	_play_action(&"walk")
	_update_torch_reach()
	set_physics_process(true)


## [param value] 共用攻击组件的索敌结果；只有进入普通啃咬时才停步。
func change_is_attack(value: bool) -> void:
	if is_death:
		return
	# 魅惑后的敌方僵尸和模式道具沿用普通攻击，火把只烧植物。
	var burning_plant := value and _torch_lit and not is_hypno \
		and attack_component.detect_component.enemy_can_be_attacked is Plant000Base
	# 经过植物时暂停普通 DPS，防止同帧烧毁和啃咬。
	var biting := value and not burning_plant
	attack_component.set_physics_process(not burning_plant)
	move_component.update_move_factor(biting, MoveComponent.E_MoveFactor.IsAttack)
	hurt_box_component.change_area_attack_appear(biting)
	super(biting)
	_play_action(&"eat" if biting else &"walk")


## [param _delta] 本次物理帧时长；火把接触一次即结算，与帧长无关。
func _physics_process(_delta: float) -> void:
	if not _torch_lit:
		return
	_update_torch_reach()
	if is_hypno or not attack_component.is_enabling or not attack_component.is_attack_res \
		or not move_component.is_move or is_zero_approx(move_component.curr_speed):
		return
	# 保留检测组件选出的同一行植物及格内保护层优先顺序。
	var detector := attack_component.detect_component # 本实例的同行攻击检测器。
	var target := detector.enemy_can_be_attacked as Plant000Base # 格内实际受击的植物。
	if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion() \
		or (target.curr_be_attack_status & detector.can_attack_plant_status) == 0 \
		or target.hp_component.is_damage_immune():
		return
	_burn_plant(target)


## [param target] 本次触碰的可烧毁植物。沿用生命组件处理移除和格子占位。
func _burn_plant(target: Plant000Base) -> void:
	# 特效和声音在植物移除后继续播放，因此提前保存世界位置和层级。
	var burn_position := target.global_position + Vector2(0, -25)
	var burn_z_index := target.z_index + 1 # 在目标所在图层上方播放燃烧。
	target.is_can_death_language = false
	target.hp_component.Hp_loss_death(false)
	# 使用战场节点承载一次性燃烧动画，不受植物或僵尸后续移除影响。
	var effect := PLANT_BURN.instantiate() as Node2D
	Global.main_game.bullets.add_child(effect)
	effect.global_position = burn_position
	effect.z_index = burn_z_index
	# Wwise 原始事件为同一个样本随机调音，数值单位为音分。
	var pitch := pow(2.0, randf_range(-251.0, 347.0) / 1200.0)
	SoundManager.play_sfx_with_pool(TORCH_BURN_SFX, 0.0, pitch, false)


## [param time] 受寒冷效果减速的时间，单位为秒。
func be_ice_decelerate(time: float) -> void:
	_set_torch_lit(false)
	super(time)


## [param time] 冻结时长，单位为秒。
## [param new_time_ice_end_decelerate] 冻结结束后继续减速的时间，单位为秒。
func be_ice_freeze(time: float, new_time_ice_end_decelerate: float) -> void:
	_set_torch_lit(false)
	super(time, new_time_ice_end_decelerate)


## 受到有效火伤后解除冰冻并重新点燃火把。
func relight_from_fire() -> void:
	if is_death:
		return
	cancel_ice()
	_set_torch_lit(true)


## [param lit] 新的火把状态；只切换火焰图层及攻击范围，不打断身体动作。
func _set_torch_lit(lit: bool) -> void:
	if _torch_lit == lit or is_death:
		return
	_torch_lit = lit
	# 火焰精灵的帧内显隐由动画控制，独立透明度保留跨动作的熄灭状态。
	for part: Node in _visual.get_children():
		if part.is_in_group(&"explorer_torch_flame"):
			(part as Sprite2D).self_modulate.a = 1.0 if lit else 0.0
	_update_torch_reach()
	# 范围变化后清除原啃咬状态，由检测组件重新确认目标。
	attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.RayEnemy)
	attack_component.detect_component.need_judge = true


## 按原版后脚到火把头的距离前移攻击框，熄灭时恢复普通啃咬位置。
func _update_torch_reach() -> void:
	# 用美术缩放换算为攻击组件局部像素；根节点翻面会同步镜像碰撞框。
	var reach := minf(_torch_reach.position.x * _visual.scale.x, MAX_TORCH_REACH) if _torch_lit else 0.0
	var attack_x := _bite_center_x - reach # 只偏移攻击框，保留宽度和高度。
	if not is_equal_approx(_requested_attack_x, attack_x):
		_requested_attack_x = attack_x
		_attack_shape.set_deferred(&"position", Vector2(attack_x, _attack_shape.position.y))


## 原版啃咬动作合嘴时，触发共用啃咬反馈及道具交互。
func _on_eat_contact() -> void:
	if is_attack and not is_death:
		(attack_component as AttackComponentZombieNorm).attack_once()


## 普通死亡停止攻击和移动，从最后的头部位置抛出头部并播放原版倒地动作。
func _on_death() -> void:
	set_physics_process(false)
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	if not is_can_death_language:
		return
	signal_update_speed.disconnect(anim_component.owner_update_speed)
	_visual_animation.speed_scale = 1.0
	_head_drop.global_position = _head_anchor.global_position
	# 掉头停在地面上方半个头部高度，避免精灵陷入地面。
	var head_sprite := _head_drop.get_child(0) as Sprite2D
	_head_drop.ground_y = global_position.y - _head_drop.global_position.y \
		- head_sprite.texture.get_height() * head_sprite.global_transform.y.length() * 0.5
	_head_drop.visible = true
	_head_drop.acitvate_it()
	_play_action(&"die")


## [param action] 播放完成的原版动作；倒地完成后淡出。
func _on_visual_animation_finished(action: StringName) -> void:
	if action == &"die":
		_fade_and_remove()


## [param action] 原版动作名。立即应用首帧，避免残留上一动作的姿态。
func _play_action(action: StringName) -> void:
	if _visual_animation.current_animation != action or not _visual_animation.is_playing():
		_visual_animation.play(action)
		_visual_animation.advance(0.0)
