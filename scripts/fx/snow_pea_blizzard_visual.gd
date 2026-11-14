## 喀俄涅的横扫暴雪；单一画布绘制，不创建逐片粒子或碰撞体。
extends Node2D
class_name SnowPeaBlizzardVisual

## 暴雪表现持续的战斗秒数。
const LIFETIME: float = 0.48
## 暴雪的战场快照，阶段切换后表演立即结束。
var _battle: RepeaterShotContext
## 本行的横扫宽度，单位为世界像素。
var _width: float
## 当前表现时间，菜单暂停不推进。
var _age: float = 0.0

## 在 [param battle] 的 [param lane] 显示以 [param origin] 为起点的横扫。
static func spawn(battle: RepeaterShotContext, origin: Vector2, lane: int) -> void:
	var visual := SnowPeaBlizzardVisual.new() # 全部雪片由此单画布绘制。
	visual._battle = battle
	visual._width = maxf(battle.cell_pitch.x * 3.0, BoardQueries.bounds(battle.board.row_cells(lane)).end.x - origin.x)
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

## 用雪线和密集浅蓝雪点表现横向风向及覆盖行。
func _draw() -> void:
	var progress: float = clampf(_age / LIFETIME, 0.0, 1.0) # 从弹口横扫到行末。
	var opacity: float = sin(progress * PI) # 随横扫渐显渐隐。
	for index: int in range(24): # 每次暴雪固定数量，避免随僵尸数量分配粒子。
		var x: float = _width * clampf(progress * 1.45 - (index % 8) * 0.061, 0.0, 1.0) # 雪线头部位置。
		var y: float = (float(index * 17 % 58) - 29.0) * (0.4 + progress * 0.6) # 从枪口向本行展开。
		var length: float = float(9 + index * 13 % 28) # 不同长度使速度方向清晰。
		draw_line(Vector2(x - length, y), Vector2(x, y - 2.0), Color(0.61, 0.89, 1.0, opacity * 0.76), 1.5, true)
		draw_circle(Vector2(x + 4.0, y), 1.25, Color(0.91, 0.98, 1.0, opacity))
