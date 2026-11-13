extends Bullet000NormBase
class_name BulletLinear000Base
## 直线移动子弹基类

## 线性移动组件
@onready var movement_component: BulletMovementLinear = $MovementComponent

## 对僵尸敌人造成伤害,直线类子弹重写
func _attack_zombie(zombie:Zombie000Base):
	## 从后面攻击僵尸的子弹，正常伤害类型子弹攻击类型修改为真实
	if direction.x < 0 and bullet_mode ==BulletRegistry.AttackMode.Norm:
		## 攻击敌人
		_hit_zombie(zombie, BulletRegistry.AttackMode.Real)
	else:
		## 攻击敌人
		_hit_zombie(zombie, bullet_mode)


func _physics_process(delta: float) -> void:
	# 同场景切换冒险阶段后，旧来源弹体在恢复物理处理时立即回收。
	if attack_context != null and not attack_context.is_active():
		queue_free()
		return
	## 调用移动组件控制移动
	movement_component.physics_process_bullet_move(delta)

	## 移动超过最大距离后销毁，部分子弹有限制
	if global_position.distance_to(start_pos) > max_distance:
		queue_free()

## 改变y位置(三线调用)
func change_y(target_y:float):
	var tween = create_tween()
	var start_y = global_position.y
	tween.tween_method(func(y):
		global_position.y = y,
		start_y,
		target_y,
		0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## 子弹与敌人碰撞,直线子弹检测是否有斜面,判断是否与斜面碰撞
func _on_area_2d_attack_area_entered(area: Area2D) -> void:
	## 线性子弹判断是否攻击到斜坡,非穿透子弹
	if area.owner is Slope:
		#if bullet_mode !=BulletRegistry.AttackMode.Penetration:
		var slope:Slope = area.owner
		## 如果方向与斜面法向量夹角小于90度
		if direction.dot(slope.normal_vector_slope) < 0:
			attack_once(null)
		return
	elif area.owner is Character000Base:
		#print("碰撞到角色")
		super(area)

## [param plant] 是实际命中实体；保留普通层优先级并覆盖不占位伴生植物。
func get_first_be_hit_plant_in_cell(plant: Plant000Base) -> Plant000Base:
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	var cell: PlantCell = plant.plant_cell # 从当前命中格子解析保护层。
	for slot: CharacterRegistry.PlacePlantInCell in [CharacterRegistry.PlacePlantInCell.Shell,
			CharacterRegistry.PlacePlantInCell.Norm]: # 原有两种弹道保留各自的优先顺序。
		var candidate: Variant = cell.plant_in_cell.get(slot) # 前一回调可能已经移除了该层。
		if is_instance_valid(candidate) and not candidate.is_death and not candidate.is_queued_for_deletion():
			return candidate as Plant000Base
	var companion: Plant000Base = cell.first_companion_plant() # 伴生可被子弹直接命中。
	if companion != null:
		return companion
	var support: Variant = cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Down) # 最后才命中承托物。
	if is_instance_valid(support) and not support.is_death and not support.is_queued_for_deletion():
		return support as Plant000Base
	return null
