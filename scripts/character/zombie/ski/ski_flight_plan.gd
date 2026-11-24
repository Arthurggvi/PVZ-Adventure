## 滑雪僵尸一次跳跃或风推的世界轨迹快照；只保存数值，不移动节点或持有障碍引用。
extends RefCounted
class_name SkiFlightPlan

## 起跳时锁定的前进格数，不因落点缺格而缩短或吸附到邻格。
const JUMP_CELLS: float = 1.5
## 普通场景尺度下最低离开起终点连线的峰高，单位为世界像素。
const MINIMUM_JUMP_HEIGHT: float = 24.0
## 沿用三叶草共用风推的物理时长，单位为秒。
const WIND_SECONDS: float = 0.35
## 坡面折点的基础离地余量，单位为场景缩放前的像素。
const CLEARANCE_PIXELS: float = 2.0

## 本条轨迹的总时长；跳跃由调用者按动作秒推进，风推由调用者按物理秒推进。
var duration: float = 0.0
## 开始时确定的实际地面脚点，之后不追踪移动平台或障碍。
var landing_position: Vector2 = Vector2.ZERO
## 当前飞行开始时的世界脚点；风推保留此前已经抬起的高度。
var _release_position: Vector2 = Vector2.ZERO
## 抛物线系数；中点离开起终点连线的高度为该值的四分之一。
var _arc_lift: float = 0.0

## 为 [param source] 在 [param game] 中创建精确前进 [constant JUMP_CELLS] 格的轨迹。
## [param cell_width] 是世界格宽，[param seconds] 是完整跳跃动作秒数，[param obstacle_bounds] 只验证接触几何有效。
## 使用低弧擦掠冰封对象，不按植物或冰块的视觉顶部增加抛高。
## 落点不在真实同路地块中、参数失效或角色已离场时返回空值；不修改任何节点。
static func for_jump(source: Zombie000Base, game: MainGameManager, cell_width: float,
		seconds: float, obstacle_bounds: Rect2) -> SkiFlightPlan:
	if not _valid_context(source, game, cell_width) or not is_finite(seconds) or seconds <= 0.0 \
			or not obstacle_bounds.position.is_finite() or not obstacle_bounds.size.is_finite() \
			or obstacle_bounds.size.x < 0.0 or obstacle_bounds.size.y < 0.0:
		return null
	var facing: float = signf(float(source.direction_x_root)) # 右侧来袭时朝左；魅惑或反向行走仍保持有符号前进。
	if is_zero_approx(facing):
		return null
	var origin: Vector2 = source.global_position # 角色根已由原移动组件放在实际坡面脚点。
	var baseline: float = origin.y - _slope_height(game, origin.x) # 保留当前行的实际基线，不重设为另一条行线。
	var target_x: float = origin.x - facing * JUMP_CELLS * cell_width # 精确距离，不重新查障碍位置。
	var destination: Vector2 = Vector2(target_x, _ground_y(game, baseline, target_x)) # 同一条行线上的真实地面落点。
	if not destination.is_finite() or is_equal_approx(origin.x, target_x) \
			or game.board.cell_at_ground_point(destination, source.lane) == null:
		return null
	var scale_y: float = game.global_transform.y.length() # 场景的世界纵向尺度，独立于僵尸迷你体型。
	var clearance: float = CLEARANCE_PIXELS * scale_y # 仅为真实地形留轻微余量。
	var plan: SkiFlightPlan = SkiFlightPlan.new() # 只从当前现场提取数值，完成后不保存战场引用。
	plan._release_position = origin
	plan.landing_position = destination
	plan.duration = seconds
	plan._arc_lift = 4.0 * MINIMUM_JUMP_HEIGHT * scale_y
	if not plan._is_finite():
		return null
	_clear_slopes(plan, game, baseline, clearance)
	return plan if plan._is_finite() else null

## 为 [param source] 创建右向风推；[param game] 提供坡高，[param air_position] 保留当前空中脚点。
## [param cell_width] 为世界格宽，[param cells] 沿用共用三叶草规则；允许出屏，由调用者按视野边界决定退场。
## 无效参数返回空值；成功轨迹固定0.35物理秒，末端回到该行地面，不改角色状态。
static func for_wind(source: Zombie000Base, game: MainGameManager, air_position: Vector2,
		cell_width: float, cells: int) -> SkiFlightPlan:
	if not _valid_context(source, game, cell_width) or not air_position.is_finite() or cells <= 0:
		return null
	var baseline: float = source.global_position.y - _slope_height(game, source.global_position.x) # 根节点仍是地面投影。
	var target_x: float = air_position.x + cell_width * float(cells) # 风始终向右，不受魅惑朝向影响。
	var plan: SkiFlightPlan = SkiFlightPlan.new() # 不引用旧跳跃计划，避免余程与风推同时累加。
	plan._release_position = air_position
	plan.landing_position = Vector2(target_x, _ground_y(game, baseline, target_x))
	plan.duration = WIND_SECONDS
	plan._arc_lift = 0.0
	if not plan._is_finite():
		return null
	_clear_slopes(plan, game, baseline, CLEARANCE_PIXELS * game.global_transform.y.length())
	return plan if plan._is_finite() else null

## 按累计 [param elapsed] 秒解析采样；非有限时间保持起点，终点之后精确停在地面落点。
func sample(elapsed: float) -> Vector2:
	if not is_finite(elapsed):
		return _release_position
	if duration <= 0.0 or elapsed >= duration:
		return landing_position
	var progress: float = clampf(elapsed / duration, 0.0, 1.0) # 负时间停在起点，不外推轨迹。
	return _release_position.lerp(landing_position, progress) \
		+ Vector2.UP * _arc_lift * progress * (1.0 - progress)

## 验证 [param source] 属于 [param game] 的有效攻击行，且 [param cell_width] 为有限正世界宽度。
static func _valid_context(source: Zombie000Base, game: MainGameManager, cell_width: float) -> bool:
	return is_instance_valid(source) and source.is_inside_tree() and not source.is_death \
		and not source.is_queued_for_deletion() and source.global_position.is_finite() \
		and is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game.is_ancestor_of(source) and is_instance_valid(game.board) and game.board.configured \
		and source.lane >= 0 and source.lane < game.board.lanes.size() \
		and is_finite(cell_width) and cell_width > 0.0 \
		and game.global_transform.y.is_finite() and game.global_transform.y.length() > 0.0

## 读取 [param game] 的世界横坐标 [param x] 对应的坡面偏移，平地为零。
static func _slope_height(game: MainGameManager, x: float) -> float:
	return game.main_game_slope.get_all_slope_y(x) if is_instance_valid(game.main_game_slope) else 0.0

## 将 [param baseline] 与 [param game] 在 [param x] 的坡高合成为实际世界地面高度。
static func _ground_y(game: MainGameManager, baseline: float, x: float) -> float:
	return baseline + _slope_height(game, x)

## 抬高 [param plan] 以越过 [param game] 的各坡折点；[param baseline] 是当前行基线。
## [param clearance] 随起终点收敛到零，避免靠近落点的折线使弧高因极小分母暴涨。
static func _clear_slopes(plan: SkiFlightPlan, game: MainGameManager, baseline: float, clearance: float) -> void:
	if not is_instance_valid(game.main_game_slope):
		return
	for slope: Slope in game.main_game_slope.all_slopes: # 每段都是直线，轨迹在该段的最大侵入只需检查两端。
		if not is_instance_valid(slope):
			continue
		for edge_x: float in [slope.slope_global_pos_x_range.x, slope.slope_global_pos_x_range.y]: # 地形实际世界折点。
			var progress: float = plan._progress_at_x(edge_x) # 只检查本段飞行内部的折点。
			if progress <= 0.0 or progress >= 1.0:
				continue
			var margin: float = clearance * 4.0 * progress * (1.0 - progress) # 接近地面起终点时连续归零。
			_raise_above(plan, edge_x, _ground_y(game, baseline, edge_x) - margin)

## 将 [param plan] 在 [param x] 的脚点抬至 [param ceiling_y] 或更高；只增弧高，不改变水平落点和时长。
static func _raise_above(plan: SkiFlightPlan, x: float, ceiling_y: float) -> void:
	var progress: float = plan._progress_at_x(x) # 未进入飞行或已在落地后的坡面边界不参与抬高。
	if progress <= 0.0 or progress >= 1.0:
		return
	var line_y: float = lerpf(plan._release_position.y, plan.landing_position.y, progress) # 尚未加入抛高的连接线。
	var required: float = (line_y - ceiling_y) / (progress * (1.0 - progress)) # 只保证真实地面净空，不避让冰块顶部。
	plan._arc_lift = maxf(plan._arc_lift, required)

## 返回世界横坐标 [param x] 所在的飞行进度；工厂只构造有非零水平距离的计划。
func _progress_at_x(x: float) -> float:
	return (x - _release_position.x) / (landing_position.x - _release_position.x)

## 工厂收尾验证，防止异常地形、缩放或极端边界生成非有限采样结果。
func _is_finite() -> bool:
	return _release_position.is_finite() and landing_position.is_finite() \
		and is_finite(duration) and duration > 0.0 and is_finite(_arc_lift) and _arc_lift >= 0.0 \
		and not is_equal_approx(_release_position.x, landing_position.x)
