## 有限代星弹扇出；随机圆周间隙有硬下限，不使用可能卡死的拒绝采样。
extends RefCounted
class_name RepeaterStarFork

## 同次扇出任意相邻两颗星的最小角距，含圆周首尾。
const MIN_GAP: float = PI / 12.0

## [param parent] 为刚命中的弹体；[param target] 为本次直击目标。
## [param shot] 为同源战斗快照；[param generation] 零产生五颗一级星，一产生三颗二级星。
static func split(parent: Bullet000NormBase, target: Character000Base,
		shot: RepeaterShotContext, generation: int) -> void:
	if shot == null or not shot.is_active() or generation < 0 or generation >= 2:
		return
	var count: int = 5 if generation == 0 else 3 # 固定上界：总共最多五加十五颗，不允许递归到第三代。
	var angles: Array[float] = _angles(count) # 一次生成完整圆周布局，所有间隙均大于等于十五度。
	var kind: StringName = &"star_dark" if generation == 0 else &"star_light" # 每一代有独立颜色深浅。
	var damage: int = parent.attack_value if generation == 0 else roundi(float(parent.attack_value) * 0.5) # 只继承卡片后的基础伤害，不复制已修饰的目标伤害。
	var color_offset: int = randi_range(0, 4) # 随机起色，各同胞仍得到不同的颜色编号。
	for index: int in range(count): # 一次有界派生，二级星不再挂载分裂能力。
		var star: Bullet000NormBase = RepeaterProjectileFactory.create(kind, shot, damage,
			generation + 1, color_offset + index) # 新弹体共享来源快照，但命中表独立。
		if star == null:
			continue
		star.set("birth_target_id", target.get_instance_id() if is_instance_valid(target) else 0)
		var parameters: Dictionary = parent.get_bullet_paras() # 延续阵营状态、原行与来源上下文。
		parameters[Bullet000NormBase.E_InitParasAttr.Position] = shot.game.bullets.to_local(parent.global_position)
		parameters[Bullet000NormBase.E_InitParasAttr.Direction] = Vector2.from_angle(angles[index])
		parameters[Bullet000NormBase.E_InitParasAttr.IsActivateLane] = false
		parameters[Bullet000NormBase.E_InitParasAttr.DamageMultiplier] = 1.0
		parameters[Bullet000NormBase.E_InitParasAttr.AttackContext] = shot.attack_context
		star.init_bullet(parameters)
		star.call_deferred("attach_to_battle")

## [param count] 为本次有限扇出数；在十五度基础间隔外随机分配剩余角度并随机旋转整体。
static func _angles(count: int) -> Array[float]:
	var weights: Array[float] = [] # 连续随机间隙权重，不使用固定方向模板。
	var sum: float = 0.0 # 所有权重为正，归一化不会除零。
	for _index: int in range(count): # 每个间隙只抽签一次，不需要重试。
		var weight: float = randf_range(0.01, 1.0) # 保留极小正间隙，全部圆周角度必定分配完。
		weights.append(weight)
		sum += weight
	var angle: float = randf() * TAU # 整组随机旋转，不绑定任何屏幕方向。
	var spare: float = TAU - MIN_GAP * float(count) # 五颗或三颗时都有充足剩余弧度。
	var result: Array[float] = [] # 返回按圆周顺序排列的方向。
	for weight: float in weights: # 最后一个间隙同样受下限约束，保证跨零度边界的两颗不会贴合。
		result.append(angle)
		angle += MIN_GAP + spare * weight / sum
	return result
