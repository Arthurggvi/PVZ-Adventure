## 一次释放后的世界坐标轨迹快照；不持有地块、生成者或管理器节点。
extends RefCounted
class_name ImpThrowPlan

## 交给生成管理器的行基线脚点；基类就绪时仍负责补上屋顶高度。
var spawn_position: Vector2
## 小鬼释放时的空中脚点，世界像素，Y 向下。
var release_position: Vector2
## 出手时确定的目标地面脚点，不随种植平台追踪移动。
var landing_position: Vector2
## 飞行持续的动作秒数；暂停与动作减速只影响采样时钟。
var duration: float
## 抛物线的上抬系数，乘以进度与剩余进度；中点抬高为此值的四分之一。
var arc_lift: float


## 返回轨迹是否完整且有限；调用者必须在创建小鬼前排除无效计划。
func is_valid() -> bool:
	return spawn_position.is_finite() and release_position.is_finite() \
		and landing_position.is_finite() and is_finite(duration) and duration > 0.0 \
		and is_finite(arc_lift) and arc_lift >= 0.0


## 按累计 [param elapsed] 动作秒解析采样空中脚点，超出时长时精确停在终点。
func sample(elapsed: float) -> Vector2:
	var progress: float = clampf(elapsed / duration, 0.0, 1.0) # 时间截断避免末帧越过地面和房屋。
	return release_position.lerp(landing_position, progress) \
		+ Vector2.UP * arc_lift * progress * (1.0 - progress)
