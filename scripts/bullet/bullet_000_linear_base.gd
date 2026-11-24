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
	if not is_attack_active():
		queue_free()
		return
	## 调用移动组件控制移动
	movement_component.physics_process_bullet_move(delta)

	## 移动超过最大距离后销毁，部分子弹有限制
	if global_position.distance_to(start_world_position) > max_distance:
		_finish_projectile(ExitCause.RANGE)

## 改变y位置(三线调用)
func change_y(target_y:float):
	var tween = create_tween()
	var start_y = global_position.y
	tween.tween_method(func(y):
		global_position.y = y,
		start_y,
		target_y,
		0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## 处理 [param area] 的碰撞；从地面上方撞入斜面时播放本弹体的撞地效果。
func _on_area_2d_attack_area_entered(area: Area2D) -> void:
	var slope := area.owner as Slope # 世界层碰撞区域归属于实际坡面。
	if slope != null:
		if is_queued_for_deletion() or direction.dot(slope.normal_vector_slope) >= 0.0:
			return
		if slope.solid_for_projectiles:
			if is_activate_lane and lane >= 0 and slope.all_slope_area_real.find(area) != lane:
				return
			# 弹体边缘接触时，将撞击特效贴到本行坡面。
			global_position = Geometry2D.get_closest_point_to_segment(global_position,
				area.to_global(slope.start_pos_slope), area.to_global(slope.end_pos_slope))
		attack_once(null)
		if slope.solid_for_projectiles and not is_queued_for_deletion():
			_finish_projectile(ExitCause.TERRAIN)
		return
	elif area.owner is Character000Base:
		#print("碰撞到角色")
		super(area)

## [param plant] 是实际命中实体；保留普通层优先级并覆盖不占位伴生植物。
func get_first_be_hit_plant_in_cell(plant: Plant000Base) -> Plant000Base:
	return first_plant_in_cell(plant)

## 从 [param plant] 所在格解析敌方投射物能命中的保护层。[param shell_first] 保留直线和抛射各自的顺序。
static func first_plant_in_cell(plant: Plant000Base, shell_first: bool = true) -> Plant000Base:
	if not is_instance_valid(plant) or not is_instance_valid(plant.plant_cell):
		return null
	var cell: PlantCell = plant.plant_cell # 从当前命中格子解析保护层。
	var shell := CharacterRegistry.PlacePlantInCell.Shell # 直线投射先遇到壳层。
	var normal := CharacterRegistry.PlacePlantInCell.Norm # 抛射优先直击本体。
	for slot: CharacterRegistry.PlacePlantInCell in ([shell, normal] if shell_first else [normal, shell]): # 保持原先覆盖顺序。
		var candidate: Variant = cell.plant_in_cell.get(slot) # 前一回调可能已经移除了该层。
		if is_instance_valid(candidate) and not candidate.is_death and not candidate.is_queued_for_deletion() \
				and not candidate.battle_hidden_from_zombies:
			return candidate as Plant000Base
	var companion: Plant000Base = cell.first_companion_plant(
		func(entry: Plant000Base) -> bool: return not entry.battle_hidden_from_zombies) # 可索敌伴生仍可被直击。
	if companion != null:
		return companion
	var support: Variant = cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Down) # 最后才命中承托物。
	if is_instance_valid(support) and not support.is_death and not support.is_queued_for_deletion() \
			and not support.battle_hidden_from_zombies:
		return support as Plant000Base
	return null
