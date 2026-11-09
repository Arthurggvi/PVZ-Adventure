extends Zombie000Base
class_name Zombie017Balloon

## 我是僵尸模式气球破裂的位置
@export var balloon_pop_glo_pos_x_in_zombie_mode:float = 50
@export_group("动画状态")
@export var is_pop:=false
signal balloon_landed()

func _ready() -> void:
	super()
	(hp_component as HpComponentZombie).configure_fragile_armor1(1)

func ready_norm():
	super()
	hurt_box_component.position.y -= 20

func _process(_delta: float) -> void:
	## 如果是我是僵尸模式
	if is_zombie_mode:
		if not is_pop and global_position.x < balloon_pop_glo_pos_x_in_zombie_mode:
			hp_component = hp_component as HpComponentZombie
			hp_component.apply_unblocked_loss(hp_component.curr_hp_armor1)

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	hp_component.signal_armor1_death.connect(balloon_pop)
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Balloon)

## 气球破裂
func balloon_pop():
	if not is_death:
		is_pop = true
		#hurt_box_component.position.y += 20
		move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsAnimGap)
		move_component.update_move_mode(MoveComponent.E_MoveMode.Ground)
		curr_be_attack_status = E_BeAttackStatusZombie.IsNorm
		SoundManager.play_character_SFX(&"balloon_pop")
		if curr_zombie_row_type == CharacterRegistry.ZombieRowType.Pool:
			# Death must not run inside the armor setter's death-signal emission;
			# defer landing/crash until the original received hit is fully settled.
			_finish_balloon_pop_in_pool.call_deferred()

func _finish_balloon_pop_in_pool() -> void:
	if is_death or is_queued_for_deletion():
		return
	balloon_landed.emit()
	if not is_death:
		character_death_disappear()

## 动画调用 气球破裂结束落地,可以移动
func balloon_pop_end():
	move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsAnimGap)
	attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Balloon)
	balloon_landed.emit()

## 被三叶草吹走
func be_blow_away():
	AdventureZombieWindGust.blow_target(self, 4, true)


## 被冰冻控制
func be_ice_freeze(time:float, new_time_ice_end_decelerate:float):
	be_ice_decelerate(time + new_time_ice_end_decelerate)
