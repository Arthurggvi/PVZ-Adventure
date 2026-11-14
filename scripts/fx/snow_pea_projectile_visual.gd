## 寒冰弹的清透晶面与方向霜尾；只读取弹体状态，不参与移动、伤害或寒冷结算。
extends Node2D

## 所属原生或转职寒冰弹；随弹体释放，不留下常驻粒子。
var _bullet: Bullet002PeaSnow
## 深寒使用偏蓝的芯部与更长的细尾，亮边仍保持冰白。
var _deep_cold: bool = false
## 棱锥使用尖锐折面，普通弹保留原生圆形雪豆纹理。
var _prism: bool = false
## 出膛后的表现秒数，暂停时不推进；用于让尾迹短暂长出。
var _age: float = 0.0
## 每枚弹的微光相位，避免齐射时全部同步闪烁。
var _phase: float = 0.0

## 读取发射前已冻结的状态；场景中独立挂载，原版与转职共用同一表现。
func _ready() -> void:
	_bullet = get_parent() as Bullet002PeaSnow
	if _bullet == null:
		set_process(false)
		return
	_deep_cold = _bullet.promotion_shot != null and _bullet.promotion_shot.loadout.has(&"deep_cold")
	_prism = _bullet.is_prism
	_phase = float(get_instance_id() % 37) * 0.17
	rotation = _bullet.direction.angle()
	queue_redraw()

## [param delta] 为有效表现秒；尾迹跟随真实发射方向，不假定向右或同一行。
func _process(delta: float) -> void:
	_age += delta
	rotation = _bullet.direction.angle()
	position = _bullet.body.position
	queue_redraw()

## 每枚只绘制两条渐细霜丝、一个尾端碎晶和少量表面高光，保持僵尸轮廓可读。
func _draw() -> void:
	if _bullet == null:
		return
	var onset: float = clampf(_age / 0.13, 0.0, 1.0) # 出膛约八帧内长出霜尾，不在枪口突然铺开。
	var length: float = (43.0 if _prism else (39.0 if _deep_cold else 29.0)) * onset # 尾迹最大长度小于半格。
	var cold: Color = Color(0.35, 0.68, 1.0, 0.46) if _deep_cold else Color(0.47, 0.87, 0.98, 0.38) # 雾色保留透明度。
	var bright: Color = Color(0.88, 0.98, 1.0, 0.80) # 高光集中在细线，不使用覆盖整个弹体的光晕。
	var shimmer: float = 0.83 + 0.17 * sin(_age * 7.0 + _phase) # 缓慢轻微闪烁，避免频繁白闪。
	if length > 12.0:
		# 四顶点薄片从透明尾尖过渡到窄霜核，反向与斜向发射同样正确。
		draw_polygon(PackedVector2Array([Vector2(-length, 0.0), Vector2(-12.0, -2.7), Vector2(-7.0, 0.0), Vector2(-12.0, 2.7)]),
			PackedColorArray([Color(cold, 0.0), cold, Color(cold, 0.15), cold]))
		_draw_filament(Vector2(-length * 0.92, -1.8), Vector2(-9.0, -5.0), Color(bright, 0.55 * onset * shimmer))
		_draw_filament(Vector2(-length * 0.70, 2.0), Vector2(-10.0, 4.5), Color(cold, 0.56 * onset))
		if _deep_cold or _prism:
			_draw_shard(Vector2(-length * 0.69, -3.4), 1.8, Color(bright, 0.55 * onset * shimmer))
	if _prism:
		# 长轴白脊与短小反光让冰锥有厚度，原有几何承担主体颜色。
		draw_line(Vector2(-10.0, -0.5), Vector2(13.0, -0.5), Color(bright, 0.78), 0.85, true)
		draw_line(Vector2(-3.0, -4.5), Vector2(8.0, -1.2), Color(bright, 0.75 * shimmer), 0.8, true)
		return
	# 圆形雪豆仍以原画为主，只叠一小块半透明冰面和上缘反光。
	draw_colored_polygon(PackedVector2Array([Vector2(-4.0, -5.0), Vector2(1.0, -8.0), Vector2(6.5, -3.0), Vector2(1.0, -1.0)]),
		Color(0.77, 0.94, 1.0, 0.22 if _deep_cold else 0.14))
	draw_arc(Vector2.ZERO, 8.0, -2.50, -0.75, 9, Color(bright, 0.65 * shimmer), 0.9, true)
	if _deep_cold:
		draw_line(Vector2(-4.0, 2.0), Vector2(1.5, -1.0), Color(0.71, 0.90, 1.0, 0.55), 0.85, true)
		_draw_shard(Vector2(5.0, -5.0), 2.3, Color(bright, 0.74 * shimmer))

## [param start] 至 [param finish] 形成一条渐亮细霜丝；[param tint] 只在头端达到完整透明度。
func _draw_filament(start: Vector2, finish: Vector2, tint: Color) -> void:
	var side: Vector2 = (finish - start).normalized().orthogonal() * 0.45 # 仅零点九像素宽，保持连续细尾。
	draw_polygon(PackedVector2Array([start, finish + side, finish - side]),
		PackedColorArray([Color(tint, 0.0), tint, tint]))

## 在 [param point] 绘制半长为 [param size] 的四尖晶屑；[param tint] 包含本帧透明度。
func _draw_shard(point: Vector2, size: float, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([point + Vector2(-size, 0.0), point + Vector2(0.0, -size * 0.45),
		point + Vector2(size, 0.0), point + Vector2(0.0, size * 0.45)]), tint)
