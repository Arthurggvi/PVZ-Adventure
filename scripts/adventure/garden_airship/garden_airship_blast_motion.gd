## 花园飞艇爆炸产物与独立机壳共用的气流取样和解析阻力积分。
extends RefCounted

## 局内实际飞行时钟、巡航空速及空间阵风。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 1920 参考画幅上的巡航气流，单位为参考像素每战斗秒。
const CRUISE_REFERENCE_SPEED: float = 2010.0
## 同一阵风峰值的额外倍率，只在 [method flow_velocity] 取样时乘一次。
const GUST_GAIN: float = 0.58

## 返回 [param point] 处的目标气流速度，单位为世界像素每战斗秒。
## [param wind] 由关卡持有，[param factor] 将参考像素换成世界像素，[param lag] 为取样迟滞秒数。
static func flow_velocity(wind: Wind, point: Vector2, factor: float, lag: float = 0.0) -> Vector2:
	var ratio: float = wind.sample_flow_ratio(point.x, lag, GUST_GAIN) if wind != null else 1.0 # 空速与阵风共用一个倍率。
	return Wind.DIRECTION * (CRUISE_REFERENCE_SPEED * ratio * factor)

## 在 [param step] 战斗秒内以恒定 [param airflow]、[param gravity] 和阻力时间常数 [param tau] 积分。
## [param velocity] 为上一步世界速度；返回 XY 世界位移与 ZW 末速度。不使用额外倍速修正。
static func integrate(velocity: Vector2, airflow: Vector2, gravity: Vector2, tau: float,
		step: float) -> Vector4:
	var response: float = maxf(tau, 0.001) # 时间常数下限避免除零。
	var target: Vector2 = airflow + gravity * response # 恒定阻力与加速度平衡时的世界速度。
	var span: float = maxf(step, 0.0) # 调用者可读取零秒处的当前位置及速度。
	var decay: float = exp(-span / response) # 当前时间步保留的相对速度比例。
	var offset: Vector2 = velocity - target # 相对平衡速度的差值。
	var movement: Vector2 = target * span + offset * (response * (1.0 - decay)) # 速度曲线的解析面积。
	var finish: Vector2 = target + offset * decay # 解析步结束时的世界速度。
	return Vector4(movement.x, movement.y, finish.x, finish.y)
