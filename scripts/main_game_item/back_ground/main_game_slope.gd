## 战场地形高度的唯一查询入口，角色与连续弹道共用同一套区间规则。
extends Node2D
class_name MainGameSlope

## 多段地形的行走按跨步两端采样，避免到达坡顶或坡脚时积累高度误差。
var sample_walking_height: bool = false

## 按从左到右排列的斜面，保存各自的世界横向范围。
var all_slopes: Array[Slope] = []

## 收集场景声明的斜面顺序，忽略辅助节点；重新就绪时不重复追加。
func _ready() -> void:
	all_slopes.clear()
	for child: Node in get_children(): # 屋顶场景按从左到右组织斜面子节点。
		var part: Slope = child as Slope # 只保留提供坡面高度的节点。
		if part != null:
			all_slopes.append(part)

## 仅保留最初 [param remaining] 行的坡面阻挡。逻辑行号和斜率采样保持稳定。
func limit_collision_rows(remaining: int) -> void:
	for part: Slope in all_slopes: # 两段坡面分别装有各行碰撞区。
		for lane: int in range(remaining, part.all_slope_area_real.size()): # 退去的行不会再挡弹。
			var area: Area2D = part.all_slope_area_real[lane] # 区域仍保有原来的索引供老弹查询。
			if is_instance_valid(area):
				area.set_deferred(&"collision_layer", 0)
				area.set_deferred(&"monitorable", false)
## 沿 [param start] 到 [param finish] 查询 [param lane] 首个迎面地形交点，无碰撞时返回原终点。
## [param include_roof] 为真时旧屋顶表面也遮挡；普通飞弹按碰撞层只阻挡实体坡。
func first_projectile_contact(start: Vector2, finish: Vector2, lane: int, include_roof: bool = false) -> Vector2:
	var first: Vector2 = finish # 路径缩短后继续查询，处理多坡或不按距离编排的几何。
	for part: Slope in all_slopes: # 使用原生每行碰撞线，不从贴图或格宽猜碰撞。
		if not is_instance_valid(part) or (not include_roof and not part.solid_for_projectiles) \
				or lane < 0 or lane >= part.all_slope_area_real.size():
			continue
		var surface: Area2D = part.all_slope_area_real[lane] # 此行真实世界坐标，已沉没行停用。
		if not is_instance_valid(surface) or not surface.monitorable or surface.collision_layer == 0:
			continue
		var a: Vector2 = surface.to_global(part.start_pos_slope) # 原碰撞线段左端。
		var b: Vector2 = surface.to_global(part.end_pos_slope) # 原碰撞线段右端。
		var normal: Vector2 = Vector2((b - a).y, (a - b).x) # 相对斜面的地面上方，保留单向接触规则。
		if (first - start).dot(normal) >= 0.0:
			continue
		var contact: Variant = Geometry2D.segment_intersects_segment(start, first, a, b) # 朝地面进入才裁切。
		if contact is Vector2:
			first = contact
	return first

## 返回 [param global_x] 对应的坡面相对高度；没有斜面时为零。
## 精确端点归入斜面本身；分离斜面的间隙延续前坡末端，左右外侧延续最近端点。
func get_all_slope_y(global_x: float) -> float:
	var previous_end: float = 0.0 # 已经过的最后一个斜面末端高度。
	var has_previous: bool = false # 区分首坡左侧与两个斜面之间的平段。
	for reference: Variant in all_slopes: # 斜面可能在场景清理中释放，先验证再进行有类型的访问。
		if not is_instance_valid(reference):
			continue
		var part: Slope = reference # 当前仍存在的斜面。
		var bounds: Vector2 = part.slope_global_pos_x_range # 当前斜面的世界横向闭区间。
		if global_x < bounds.x:
			return previous_end if has_previous else part.start_pos_slope.y
		if global_x <= bounds.y:
			return part.get_slope_y(global_x) if bounds.y > bounds.x else part.end_pos_slope.y
		previous_end = part.end_pos_slope.y
		has_previous = true
	return previous_end
