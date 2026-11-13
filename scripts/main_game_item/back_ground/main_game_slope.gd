## 战场屋顶高度的唯一查询入口，角色与连续弹道共用同一套区间规则。
extends Node2D
class_name MainGameSlope

## 按从左到右排列的斜面，保存各自的世界横向范围。
var all_slopes: Array[Slope] = []

## 收集场景声明的斜面顺序，忽略辅助节点；重新就绪时不重复追加。
func _ready() -> void:
	all_slopes.clear()
	for child: Node in get_children(): # 屋顶场景按从左到右组织斜面子节点。
		var part: Slope = child as Slope # 只保留提供坡面高度的节点。
		if part != null:
			all_slopes.append(part)

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
