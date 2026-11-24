## 雪面固定时间步的唯一调度器：将一次完整像素计算分摊到相邻渲染帧。
extends RefCounted
class_name SnowSurfaceStepClock

## 固定步长秒数，决定天气模拟速度，不受帧率影响。
var _interval: float = 0.2
## 尚未派发的游戏时间，上限为两个完整固定步。
var _pending: float = 0.0
## 唯一雪面状态拥有者，脚印的局部写入由它记录并最终重放。
var _state: SnowSurfaceState
## 只在雪面完成一笔固定步后同步处理压痕与雪沿。
var _imprints: SnowSurfaceImprints

## 同场初始化一次，[param state] 与 [param imprints] 不得跨战斗混用。
func configure(state: SnowSurfaceState, imprints: SnowSurfaceImprints) -> void:
	_state = state
	_imprints = imprints

## 更改 [param seconds] 固定模拟步长，先完成旧步再允许新画质重采样。
func set_interval(seconds: float) -> void:
	if _state != null and _state.has_pending_step():
		if _state.finish_step(_state.eligible_count()):
			_imprints.advance(_interval, _state.refill_rates())
	_interval = seconds
	_pending = minf(_pending, _interval)

## [param delta] 为本帧游戏秒；[param snow]、[param wind] 与正式输入完全相同。
## 每帧只消费一批雪地像素，渲染纹理在整步完成后原子替换。
func advance(delta: float, snow: float, wind: float) -> void:
	if _state == null or _imprints == null or _interval <= 0.0:
		return
	var seconds: float = maxf(0.0, delta) # 禁止负数导致累积状态倒退。
	_pending = minf(_interval * 2.0, _pending + seconds)
	var budget: int = maxi(1024, ceili(float(_state.eligible_count()) *
		maxf(seconds, 1.0 / 120.0) / _interval)) # 由帧间隔决定本帧最多处理的雪地像素。
	if _state.has_pending_step():
		var used: int = mini(budget, _state.remaining_step_cells()) # 只扣实际更新的像素。
		if _state.finish_step(used):
			_imprints.advance(_interval, _state.refill_rates()) # 同一固定步交接雪痕回填。
		budget -= used
	while budget > 0 and not _state.has_pending_step() and _pending >= _interval:
		_pending -= _interval
		if not _state.begin_step(_interval, clampf(snow, 0.0, 1.0), clampf(wind, 0.0, 1.0)):
			_imprints.advance(_interval, _state.refill_rates()) # 无有效雪地仍推进历史雪痕。
			continue
		var used: int = mini(budget, _state.remaining_step_cells()) # 上一笔剩余预算归还后可进入下一笔。
		if _state.finish_step(used):
			_imprints.advance(_interval, _state.refill_rates())
		budget -= used
