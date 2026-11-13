## 持续场的受击区域查询；辉夜整场只做一次宽相查询，碎片再与真实碰撞形状核对。
extends RefCounted
class_name RepeaterFieldQueries

## 与原生植物弹体相同的真实受击层；索敌层会受坡面修正，不可代替实际接触。
const ENEMY_HURT_MASK: int = 512

## [param shot] 提供战场；[param position] 与 [param lane] 定位真实格距；[param cells] 是方形边长格数。
static func area(shot: RepeaterShotContext, position: Vector2, lane: int, cells: float) -> Array[Area2D]:
	if not shot.is_active():
		return []
	var profile := CombatExplosionProfile.new() # 复用唯一物理查询入口，不创建隐藏碰撞节点。
	var rectangle := RectangleShape2D.new() # 当前地形格距决定矩形尺寸。
	rectangle.size = shot.pitch_at(position, lane) * cells
	profile.shape = rectangle
	profile.collision_mask = ENEMY_HURT_MASK
	return CombatExplosion.query_areas(shot.game.get_world_2d().direct_space_state, profile, position)

## 为 [param fields] 的所有辉夜碎片返回按敌人身份去重的一次接触；跨场重叠也只保留一次。
static func kaguya_contacts(fields: Array[RepeaterFieldState]) -> Dictionary[int, Dictionary]:
	var contacts: Dictionary[int, Dictionary] = {} # 同一60Hz时刻的唯一受伤资格。
	var samples: Array[Dictionary] = [] # 每个场只计算一次解析碎片位置与边界。
	var bounds := Rect2() # 整场辉夜并集的宽相范围。
	var game: MainGameManager = null # 所有有效场必须属于当前战场。
	for field: RepeaterFieldState in fields: # 地狱场不参加辉夜去重。
		if field.kind != &"kaguya" or not field.shot.is_active() or not is_instance_valid(field.visual):
			continue
		var points: PackedVector2Array = field.visual.get_fragment_positions_at(minf(field.age, field.lifetime - 0.00001)) # 末尾时刻仍兑现最后一跳。
		if points.is_empty():
			continue
		var center: Vector2 = field.center_at(field.age) # 可见星屑与碰撞共享同一位置函数。
		var circle := CircleShape2D.new() # 半径由可见星屑模块声明，装饰闪光不扩大命中。
		circle.radius = field.visual.get_fragment_radius()
		var box := Rect2(points[0] + center, Vector2.ZERO) # 从真实第一颗碎片开始合并。
		for index: int in range(points.size()): # 仅转换局部点，不修改视觉模块内部数组。
			points[index] += center
			box = box.expand(points[index])
		box = box.grow(circle.radius)
		bounds = box if samples.is_empty() else bounds.merge(box)
		samples.append({"field": field, "points": points, "circle": circle, "bounds": box})
		game = field.shot.game
	if samples.is_empty() or not is_instance_valid(game):
		return contacts
	var profile := CombatExplosionProfile.new() # 所有场共用一次空间宽相查询。
	var rectangle := RectangleShape2D.new() # 只负责候选集合，不直接授予伤害。
	rectangle.size = bounds.size
	profile.shape = rectangle
	profile.collision_mask = ENEMY_HURT_MASK
	var areas: Array[Area2D] = CombatExplosion.query_areas(game.get_world_2d().direct_space_state, profile, bounds.get_center()) # 查询饱和时公共入口自动扩容。
	var eligible: Dictionary[int, bool] = {} # 保留公共攻击资格，不以碰撞形状猜测阵营。
	for target: Character000Base in CombatExplosion.plant_blast_targets(areas, -1, -1, 31): # 允许空间命中的多行Boss。
		eligible[target.get_instance_id()] = true
	for hit_area: Area2D in areas: # 同一角色的多个受击盒只消费一个接触资格。
		if not is_instance_valid(hit_area) or not is_instance_valid(hit_area.owner):
			continue
		var target: Character000Base = hit_area.owner as Character000Base # 设施可受普通伤害，不能接受缠怨等负面。
		if target == null:
			continue
		var identity: int = target.get_instance_id() # 统一按角色身份去重。
		if not eligible.has(identity) or contacts.has(identity):
			continue
		for sample: Dictionary in samples: # 先包围盒剔除，再核对每个真实形状。
			if _touches(hit_area, sample):
				contacts[identity] = {"target": target, "shot": (sample.field as RepeaterFieldState).shot}
				break
	return contacts

## 判断 [param area] 的有效碰撞形状是否接触 [param sample] 的任一可见碎片。
static func _touches(area: Area2D, sample: Dictionary) -> bool:
	for child: Node in area.get_children(): # 原生受击框直接持有CollisionShape2D，不克隆物理实体。
		var shape_node: CollisionShape2D = child as CollisionShape2D # 禁用或空形状不参与命中。
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var target_bounds: Rect2 = shape_node.global_transform * shape_node.shape.get_rect() # 世界包围盒只作无损快速剔除。
		if not (sample.bounds as Rect2).intersects(target_bounds):
			continue
		for point: Vector2 in sample.points: # 最终判断使用原形状，而非矩形覆盖猜测。
			if (sample.circle as CircleShape2D).collide(Transform2D(0.0, point), shape_node.shape, shape_node.global_transform):
				return true
	return false
