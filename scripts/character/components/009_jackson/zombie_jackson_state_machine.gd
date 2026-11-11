extends Node
## 舞王状态机,与舞王相关节点高度耦合，就这一个用状态机的，不想写太麻烦的代码
class_name JacksonStateMachine

## 战斗专用的单次滑步动画，与循环播放的展示动画隔离。
const ENTRANCE_ANIMATION := &"battle/moonwalk"
## 从伴舞出场起保持召唤姿势的战斗秒数。
const SUMMON_HOLD_SECONDS := 2.0

@onready var animation_player: AnimationPlayer = $"../AnimationPlayer"
@onready var charred_component: CharredComponent = %CharredComponent
@onready var attack_component: AttackComponentZombieNorm = %AttackComponent
@onready var move_component: MoveComponent = %MoveComponent
@onready var node_drop: Node2D = %NodeDrop

@onready var zombie_009_jackson: Zombie009Jackson = $".."
var jackson_manager: JacksonManager

## 舞王动画状态
enum E_JacksonStatus{
	Enter,	## 入场状态
	Point,	## 打响指和召唤后停留状态
	Norm,	## 正常移动、跳舞状态（该状态下舞王管理器管理）
	Attack,	## 攻击状态
	Death,	## 死亡状态
}

@export var curr_jackson_status = E_JacksonStatus.Norm
## 召唤后的剩余停留秒数；负数表示本次响指尚未触发出怪。
var _summon_hold_remaining := -1.0

## 仅在召唤后的停留期间逐帧计时。
func _ready() -> void:
	set_process(false)

## 初始化状态机，舞王根节点调用。
## [param init_status] 入场滑步、出土或直接加入舞步的初始状态。
func init_state(init_status:E_JacksonStatus):
	curr_jackson_status = init_status
	animation_player.set_blend_time('armraise', 'walk', 0.2)
	if init_status != E_JacksonStatus.Enter:
		jackson_manager.start_anim()
		allow_dance()
		return

	attack_component.update_attack_value(0, AttackComponentZombieNorm.E_AttackValueFactor.JacksonEnter)
	if zombie_009_jackson is Zombie010Dancer:
		zombie_009_jackson.update_direction_x_body(1)
		animation_player.play(&"pose_be_call")
		zombie_009_jackson.sync_dance_movement()
		return

	zombie_009_jackson.update_direction_x_body(-1)
	# 每次自然播完滑步才消耗一轮；撞到植物或死亡会提前离开入场状态。
	for _walk_index in range(zombie_009_jackson.num_moon_walk):
		animation_player.play(ENTRANCE_ANIMATION)
		animation_player.seek(0)
		# 切换动画后收到的结束信号可能来自响指或死亡动画。
		var finished_anim: StringName = await animation_player.animation_finished
		if curr_jackson_status != E_JacksonStatus.Enter or finished_anim != ENTRANCE_ANIMATION:
			return
	begin_first_summon()

## 结束舞王入场并开始首召，供滑步播完或碰到植物时调用。
func begin_first_summon() -> void:
	if curr_jackson_status != E_JacksonStatus.Enter or zombie_009_jackson is Zombie010Dancer:
		return
	change_jackson_anim_status(E_JacksonStatus.Enter, E_JacksonStatus.Point)
	jackson_manager.start_anim()

## 改变舞王动画状态，忽略已经失效的转换请求。
## [param ori_value] 调用方要求的当前状态。
## [param new_value] 要切换到的状态。
func change_jackson_anim_status(ori_value:E_JacksonStatus, new_value:E_JacksonStatus):
	if curr_jackson_status != ori_value or ori_value == new_value or ori_value == E_JacksonStatus.Death:
		return
	move_component._walking_end()
	curr_jackson_status = new_value
	if ori_value == E_JacksonStatus.Attack:
		attack_component.update_attack_value(0, AttackComponentZombieNorm.E_AttackValueFactor.JacksonEnter)
	if ori_value == E_JacksonStatus.Point:
		set_process(false)
	if new_value != E_JacksonStatus.Death and (
			new_value == E_JacksonStatus.Point or ori_value == E_JacksonStatus.Point
			or (ori_value == E_JacksonStatus.Enter and zombie_009_jackson is Zombie010Dancer)):
		zombie_009_jackson.sync_dance_movement()
	enter_status(new_value)

## 记录响指轨道已触发召唤；每次进入召唤状态只接受一次。
## 返回是否允许调用舞团管理器生成援军。
func begin_summon_hold() -> bool:
	if curr_jackson_status != E_JacksonStatus.Point or _summon_hold_remaining >= 0.0:
		return false
	_summon_hold_remaining = SUMMON_HOLD_SECONDS
	set_process(true)
	return true

## 等伴舞出土期间保持召唤状态，硬控时暂停计时。
## [param delta] 自上一帧经过的战斗秒数。
func _process(delta: float) -> void:
	if is_zero_approx(animation_player.speed_scale):
		return
	_summon_hold_remaining = maxf(0.0, _summon_hold_remaining - delta)
	if _summon_hold_remaining == 0.0 and animation_player.current_animation != &"point":
		change_jackson_anim_status(E_JacksonStatus.Point, judge_curr_status())

## 进入新状态，切换动画和啃食伤害。
## [param new_value] 已写入状态机的新状态。
func enter_status(new_value:E_JacksonStatus):
	match new_value:
		E_JacksonStatus.Point:
			_summon_hold_remaining = -1.0
			animation_player.play(&"point")
			zombie_009_jackson.update_direction_x_body(1)
		E_JacksonStatus.Norm:
			allow_dance()

		E_JacksonStatus.Attack:
			## 修改攻击力为原始值
			attack_component.update_attack_value(1, AttackComponentZombieNorm.E_AttackValueFactor.JacksonEnter)
			animation_player.play(&"eat", -1, 2)
			#zombie_009_jackson.body.scale = Vector2(1,1)
			zombie_009_jackson.body.scale = Vector2(
				abs(zombie_009_jackson.body.scale.x) * sign(1),
				abs(zombie_009_jackson.body.scale.y) * sign(1)
			)
		E_JacksonStatus.Death:
			animation_player.play(&"death", 0.2)

## 判断当前状态(召唤僵尸动画、入场结束后调用)
func judge_curr_status() -> JacksonStateMachine.E_JacksonStatus:
	if zombie_009_jackson.is_death:
		return JacksonStateMachine.E_JacksonStatus.Death
	if zombie_009_jackson.is_attack:
		return JacksonStateMachine.E_JacksonStatus.Attack

	return JacksonStateMachine.E_JacksonStatus.Norm

## 从特殊状态（舞王入场、攻击）修改跟随跳舞
func allow_dance():
	var anim_info = jackson_manager.get_current_animation_info()
	anim_play(anim_info['name'], anim_info['curr_scale'], anim_info['current_time'], anim_info['speed'], true)

## 舞王管理器管理动画播放
## Norm状态更新
func anim_play(anim_name, curr_scale, start_time, _speed, is_follow:=false):
	if curr_jackson_status == E_JacksonStatus.Norm:
		move_component._walking_end()
		## 如果是唤伴舞动画,入场标志已结束使用，这里重复使用一下
		if anim_name == "point":
			change_jackson_anim_status(curr_jackson_status, E_JacksonStatus.Point)
			return
		## 最后一次举手需要举起，舞王管理器重新创建了新动画控制播放时间
		if anim_name == "armraise_end":
			anim_name = "armraise"

		if is_follow:
			animation_player.play_section(anim_name, start_time, -1, 0.2)
		else:
			animation_player.play(anim_name)
			animation_player.seek(0)

		## 控制舞王方向
		zombie_009_jackson.update_direction_x_body(curr_scale.x)

		if anim_name == "walk":
			#await get_tree().create_timer(0.1).timeout
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			if curr_jackson_status == E_JacksonStatus.Norm and animation_player.current_animation == &"walk":
				move_component._walking_start()

