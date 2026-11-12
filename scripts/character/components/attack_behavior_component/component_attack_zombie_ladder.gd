extends AttackComponentZombieNorm
class_name AttackComponentZombieLadder

## 是否可以搭梯子
var is_can_ladder:=true
## 发射搭梯子信号
signal signal_ladder(plant:Plant000Base)

func _physics_process(delta: float) -> void:
	if is_enabling and is_attack_res and not owner.is_stunned():
		frame_counter = wrapi(frame_counter + 1, 0, 8)
		if not is_instance_valid(detect_component.enemy_can_be_attacked):
			return
		if frame_counter==0 and is_instance_valid(detect_component.enemy_can_be_attacked):
			## 如果可以搭梯子
			if is_can_ladder:
				## 如果有可以被搭梯子的植物
				var plant_ladder = get_plant_can_ladder(detect_component.enemy_can_be_attacked)
				if is_instance_valid(plant_ladder):
					is_can_ladder = false
					signal_ladder.emit(plant_ladder)
					return
			_apply_bite(detect_component.enemy_can_be_attacked, int(curr_attack_value_per_min * delta * 8))


## 判断是否可以给敌人挂梯子
func get_plant_can_ladder(enemy:Character000Base) -> Plant000Base:
	if enemy is Plant000Base:
		var ladder_zombie: Zombie022Ladder = owner as Zombie022Ladder
		if is_instance_valid(ladder_zombie) and ladder_zombie.allow_any_ladder_target \
				and is_instance_valid(enemy.plant_cell) \
				and not is_instance_valid(enemy.plant_cell.ladder):
			return enemy
		## 挂载梯子的植物
		var plant_ladder:Plant000Base= enemy.plant_cell.get_plant_ladder()
		if is_instance_valid(plant_ladder):
			return plant_ladder

	return null
