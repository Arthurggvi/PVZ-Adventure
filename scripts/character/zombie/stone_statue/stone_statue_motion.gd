## 石壳碎块的解析运动；仅使用固定形状，不创建物理刚体。
extends RefCounted

## 源图坐标中的重力，单位为像素每平方秒。
const GRAVITY: float = 1900.0
## 源图中的脚底高度，缩放后与普僵脚掌接地位置一致。
const FLOOR_Y: float = 254.0

## 按固定种子创建运动；[param parts] 为已经准备好顶点的碎块。
static func create(parts: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 每次破壳独立持有的运动状态。
	var random: RandomNumberGenerator = RandomNumberGenerator.new() # 不改动战斗全局随机序列。
	random.seed = 9217
	for index: int in range(parts.size()): # 每块只计算一次初速度和接地时间。
		var part: Dictionary = parts[index] # 只读的共享碎块几何。
		var size: Vector2 = part.size # 碎块纹理宽高，单位为源图像素。
		var origin: Vector2 = part.origin # 碎块在完整石像中的左上角。
		var center: Vector2 = origin + size * 0.5 # 物理旋转中心。
		var side: float = -1.0 if center.x < 87.0 else 1.0 # 两侧主要向外脱落。
		var velocity: Vector2 = Vector2(side * random.randf_range(75.0, 145.0), random.randf_range(-28.0, 30.0)) # 初速度。
		var spin_sign: float = -1.0 if random.randf() < 0.5 else 1.0 # 翻转方向与横向飞出方向分离。
		var angular: Vector3 = Vector3.ZERO # 三个独立旋转轴的弧度每秒。
		if index % 3 == 0:
			angular = Vector3(spin_sign * random.randf_range(5.2, 8.8), side * random.randf_range(1.2, 3.2), random.randf_range(-1.8, 1.8))
		else:
			angular = Vector3(spin_sign * random.randf_range(1.4, 4.8), side * random.randf_range(4.0, 10.2), random.randf_range(-1.8, 1.8))
		var floor: float = maxf(FLOOR_Y + random.randf_range(-3.0, 13.0), center.y + lower_edge(part, Vector3.ZERO)) # 初始状态不得穿地。
		var state: Dictionary = {"part": part, "center": center, "velocity": velocity, "angular": angular, "floor": floor,
			"launch": 0.025 + 0.09 * origin.y / 260.0 + random.randf_range(-0.013, 0.013), "impact": 0.0} # 上部先碎、脚部稍后。
		state.impact = _find_impact(state)
		result.append(state)
	return result

## 按本地 X、Y、Z 顺序旋转；[param angles] 的单位为弧度。
static func rotation(angles: Vector3) -> Basis:
	return Basis(Vector3(0.0, 0.0, 1.0), angles.z) * Basis(Vector3.UP, angles.y) * Basis(Vector3.RIGHT, angles.x)

## 返回真实前后顶点投影后的最下缘；[param part] 与 [param angles] 共用绘制变换。
static func lower_edge(part: Dictionary, angles: Vector3) -> float:
	var turn: Basis = rotation(angles) # 绘制和碰撞共用的旋转基。
	var bottom: float = -INF # 当前所有表面的最下点。
	for vertex: Vector3 in part.vertices: # 同时检查正面和有厚度的背面。
		bottom = maxf(bottom, (turn * vertex).y)
	return bottom

## 用二分找到第一次接地，避免不同帧率导致碎块悬浮；[param state] 是单块运动。
static func _find_impact(state: Dictionary) -> float:
	var previous: float = 0.0 # 上一次仍在空中的秒数。
	for step: int in range(1, 91): # 只在破壳时求解，最长检查 1.5 秒。
		var age: float = float(step) / 60.0 # 本次候选飞行时长。
		if _air_position(state, age).y + lower_edge(state.part, state.angular * age) >= float(state.floor):
			var low: float = previous # 接触区间的下界。
			var high: float = age # 接触区间的上界。
			for _iteration: int in range(8): # 亚像素精度，不依赖物理引擎。
				var middle: float = (low + high) * 0.5 # 本次二分时间。
				if _air_position(state, middle).y + lower_edge(state.part, state.angular * middle) >= float(state.floor):
					high = middle
				else:
					low = middle
			return high
		previous = age
	return 1.5

## 返回 [param state] 的抛物线位置；[param age] 从该块实际离壳时刻开始计秒。
static func _air_position(state: Dictionary, age: float) -> Vector2:
	return state.center + state.velocity * age + Vector2(0.0, 0.5 * GRAVITY * age * age)

## 采样 [param state] 在整体破壳后 [param time] 秒的位置与角度。
static func sample(state: Dictionary, time: float) -> Dictionary:
	var age: float = maxf(0.0, time - float(state.launch)) # 各块错开约百分之一秒离壳。
	var impact: float = state.impact # 第一次真实轮廓接地时刻。
	if age <= impact:
		return {"center": _air_position(state, age), "angles": state.angular * age, "landed": false, "settle_age": 0.0}
	var elapsed: float = age - impact # 接地后继续翻平的时间。
	var impact_position: Vector2 = _air_position(state, impact) # 接地瞬间的物理中心。
	var impact_angles: Vector3 = state.angular * impact # 接地瞬间的朝向。
	var target: Vector3 = Vector3(signf(state.angular.x) * 1.48, impact_angles.y, impact_angles.z + 0.13) # 碎石最终平躺。
	var angles: Vector3 = impact_angles.lerp(target, 1.0 - exp(-elapsed * 23.0)) # 短促滚动并快速停止。
	var horizontal: float = impact_position.x + state.velocity.x * 0.14 * (1.0 - exp(-elapsed * 9.0)) # 地面摩擦后的短距离滑移。
	var hop: float = 2.2 * sin(PI * minf(1.0, elapsed / 0.12)) if elapsed < 0.12 else 0.0 # 仅一次轻微回弹。
	var vertical: float = float(state.floor) - lower_edge(state.part, angles) - hop # 每帧贴合旋转后的真实轮廓。
	return {"center": Vector2(horizontal, vertical), "angles": angles, "landed": true, "settle_age": elapsed}
