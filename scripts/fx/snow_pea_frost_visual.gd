## 寒冰专属的柔雾与双切面冰晶笔刷；所有动画共享小纹理，不创建逐片节点。
extends RefCounted
class_name SnowPeaFrostVisual

## 无硬边的霜雾纹理，首次战斗表现需要时生成。
static var _mist: GradientTexture2D
## 窄冰晶的完整轮廓，尖端朝向局部右方。
static var _crystal: PackedVector2Array = PackedVector2Array([
	Vector2(-0.72, 0.0), Vector2(-0.12, -0.30), Vector2(1.0, 0.0), Vector2(-0.12, 0.40),
])
## 朝光的上侧切面，与暗部共用一条中轴。
static var _lit_facet: PackedVector2Array = PackedVector2Array([
	Vector2(-0.72, 0.0), Vector2(-0.12, -0.30), Vector2(1.0, 0.0),
])

## 返回透明边缘的霜雾笔刷；缓存只含 64 像素纹理，不保存战场引用。
static func mist_texture() -> GradientTexture2D:
	if _mist == null:
		var gradient := Gradient.new() # 三段柔化消除圆形贴片边界。
		gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.65, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.78), Color(1, 1, 1, 0.46),
			Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.0)])
		_mist = GradientTexture2D.new()
		_mist.width = 64
		_mist.height = 64
		_mist.fill = GradientTexture2D.FILL_RADIAL
		_mist.fill_from = Vector2(0.5, 0.5)
		_mist.fill_to = Vector2(1.0, 0.5)
		_mist.gradient = gradient
	return _mist

## 在 [param canvas] 的 [param point] 绘制半长 [param size] 的冰晶。
## [param angle] 为弧度朝向；[param opacity] 为透明度；结束时恢复画布绘制变换。
static func draw_shard(canvas: Node2D, point: Vector2, size: float, angle: float, opacity: float) -> void:
	canvas.draw_set_transform(point, angle, Vector2.ONE * size)
	canvas.draw_colored_polygon(_crystal, Color(0.32, 0.68, 0.82, opacity * 0.70))
	canvas.draw_colored_polygon(_lit_facet, Color(0.77, 0.95, 1.0, opacity * 0.88))
	canvas.draw_line(Vector2(-0.58, 0.0), Vector2(0.90, 0.0),
		Color(0.94, 1.0, 1.0, opacity), 0.7 / maxf(size, 0.1), true)
	canvas.draw_set_transform(Vector2.ZERO)
