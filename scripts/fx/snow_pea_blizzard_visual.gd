## 喀俄涅的横扫暴雪；单一画布绘制，不创建逐片粒子或碰撞体。
extends Node2D
class_name SnowPeaBlizzardVisual

## 0.60 秒横扫匹配击退，其后保留 0.12 秒尾风。
const LIFETIME: float = 0.72
## 暴雪的战场快照，阶段切换后表演立即结束。
var _battle: RepeaterShotContext
## 本行的横扫宽度，单位为世界像素。
var _width: float
## 风雪覆盖的半行高度，来自棋盘节距且不盖满邻行。
var _height: float
## 当前表现时间，菜单暂停不推进。
var _age: float = 0.0

## 在 [param battle] 的 [param lane] 显示以 [param origin] 为起点的横扫。
static func spawn(battle: RepeaterShotContext, origin: Vector2, lane: int) -> void:
	var visual := SnowPeaBlizzardVisual.new() # 全部雪片由此单画布绘制。
	visual._battle = battle
	visual._width = maxf(battle.cell_pitch.x * 3.0, BoardQueries.bounds(battle.board.row_cells(lane)).end.x - origin.x)
	visual._height = clampf(battle.cell_pitch.y * 0.32, 24.0, 40.0)
	visual.position = battle.game.bullets.to_local(origin)
	visual.z_index = lane * 50 + 47
	battle.game.bullets.add_child(visual)

## [param delta] 是有效战斗秒；淡出或阶段变化时释放画布。
func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME or not _battle.is_active():
		queue_free()
	else:
		queue_redraw()

## 三层薄雾风带先行，亮冰晶与细雪随后；前沿和尾部各自渐隐。
func _draw() -> void:
	var progress: float = clampf(_age / LIFETIME, 0.0, 1.0) # 全段动画归一化时间。
	var travel: float = smoothstep(0.0, 0.60, _age) # 横扫终点与一格击退共用完成时刻。
	var front: float = _width * travel # 所有霜雾只出现在已扫过的范围。
	var tail: float = maxf(0.0, front - minf(_width * 0.58, 310.0)) # 长行也不形成遮挡整排的蓝幕。
	var opacity: float = smoothstep(0.0, 0.10, progress) * (1.0 - smoothstep(0.74, 1.0, progress)) # 淡入短、尾风长。
	for band: int in range(3): # 上下风带细，中间雾带略厚，保留角色可读性。
		var ribbon := PackedVector2Array() # 每条风带使用连续弯曲折线，避免平行直线堆叠。
		for sample: int in range(19): # 固定采样成本，不随行宽增长。
			var along: float = float(sample) / 18.0 # 从尾部到前沿的归一化位置。
			var x: float = lerpf(tail, front, along) # 本段沿风方向的位置。
			var curl: float = sin(along * 4.2 + float(band) * 1.7 - progress * 5.0) # 错位弯曲形成层次。
			var y: float = (float(band) - 1.0) * _height * 0.54 + curl * 6.0 * sin(along * PI) # 不侵入相邻行。
			ribbon.append(Vector2(x, y))
		draw_polyline(ribbon, Color(0.57, 0.82, 0.92, opacity * 0.08), 8.0, true)
		draw_polyline(ribbon, Color(0.76, 0.94, 1.0, opacity * 0.20), 1.1, true)
	for index: int in range(9): # 柔边雾团分散在风带中，不构成实体色条。
		var along: float = float(index) / 9.0 # 雾团分布沿途由淡到亮。
		var point := Vector2(lerpf(tail, front, along), sin(float(index) * 2.4 + progress * 3.0) * _height * 0.42) # 轻微卷动。
		var size := Vector2(68.0 + along * 48.0, 20.0 + along * 15.0) # 横向柔雾突出扫行速度。
		draw_texture_rect(SnowPeaFrostVisual.mist_texture(), Rect2(point - size * 0.5, size),
			false, Color(0.70, 0.91, 1.0, opacity * (0.10 + along * 0.16)))
	for index: int in range(30): # 固定数量的细雪与冰晶共用画布，不受本行敌人数影响。
		var along: float = float(index * 37 % 97) / 96.0 # 互质散布避免雪片对齐成排。
		var x: float = lerpf(tail, front, along) # 尾端不越过起点。
		var y: float = (float(index * 19 % 67) / 33.0 - 1.0) * _height # 整行内的散布高度。
		y += sin(progress * 9.0 + float(index)) * 4.0
		var alpha: float = opacity * (0.26 + along * 0.62) # 前沿亮、尾风轻。
		if index % 3 == 0:
			SnowPeaFrostVisual.draw_shard(self, Vector2(x, y), 2.5 + float(index % 5), -0.14, alpha)
		else:
			draw_line(Vector2(x - 3.0 - float(index % 4), y + 0.7), Vector2(x, y),
				Color(0.90, 0.98, 1.0, alpha), 0.85, true)
