## 将巨人的投掷意图转换为一组安全轨迹；地图几何、力度和生成生命周期各自独立。
extends RefCounted
class_name ImpThrowPlanner

## 基础重力，单位为战场局部像素/动作秒²；角色体型不改变战斗时钟。
const GRAVITY: float = 500.0
## 基础横向飞行速度，单位为战场局部像素/动作秒。
const HORIZONTAL_SPEED: float = 300.0
## 释放锚点相对巨人脚点的美术偏移，X 沿朝向、Y 向下。
const RELEASE_OFFSET := Vector2(133.0, -88.0)
## 力度基准距当前朝向的阵地边缘的实际格宽数。
const WINDUP_DEPTH: float = 4.0
## 家门前保留的实际格宽数，独立于割草机是否存在。
const HOME_CLEARANCE: float = 2.0
## 坡面转折处的最小空中余量，单位为世界像素。
const SLOPE_CLEARANCE: float = 1.0


## 查询 [param game] 中 [param giant] 是否存在向前投掷空间；不抽随机数或修改任何状态。
static func can_throw(game: MainGameManager, giant: Zombie000Base) -> bool:
	if not is_instance_valid(giant) or not _has_row(game, giant.lane):
		return false
	var geometry: BoardLandingGeometry = BoardLandingGeometry.capture(game.board, giant.lane) # 即时地图几何。
	if geometry.spans.is_empty():
		return false
	var forward_x: float = -signf(giant.direction_x_root) # 角色朝向转换为游戏世界的 X 方向。
	var origin_x: float = _release_x(game, giant, forward_x) # 真实出手横坐标。
	var ahead: float = (_forward_edge_x(geometry.bounds, forward_x) - giant.global_position.x) * forward_x # 脚点至朝向一侧的边缘距离。
	var bounds: Vector2 = _ahead_landing_bounds(_safe_landing_bounds(game, geometry), origin_x, forward_x, geometry.pitch) # 原生长抛须向前留半格。
	return ahead > (WINDUP_DEPTH + 0.5) * geometry.pitch \
		and is_finite(geometry.nearest_x(origin_x, bounds.x, bounds.y))


## 为 [param giant] 在 [param game] 中规划 [param count] 只小鬼。
## [param allow_short_throw] 允许下砸近身时向安全阵地短抛；[param scatter] 为整组共用的 0 到 1 随机量。
## 空行、结束的战局或无安全落点返回空组，不生成实体；释放后的轨迹不追踪种植平台。
static func plan_volley(game: MainGameManager, giant: Zombie000Base, count: int,
		allow_short_throw: bool, scatter: float) -> Array[ImpThrowPlan]:
	var plans: Array[ImpThrowPlan] = [] # 同一释放帧的完整计划，先规划后生成。
	if count <= 0 or not is_instance_valid(giant) or not _has_row(game, giant.lane) \
			or not game.zombie_manager.is_game_running():
		return plans
	var geometry: BoardLandingGeometry = BoardLandingGeometry.capture(game.board, giant.lane) # 世界坐标快照。
	if geometry.spans.is_empty():
		return plans
	var scale_size: Vector2 = giant.global_scale.abs() # 角色体型只决定释放锚点和高度。
	var field_scale: Vector2 = game.global_scale.abs() # 飞行速度按战场缩放，小体型不会把飞行时长翻倍。
	if not scale_size.is_finite() or not field_scale.is_finite() or minf(scale_size.x, scale_size.y) <= 0.0 \
			or minf(field_scale.x, field_scale.y) <= 0.0 or not is_finite(scatter):
		return plans
	var source: Vector2 = giant.global_position # 已由移动组件修正坡面的巨人脚点。
	var forward_x: float = -signf(giant.direction_x_root) # 角色朝向转换为游戏世界的 X 方向。
	var origin_x: float = _release_x(game, giant, forward_x) # 出手位置可以落在可种植区的投影外。
	var bounds: Vector2 = _safe_landing_bounds(game, geometry) # 使用真实可落地范围和房屋保护距离。
	var landing_edge: float = _forward_edge_x(bounds, forward_x) # 短抛优先落在朝向一侧的安全地块。
	var ahead: float = (_forward_edge_x(geometry.bounds, forward_x) - source.x) * forward_x # 脚点至朝向一侧的边缘距离。
	var drive: float = ahead - WINDUP_DEPTH * geometry.pitch # 以实际战场尺度计算力度。
	var short_throw: bool = drive <= 0.5 * geometry.pitch or (landing_edge - origin_x) * forward_x <= 0.0 # 近身下砸使用短抛时间。
	if not allow_short_throw:
		if short_throw:
			return plans
		bounds = _ahead_landing_bounds(bounds, origin_x, forward_x, geometry.pitch)
	drive = maxf(drive, 0.5 * geometry.pitch)
	if drive > 1.75 * geometry.pitch:
		drive -= clampf(scatter, 0.0, 1.0) * 1.25 * geometry.pitch
	var gravity: float = GRAVITY * field_scale.y # 世界单位的重力，不随小僵尸体型减半。
	var speed: float = HORIZONTAL_SPEED * field_scale.x # 世界单位的基准横向速度。
	var height: float = -RELEASE_OFFSET.y * scale_size.y # 保留出手高度。
	var upward_speed: float = gravity * (0.5 * drive / speed - 0.005) # 连续化原先 10 毫秒积分的力度。
	var seconds: float = sqrt(2.0 * height / gravity) if short_throw else \
		(upward_speed + sqrt(upward_speed * upward_speed + 2.0 * gravity * height)) / gravity # 原有飞行节奏。
	var preferred: float = landing_edge if short_throw else origin_x + speed * seconds * forward_x # 先确定整组共用中心。
	var half_spread: float = float(count - 1) * 0.25 * geometry.pitch # 尽可能让整组散布都容纳在安全范围内。
	var center: float = geometry.nearest_x(preferred, bounds.x + half_spread, bounds.y - half_spread) # 同组共享随机中心。
	if not is_finite(center):
		center = geometry.nearest_x(preferred, bounds.x, bounds.y)
	if not is_finite(center):
		return plans
	var baseline: float = game.zombie_manager.all_zombie_rows[giant.lane].zombie_create_position.global_position.y # 固定攻击行。
	var release := Vector2(origin_x, minf(source.y - height, _ground_y(game, baseline, origin_x) - SLOPE_CLEARANCE)) # 保证初始离地。
	for index: int in range(count): # 每个散布点都独立投影到安全集合，不能跨入缺格。
		var offset: float = (float(index) - float(count - 1) * 0.5) * 0.5 * geometry.pitch # 相邻小鬼保持半格间隔。
		var target_x: float = geometry.nearest_x(center + offset, bounds.x, bounds.y) # 不吸附到格子中心。
		if not is_finite(target_x):
			continue
		var plan := ImpThrowPlan.new() # 不持有可被平台移动或删除的节点引用。
		plan.spawn_position = Vector2(origin_x, baseline)
		plan.release_position = release
		plan.landing_position = Vector2(target_x, _ground_y(game, baseline, target_x))
		plan.duration = seconds
		plan.arc_lift = 0.5 * gravity * seconds * seconds
		_clear_slopes(plan, game, baseline)
		if plan.is_valid():
			plans.append(plan)
	return plans


## 验证 [param game] 的 [param lane] 是否有当前固定攻击行，不回退其他行。
static func _has_row(game: MainGameManager, lane: int) -> bool:
	return is_instance_valid(game) and is_instance_valid(game.zombie_manager) \
		and lane >= 0 and lane < game.zombie_manager.all_zombie_rows.size() \
		and is_instance_valid(game.zombie_manager.all_zombie_rows[lane]) \
		and is_instance_valid(game.zombie_manager.all_zombie_rows[lane].zombie_create_position)


## 返回 [param giant] 沿 [param forward_x] 的出手横坐标，限制在 [param game] 的战斗存活边界内。
static func _release_x(game: MainGameManager, giant: Zombie000Base, forward_x: float) -> float:
	var release_x: float = giant.global_position.x + RELEASE_OFFSET.x * absf(giant.global_scale.x) * forward_x # 镜像携带小鬼的美术锚点。
	var live_range: Vector2 = game.zombie_manager.zombie_range_pos_x # 波次越界清理使用的世界 X 区间。
	return clampf(release_x, live_range.x, live_range.y)


## 用 [param geometry] 的真实格宽、[param game] 的房屋和存活边界计算落点的左右极限。
static func _safe_landing_bounds(game: MainGameManager, geometry: BoardLandingGeometry) -> Vector2:
	var minimum: float = geometry.bounds.x + geometry.pitch # 阵地左端至少保留一格。
	if is_instance_valid(game.background_manager) and is_instance_valid(game.background_manager.home):
		minimum = maxf(minimum, game.background_manager.home.get_defeat_front_x() + HOME_CLEARANCE * geometry.pitch)
	var live_range: Vector2 = game.zombie_manager.zombie_range_pos_x # 空中各帧和落地均须留在清理边界内。
	return Vector2(maxf(minimum, live_range.x), minf(geometry.bounds.y, live_range.y))


## 读取 [param bounds] 左右极限中朝 [param forward_x] 的一侧。
static func _forward_edge_x(bounds: Vector2, forward_x: float) -> float:
	return bounds.x if forward_x < 0.0 else bounds.y


## 将 [param bounds] 收窄到 [param origin_x] 沿 [param forward_x] 至少半个 [param pitch] 的范围。
static func _ahead_landing_bounds(bounds: Vector2, origin_x: float, forward_x: float, pitch: float) -> Vector2:
	var first_x: float = origin_x + forward_x * 0.5 * pitch # 半血投掷最近的目标横坐标。
	if forward_x < 0.0:
		return Vector2(bounds.x, minf(bounds.y, first_x))
	return Vector2(maxf(bounds.x, first_x), bounds.y)


## 返回 [param game] 在世界 [param x] 处相对固定行 [param baseline] 的地面高度。
static func _ground_y(game: MainGameManager, baseline: float, x: float) -> float:
	return baseline + (game.main_game_slope.get_all_slope_y(x) if is_instance_valid(game.main_game_slope) else 0.0)


## 调高 [param plan] 的弧线以越过 [param game] 的坡面折点；[param baseline] 是固定攻击行基线。
## 每段坡面为直线，离地高度为凹二次曲线，检查区间端点即可保证中间不穿坡。
static func _clear_slopes(plan: ImpThrowPlan, game: MainGameManager, baseline: float) -> void:
	if not is_instance_valid(game.main_game_slope) or is_equal_approx(plan.release_position.x, plan.landing_position.x):
		return
	for slope: Slope in game.main_game_slope.all_slopes: # 使用统一坡面入口，不再为屋顶扣固定距离。
		if not is_instance_valid(slope):
			continue
		for x: float in [slope.slope_global_pos_x_range.x, slope.slope_global_pos_x_range.y]: # 分段直线的两个折点。
			var progress: float = (x - plan.release_position.x) / (plan.landing_position.x - plan.release_position.x) # 折点所在飞行进度。
			if progress <= 0.0 or progress >= 1.0:
				continue
			var line_y: float = lerpf(plan.release_position.y, plan.landing_position.y, progress) # 不含抛高的连线高度。
			var needed: float = (line_y - _ground_y(game, baseline, x) + SLOPE_CLEARANCE) / (progress * (1.0 - progress)) # 避免穿坡所需系数。
			plan.arc_lift = maxf(plan.arc_lift, needed)
