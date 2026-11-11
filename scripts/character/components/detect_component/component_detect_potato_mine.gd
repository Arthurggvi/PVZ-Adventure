## 土豆雷沿用通用重叠检测，并按僵尸的撑杆、跳杆和蹦极状态筛选引爆目标。
extends DetectComponent

## [param enemy] 与检测区重叠的角色；返回其当前是否可以触发土豆雷。
func _judge_enemy_is_can_be_attack(enemy: Character000Base) -> bool:
	if not super._judge_enemy_is_can_be_attack(enemy) or enemy.is_hypno:
		return false
	if enemy is Zombie019Pogo and enemy.is_pogo:
		# 跳杆可能在检测区内被取走，而僵尸不会重新进入检测区。
		need_judge = true
		return false
	if enemy is Zombie004PoleVaulter and enemy.jump_component.has_remaining_jumps():
		return false
	if enemy is Zombie021Bungi:
		if enemy.plant_cell != (owner as Plant000Base).plant_cell:
			return false
		# 蹦极受击框早于落地开启，等身体到达目标格才允许触雷。
		if not enemy.is_drop_end:
			need_judge = true
			return false
	return true
