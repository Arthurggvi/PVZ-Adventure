## 种植点命中区域；默认矩形与可选多边形共用相同鼠标入口。
extends Button

## [param point] 为按钮局部坐标，与所属 PlantCell 的局部几何一致。
func _has_point(point: Vector2) -> bool:
	var cell := get_parent() as PlantCell # 按钮始终是格子的直接子节点。
	return cell != null and cell.contains_local_point(point)
