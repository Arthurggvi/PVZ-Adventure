## 滑雪接触的只读查询；逻辑行判同路，真实碰撞几何提供世界横向边界，不比较坡面世界Y。
extends RefCounted
class_name SkiObstacleQuery

## 雪板前端局部锚点，比原生五十像素咬合略早触发；根节点翻转会自动改变前方。
const FRONT_LOCAL: Vector2 = Vector2(-52.0, 0.0)
## 雪板后端局部锚点；同一障碍完全离开整段雪板后才解除接触。
const REAR_LOCAL: Vector2 = Vector2(20.0, 0.0)
## 世界横向接触余量，允许物理步及图像边缘的微小间隙。
const CONTACT_MARGIN: float = 4.0
## 没有任何真实碰撞和可见贴图时的普通实体局部轮廓，仍保留角色世界缩放。
const FALLBACK_RECT: Rect2 = Rect2(-20.0, -80.0, 40.0, 80.0)

## 返回 [param source] 在 [param game] 当前地块的世界横向宽度；没有有效地块时返回零。
static func cell_width(source: Zombie000Base, game: MainGameManager) -> float:
	if not _valid_context(source, game):
		return 0.0
	var cell: PlantCell = game.board.nearest_cell(source.global_position, source.lane) # 按当前脚点选择，兼容不等宽格子。
	if not is_instance_valid(cell) or cell.is_queued_for_deletion() or cell.board != game.board:
		return 0.0
	var width: float = absf(cell.get_global_transform().basis_xform(Vector2(cell.size.x, 0.0)).x) # 根翻转及平台缩放后仍取世界横向长度。
	return width if is_finite(width) and width > 0.0 else 0.0

## 返回 [param source] 前方 [param reach_cells] 格内最近的冻结实体；[param game] 提供当前战场登记。
## [param consumed_contact] 为仍接触但已经借力的实体，排除它以免遮住紧邻的下一块冰障。
## [param known_width] 为调用方本次物理步刚计算的真实格宽；负数时使用原始动态查询。
## 已接触对象优先，完全落在雪板后方的对象排除；返回真实植物或雪人小鬼，不返回冰壳代理。
static func nearest(source: Zombie000Base, game: MainGameManager, reach_cells: float = 1.0,
		consumed_contact: Character000Base = null, known_width: float = -1.0) -> Character000Base:
	if not _valid_context(source, game) or not is_finite(reach_cells) or reach_cells < 0.0:
		return null
	var width: float = known_width if is_finite(known_width) and known_width >= 0.0 \
		else cell_width(source, game) # 同一物理步复用精确格宽，禁止跨帧缓存平台坐标。
	var skis: Vector2 = _ski_ends(source) # x为前端，y为后端；保留前后顺序供镜像方向判定。
	var forward: float = signf(skis.x - skis.y) # 正常朝左为负，根翻转后为正。
	if width <= 0.0 or is_zero_approx(forward):
		return null
	var candidates: Array[Character000Base] = [] # 当前同路的实体快照，不持久缓存可死亡的对象。
	for cell: PlantCell in game.board.row_cells(source.lane): # 每一层植物都可能独立冻结，不只读取主体槽。
		if is_instance_valid(cell) and not cell.is_queued_for_deletion() and cell.board == game.board \
				and game.board.cell_by_id(cell.cell_id) == cell:
			for plant: Plant000Base in cell.plant_entities(): # 单次列举即可；有效性与冻结状态仍由后续 _eligible 统一校验。
				candidates.append(plant)
	if is_instance_valid(game.zombie_manager) and source.lane < game.zombie_manager.all_zombies_2d.size():
		for zombie: Zombie000Base in game.zombie_manager.all_zombies_2d[source.lane]: # 冰块包括穴居人推完后停住的同一实体。
			if zombie is Zombie031YetiImp:
				candidates.append(zombie)
	var result: Character000Base = null # 没有合格对象时不进入滑雪接近状态。
	var best_gap: float = INF # 已接触统一为零，避免前方未接触对象抢走实际接触者。
	var best_center_distance: float = INF # 多个接触者重叠时选择离本体较近者。
	for obstacle: Character000Base in candidates: # 每次读取资格，破甲或解冻后不继续作为踏板。
		if obstacle == consumed_contact or not _eligible(source, obstacle) or not game.is_ancestor_of(obstacle):
			continue
		var outline: Rect2 = bounds(obstacle) # 真实碰撞框已包含坡高、角色缩放和局部偏移。
		if not outline.has_area():
			continue
		var ahead_edge: float = outline.position.x if forward < 0.0 else outline.end.x # 障碍最靠行进方向的一边。
		if (ahead_edge - skis.y) * forward < -CONTACT_MARGIN:
			continue
		var entry_edge: float = outline.end.x if forward < 0.0 else outline.position.x # 雪板将首先接触的障碍边。
		var gap: float = maxf(0.0, (entry_edge - skis.x) * forward) # 有符号前向间隙；重叠不产生负排序距离。
		if gap > width * reach_cells + CONTACT_MARGIN:
			continue
		var center_distance: float = absf(outline.get_center().x - source.global_position.x) # 不让世界高度改变同路接触排序。
		if gap < best_gap or (is_equal_approx(gap, best_gap) and center_distance < best_center_distance):
			result = obstacle
			best_gap = gap
			best_center_distance = center_distance
	return result

## 返回 [param source] 的整段雪板是否仍接触 [param obstacle]；解冻、死亡或换行立即失去踏板资格。
## 只比较世界横向区间，保持高低差地图的逻辑同路语义；用于同一障碍的重复起跳抑制。
static func is_touching(source: Zombie000Base, obstacle: Character000Base) -> bool:
	if not _eligible(source, obstacle):
		return false
	var skis: Vector2 = _ski_ends(source) # 两端可能因魅惑或恐惧互换左右位置。
	var outline: Rect2 = bounds(obstacle) # 拒绝失效几何，不把空矩形误当原点附近的接触。
	return outline.has_area() and outline.end.x >= minf(skis.x, skis.y) - CONTACT_MARGIN \
		and outline.position.x <= maxf(skis.x, skis.y) + CONTACT_MARGIN

## 读取 [param obstacle] 的真实受击形状并转换成世界包围框；缺失时依次使用可见身体、普通实体轮廓。
static func bounds(obstacle: Character000Base) -> Rect2:
	if not is_instance_valid(obstacle) or not obstacle.is_inside_tree() or obstacle.is_queued_for_deletion():
		return Rect2()
	var result: Rect2 = Rect2() # 不把世界原点混入第一个有效形状。
	var area: Area2D = obstacle.hurt_box_component.hurt_box_real if is_instance_valid(obstacle.hurt_box_component) else null # 植物和冰小鬼沿用同一真实受击入口。
	if is_instance_valid(area) and area.get_child_count() == 1:
		var sole: CollisionShape2D = area.get_child(0) as CollisionShape2D # 常规植物仅有一个受击形状。
		if sole != null and not sole.disabled and sole.shape != null:
			var direct: Rect2 = sole.global_transform * sole.shape.get_rect() # 与通用合并路径完全相同的实际世界矩形。
			if direct.position.is_finite() and direct.size.is_finite() and direct.has_area():
				return direct # 已经是唯一有效形状，无需构建子数组和递归外观轮廓。
	if is_instance_valid(area):
		for child: Node in area.get_children(): # 同一受击区可由多个实体专属形状组成。
			if child is CollisionShape2D:
				var collider: CollisionShape2D = child as CollisionShape2D # Shape2D包围框包含胶囊、矩形、圆及已有多边形类型。
				if not collider.disabled and collider.shape != null:
					result = _merge(result, collider.global_transform * collider.shape.get_rect())
			elif child is CollisionPolygon2D:
				var polygon: CollisionPolygon2D = child as CollisionPolygon2D # 顶点逐一变换，兼容旋转与镜像。
				if polygon.disabled or polygon.polygon.is_empty():
					continue
				var polygon_bounds: Rect2 = Rect2(polygon.to_global(polygon.polygon[0]), Vector2.ZERO) # 从真实首顶点开始扩展。
				for point: Vector2 in polygon.polygon: # 不修改现有碰撞顶点。
					polygon_bounds = polygon_bounds.expand(polygon.to_global(point))
				result = _merge(result, polygon_bounds)
	if result.has_area():
		return result
	result = _body_bounds(obstacle.body, Rect2())
	return result if result.has_area() else _merge(Rect2(), obstacle.global_transform * FALLBACK_RECT)

## 验证 [param source] 与 [param obstacle] 的同路活体资格，只接纳真正冻结的植物或完整冻结小鬼。
static func _eligible(source: Zombie000Base, obstacle: Character000Base) -> bool:
	if not is_instance_valid(source) or not source.is_inside_tree() or source.is_death or source.is_queued_for_deletion() \
			or source.lane < 0 or not source.global_position.is_finite() \
			or not is_instance_valid(obstacle) or not obstacle.is_inside_tree() or obstacle == source \
			or obstacle.is_death or obstacle.is_queued_for_deletion() or obstacle.lane != source.lane:
		return false
	if obstacle is Plant000Base:
		return obstacle.is_cold_frozen()
	return obstacle is Zombie031YetiImp and (obstacle as Zombie031YetiImp).is_frozen_block()

## 返回 [param source] 两端的世界X；Vector2.x存前端，Vector2.y存后端，二者不是世界点的XY。
static func _ski_ends(source: Zombie000Base) -> Vector2:
	return Vector2(source.to_global(FRONT_LOCAL).x, source.to_global(REAR_LOCAL).x)

## 验证 [param source] 仍属于 [param game] 的当前棋盘行，不读取或替换全局战场。
static func _valid_context(source: Zombie000Base, game: MainGameManager) -> bool:
	return is_instance_valid(source) and source.is_inside_tree() and not source.is_death and not source.is_queued_for_deletion() \
		and source.global_position.is_finite() and source.global_transform.x.is_finite() and source.global_transform.y.is_finite() \
		and is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() and game.is_ancestor_of(source) \
		and is_instance_valid(game.board) and game.board.configured and source.lane >= 0 and source.lane < game.board.lanes.size()

## 将有效的世界矩形 [param addition] 合入 [param current]；空矩形保持无效，不扩到世界原点。
static func _merge(current: Rect2, addition: Rect2) -> Rect2:
	if not addition.position.is_finite() or not addition.size.is_finite() or not addition.has_area():
		return current
	return current.merge(addition) if current.has_area() else addition

## 仅在没有真实碰撞时遍历 [param node] 的可见身体贴图，将世界绘图范围合入 [param current]。
static func _body_bounds(node: Node, current: Rect2) -> Rect2:
	if not is_instance_valid(node):
		return current
	if node is Sprite2D:
		var sprite: Sprite2D = node as Sprite2D # 原骨架植物使用当前绘图矩形。
		if sprite.texture != null and sprite.is_visible_in_tree() and sprite.self_modulate.a > 0.0:
			current = _merge(current, sprite.global_transform * sprite.get_rect())
	elif node is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = node as AnimatedSprite2D # 导入原帧僵尸只读取当前帧，不复制贴图。
		if sprite.sprite_frames != null and sprite.is_visible_in_tree() and sprite.self_modulate.a > 0.0 \
				and sprite.sprite_frames.has_animation(sprite.animation) and sprite.frame < sprite.sprite_frames.get_frame_count(sprite.animation):
			var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame) # 未配置的帧留给最终后备轮廓。
			if texture != null:
				var frame: Rect2 = Rect2(sprite.offset, texture.get_size()) # 保留偏移和居中规则。
				if sprite.centered:
					frame.position -= frame.size * 0.5
				current = _merge(current, sprite.global_transform * frame)
	for child: Node in node.get_children(): # 只读身体树，不生成或改动其他节点。
		current = _body_bounds(child, current)
	return current
