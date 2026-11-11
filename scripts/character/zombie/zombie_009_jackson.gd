extends Zombie000Base
class_name Zombie009Jackson
## 舞王僵尸

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var jackson_manager: JacksonManager
signal dance_manager_replaced(manager: JacksonManager)
@onready var state_machine: JacksonStateMachine = $StateMachine
## 动画初始速度
var animation_origin_speed:float
## 舞王入场滑步次数
@export var num_moon_walk := 2
## 伴舞僵尸编号,舞王为-1
var dancer_id:int= -1
## 是否已成功召唤过援军；魅惑更换舞团管理器后仍按后续召唤计算间隔。
var has_summoned_reinforcements := false
#region 重写父类的方法

#region 初始化相关
## 初始化正常出战角色
func ready_norm():
	super()
	_init_dance()

## 初始化展示角色
func ready_show():
	super()
	_init_show_jackon()

## 舞王展示角色初始化，伴舞重写
func _init_show_jackon():
	animation_player.play("moonwalk")
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.InitType)

## 舞王出场动画，伴舞继承重写
func _init_dance():
	jackson_manager = SceneRegistry.JACKSON_MANAGER.instantiate()
	add_child(jackson_manager)
	jackson_manager.zombie_dancers[-1] = self
	dance_manager_replaced.emit(jackson_manager)
	state_machine.jackson_manager = jackson_manager
	# 战斗使用非循环滑步；图鉴和白公爵仍使用原有的循环资源。
	var battle_library := AnimationLibrary.new()
	# 只复制滑步，避免修改展示和首领场景共用的动画。
	var moonwalk := animation_player.get_animation(&"moonwalk").duplicate() as Animation
	moonwalk.loop_mode = Animation.LOOP_NONE
	battle_library.add_animation(&"moonwalk", moonwalk)
	animation_player.add_animation_library(&"battle", battle_library)
	## 初始化状态为入场状态
	state_machine.init_state(JacksonStateMachine.E_JacksonStatus.Enter)

## 随机初始化角色速度,继承重写
func init_random_speed():
	## 初始化角色速度
	update_speed_factor(randf_range(random_speed_range.x, random_speed_range.y), E_Influence_Speed_Factor.InitRandomSpeed)
	animation_origin_speed = anim_component.get_animation_origin_speed()
	jackson_manager.init_anim_speed(animation_origin_speed, influence_speed_factors.get(E_Influence_Speed_Factor.InitRandomSpeed, randf_range(random_speed_range.x, random_speed_range.y)))

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	hp_component.signal_hp_component_death.connect(func():
		state_machine.change_jackson_anim_status(state_machine.curr_jackson_status, JacksonStateMachine.E_JacksonStatus.Death)
	)

#endregion



#region 修改速度
## 修改速度，发射信号
## 继承重写该方法，速度变化时将速度变化结果给舞王管理器，舞王管理器选择最小速度作为真实速度,调用manager_update_anim_speed方法
func update_speed_factor(value: float, change_speed_factor:E_Influence_Speed_Factor) -> void:
	if is_death:
		return
	influence_speed_factors[change_speed_factor] = value
	jackson_manager.change_speed_factor_product(dancer_id, GlobalUtils.get_dic_product(influence_speed_factors))

## 舞王由管理器修改速度
func manager_update_anim_speed(speed_factor_product:float):
	signal_update_speed.emit(speed_factor_product)
#endregion


#region 攻击相关
## 改变攻击状态攻击
func change_is_attack(value:bool):
	is_attack = value
	if is_attack:
		start_attack()
	else:
		end_attack()

## 获得攻击目标；舞王入场时遇到植物会立即开始首召。
func start_attack():
	if state_machine.curr_jackson_status == state_machine.E_JacksonStatus.Enter and dancer_id == -1 \
			and attack_component.detect_component.enemy_can_be_attacked is Plant000Base:
		state_machine.begin_first_summon()
		return
	if state_machine.curr_jackson_status == state_machine.E_JacksonStatus.Norm:
		state_machine.change_jackson_anim_status(state_machine.curr_jackson_status, state_machine.E_JacksonStatus.Attack)

	sync_dance_movement()

## 失去攻击目标；召唤和出土完成时再根据最新目标决定是否啃食。
func end_attack():
	if is_death:
		return
	if state_machine.curr_jackson_status == JacksonStateMachine.E_JacksonStatus.Attack:
		state_machine.change_jackson_anim_status(JacksonStateMachine.E_JacksonStatus.Attack, JacksonStateMachine.E_JacksonStatus.Norm)
	sync_dance_movement()

## 将当前角色能否移动同步给舞团，保持召唤和伴舞出土期间的位置。
func sync_dance_movement() -> void:
	# 当前状态决定角色是否在原地表演召唤动作。
	var status: JacksonStateMachine.E_JacksonStatus = state_machine.curr_jackson_status
	# 舞王滑步时可移动，伴舞的入场则是在原地出土。
	var must_hold := status == JacksonStateMachine.E_JacksonStatus.Point \
			or (status == JacksonStateMachine.E_JacksonStatus.Enter and dancer_id != -1)
	jackson_manager.change_move(dancer_id, not must_hold and move_component.get_exclude_dancer_move_res())

## 舞王管理器调用该方法控制移动，只在滑步或行走动画期间推进。
## [param curr_is_move] 舞团是否允许移动。
func update_move(curr_is_move):
	move_component.update_move_factor(not curr_is_move, MoveComponent.E_MoveFactor.IsDancerAttack)
	if animation_player.current_animation not in [&"walk", JacksonStateMachine.ENTRANCE_ANIMATION]:
		move_component._walking_end()
#endregion

#region 动画相关
## 动画结束处判断是否死亡，循环动画不发射动画结束信号，在动画轨道调用该函数
func anim_judge_death():
	if is_death:
		animation_player.play("death")
#endregion

## 角色死亡
func character_death():
	## 更新舞王管理器对应id僵尸速度和对应僵尸
	dancer_manager_change()
	## 死亡时修改自身速度，避免死亡时被伴舞被定住无法播放死亡动画删除自己
	signal_update_speed.emit(influence_speed_factors.get(E_Influence_Speed_Factor.InitRandomSpeed, 1))
	super()

## 僵尸更新舞王管理器，并更新舞王管理器父节点
func dancer_manager_change():
	## 更新舞王管理器对应id僵尸速度和对应僵尸
	jackson_manager.change_speed_factor_product(dancer_id, influence_speed_factors.get(E_Influence_Speed_Factor.InitRandomSpeed, randf_range(random_speed_range.x, random_speed_range.y)))
	jackson_manager.zombie_dancers[dancer_id] = null
	## 更新舞王管理器的移动
	jackson_manager.change_move(dancer_id, true)

	## 或者是当前持有dancer_manager的伴舞僵尸死亡
	if jackson_manager.curr_master_id == dancer_id:
		jackson_manager.change_manager_parent()

## 僵尸被魅惑
func be_hypno():
	jackson_be_hypno()
	super()

## 舞王被魅惑额外操作
func jackson_be_hypno():
	print("舞王或被魅惑")
	dancer_manager_change()

	jackson_manager = SceneRegistry.JACKSON_MANAGER.instantiate()
	state_machine.jackson_manager = jackson_manager
	add_child(jackson_manager)
	jackson_manager.zombie_dancers[-1] = self
	dance_manager_replaced.emit(jackson_manager)
	jackson_manager.init_anim_speed(animation_origin_speed, influence_speed_factors.get(E_Influence_Speed_Factor.InitRandomSpeed, randf_range(random_speed_range.x, random_speed_range.y)))
	jackson_manager.start_anim()
	jackson_manager.is_hypnotized = true

	if state_machine.curr_jackson_status == JacksonStateMachine.E_JacksonStatus.Point:
		sync_dance_movement()
	state_machine.allow_dance()

#endregion

## 舞王管理器管理动画播放
## Norm状态更新
func anim_play(anim_name, curr_scale, start_time, speed):
	state_machine.anim_play(anim_name, curr_scale, start_time, speed)

## 召唤动画的响指轨道调用，生成援军并开始原地停留。
func call_zombie_dancer():
	if not is_death and state_machine.begin_summon_hold():
		jackson_manager.call_zombie_dancer()
