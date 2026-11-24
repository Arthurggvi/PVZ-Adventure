extends Zombie000Base
class_name Zombie022Ladder

## 当前可以被搭梯子的植物
var plant_ladder:Plant000Base
var allow_any_ladder_target := false
signal ladder_placed(plant: Plant000Base, ladder_entity: Ladder)
@onready var zombie_ladder_1: Sprite2D = $Body/BodyCorrect/Ladder/Zombie_ladder_1

@export_group("动画")
@export var is_place_ladder:bool=false
@export var is_drop_ladder:= false
## 搭梯子失败
@export var is_fail_ladder:=false

## 初始化正常出战角色信号连接
func ready_norm_signal_connect():
	super()
	hp_component.signal_armor2_death.connect(drop_ladder)
	attack_component = attack_component as AttackComponentZombieLadder
	attack_component.signal_ladder.connect(start_ladder)

## 梯子掉落
func drop_ladder():
	is_drop_ladder = true
	attack_component = attack_component as AttackComponentZombieLadder
	attack_component.is_can_ladder = false
	attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Anim)

	move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsAnimGap)
	var recovery: Tween = create_action_tween(self) # 掉梯后经过同等动作时长才能继续走路。
	recovery.tween_interval(0.2)
	await recovery.finished
	move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsAnimGap)


## 检测到可以搭梯子的植物,开始搭梯子,
func start_ladder(plant:Plant000Base):
	plant_ladder = plant
	is_place_ladder = true
	attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Anim)
	is_fail_ladder = false
	SoundManager.play_character_SFX(&"ladder_zombie")

## 搭梯子,同时搭梯子动画结束
func ladder_once():
	# 动画期间可能被沉默，末端重新验证原生目标资格，不能把普通梯子搭在任意植物上。
	if not are_tier_skills_active() and is_instance_valid(plant_ladder) \
			and is_instance_valid(plant_ladder.plant_cell) \
			and plant_ladder.plant_cell.get_plant_ladder() != plant_ladder:
		is_fail_ladder = true
		is_place_ladder = false
		(attack_component as AttackComponentZombieLadder).is_can_ladder = not is_drop_ladder
		attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Anim)
		return
	if is_instance_valid(plant_ladder) and not plant_ladder.plant_cell.ladder and not is_drop_ladder:
		var placed: Ladder = plant_ladder.plant_cell.be_ladder(
				adventure_tier_id if are_tier_skills_active() else &"", plant_ladder)
		if is_instance_valid(placed):
			ladder_placed.emit(plant_ladder, placed)
		hp_component.apply_unblocked_loss(hp_component.curr_hp_armor2, BulletRegistry.AttackMode.Norm, false, false, false)
	else:
		is_fail_ladder = true
		is_place_ladder = false
	attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Anim)
