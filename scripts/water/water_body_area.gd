## 水体物理区域的统一协议。视觉材质和水体接触均通过同一份区域数据构建。
## 原版泳池和冒险水沟都使用此类型，游泳组件不再识别特定关卡或 Pool 场景。
extends Area2D
class_name WaterBodyArea

## 只作为可检测水域；不主动检测或阻挡其他物理对象。
func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	monitoring = false
	monitorable = true

## 从区域构造一个精确的水体碰撞矩形，坐标与底图一致。
## [param region] 父节点空间中的水域矩形。
static func from_region(region: Rect2) -> WaterBodyArea:
	assert(region.size.x > 0.0 and region.size.y > 0.0)
	var water := WaterBodyArea.new()
	water.position = region.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = region.size
	collision.shape = shape
	water.add_child(collision)
	return water
