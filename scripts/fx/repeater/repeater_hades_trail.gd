## 冥弹的灰白幽影尾迹：固定样本、单画布绘制、并发自动降级，不干预子弹运动。
extends Node2D
class_name RepeaterHadesTrail

## 原40点压缩到24点，密集弹幕时不再不断重建四套曲线。
const MAX_SAMPLES: int = 24
## 统一采样间隔（战斗秒），独立于渲染帧率。
const SAMPLE_STEP: float = 1.0 / 45.0
## 限制世界空间烟痕长度，不因速度或帧率变化而无限延伸。
const MAX_LENGTH: float = 170.0

## 子弹原生可见身体，只有位置依赖。
var _body: Node2D
## 截断的世界坐标历史。
var _history := PackedVector2Array()
## 上一帧弹头坐标，用于时间采样插值。
var _previous: Vector2
## 下一个时间采样前的剩余秒数。
var _sample_age: float = 0.0
## 用于烟丝错相的可暂停显示时间。
var _age: float = 0.0
## 最近一次真正重绘的显示秒数。
var _last_draw: float = -1.0
## 弹头不可见后保持旧纹理渐隐，不再重新生成尾迹。
var _stopped: bool = false

## 读取真实弹头坐标并生成一个固定长度队列；父类负责退场淡化。
func configure(body: Node2D) -> void:
	_body = body
	_previous = body.global_position
	_history.append(_previous)

## 进入场景才计算活跃尾迹，未挂载而释放的对象不泄漏预算。
func _enter_tree() -> void:
	RepeaterVisualBudget.enter(&"trail")

## 弹体结束、跨轮或释放时归还预算。
func _exit_tree() -> void:
	RepeaterVisualBudget.leave(&"trail")

## 低开销轨迹采样；不再在每个渲染帧里逐点复制多条PackedArray。
func _process(delta: float) -> void:
	_age += delta
	if not _stopped and is_instance_valid(_body) and _body.is_inside_tree() \
			and not _body.is_queued_for_deletion() and _body.is_visible_in_tree():
		var now: Vector2 = _body.global_position # 运动真实来源，不在尾迹内部推进弹体。
		_sample_age += delta
		var count: int = mini(MAX_SAMPLES, floori(_sample_age / SAMPLE_STEP))
		for i: int in range(count):
			var t: float = float(i + 1) / float(maxi(count, 1))
			_history.append(_previous.lerp(now, t))
			if _history.size() > MAX_SAMPLES:
				_history.remove_at(0)
		_sample_age = fposmod(_sample_age, SAMPLE_STEP)
		while _history.size() > 2 and _history[0].distance_to(now) > MAX_LENGTH:
			_history.remove_at(0)
		_previous = now
	else:
		_stopped = true
	if _last_draw < 0.0 or _age - _last_draw >= RepeaterVisualBudget.interval():
		_last_draw = _age
		queue_redraw()

## 单次绘制完成灰色幽影、黑色主轨迹与冷白裂丝；低预算不额外创建节点。
func _draw() -> void:
	var sample_count: int = _history.size()
	if sample_count < 2:
		return
	var quality: int = RepeaterVisualBudget.quality()
	var stride: int = 1 if quality == RepeaterVisualBudget.FULL else (2 if quality == RepeaterVisualBudget.MEDIUM else 3)
	var path := PackedVector2Array()
	for i: int in range(0, sample_count, stride):
		path.append(to_local(_history[i])) # 映射至目前真实尾迹画布，不修改历史采样。
	path.append(to_local(_history[-1])) # 永远精确连接到本次弹头，不因跳点断线。
	var ashes := PackedColorArray()
	var grey := PackedColorArray()
	var glow := PackedColorArray()
	for i: int in range(path.size()):
		var weight: float = float(i) / float(maxi(path.size() - 1, 1))
		ashes.append(Color(0.025, 0.027, 0.045, 0.63 * pow(weight, 1.2))) # 黑色剪影主脊。
		grey.append(Color(0.44, 0.47, 0.60, 0.65 * pow(weight, 1.4))) # 灰白幽烟。
		glow.append(Color(0.86, 0.91, 1.0, 0.79 * weight * weight)) # 极细银白灵丝。
	draw_polyline_colors(path, ashes, 13.0, true)
	if quality != RepeaterVisualBudget.CHEAP:
		draw_polyline_colors(path, grey, 5.5, true)
	draw_polyline_colors(path, glow, 1.6, true)
	if quality == RepeaterVisualBudget.CHEAP:
		return
	var wisp := PackedVector2Array()
	for i: int in range(path.size()):
		var previous: Vector2 = path[maxi(0, i - 1)]
		var after: Vector2 = path[mini(path.size() - 1, i + 1)]
		var vector: Vector2 = (after - previous).normalized()
		var normal := Vector2(-vector.y, vector.x)
		var phase: float = float(i) * 0.53 - _age * 5.0 # 同一轨迹上的细丝呈水波状，不随机跳跃。
		wisp.append(path[i] + normal * (5.0 + sin(phase) * 2.5))
	draw_polyline(wisp, Color(0.60, 0.70, 0.88, 0.47), 1.1, true)
	if quality == RepeaterVisualBudget.FULL:
		var head: Vector2 = path[-1] # 很淡的幽灵余辉指向弹头，身体仍使用原版豌豆。
		draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(head - Vector2.ONE * 15.0, Vector2.ONE * 30.0),
			false, Color(0.62, 0.67, 0.84, 0.22))
