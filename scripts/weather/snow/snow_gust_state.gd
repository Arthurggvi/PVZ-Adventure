## 雪场本局独占的视觉阵风。在控制器给出的游戏秒内推进，不访问玩法随机源。
extends RefCounted

## 风场最先抬升的阵风强度，范围 0..1。风速和可选风声使用。
var gust_pulse: float = 0.0
## 由现有降雪与风强共同决定的暴雪权重，范围 0..1，供环境声和暴雪表现共用。
var storm_strength: float = 0.0
## 远景能见度损失，范围 0..1。包含持续雪暴及滞后的雪墙增量。
var visibility_loss: float = 0.0
## 镜头冲击包络，范围 0..1。着色器另行限制局部透明度。
var lens_whiteout: float = 0.0
## HUD 冷白权重，范围 0..1。实际透明度由镜头材质限制。
var hud_frost: float = 0.0
## 随阵风拖尾的地吹雪强度，范围 0..1。
var ground_drift: float = 0.0
## 外部演出指定的峰值风速，单位世界像素/秒。
var burst_velocity := Vector2.ZERO
## 外部狂风叠加权重，随包络渐强及回落。
var burst_strength: float = 0.0

## 固定初相的阵风事件时钟。每一次脉冲都在同一周期内共享该相位。
var _phase: float = 0.04
## 大尺度阵风的速度调制相位，周期 26.3 游戏秒。
var _slow_phase: float = 0.18
## 与大尺度相位错开的幅度相位，周期 41.7 游戏秒。
var _variation: float = 0.39
## 本次外部狂风已消耗的游戏秒数。
var _burst_age: float = 0.0
## 本次外部狂风的总游戏秒数，零值表示尚无外部狂风。
var _burst_duration: float = 0.0
## 从自然风过渡至峰值的游戏秒数，为零时立即到达峰值。
var _burst_build: float = 0.0
## 渐强从上一股狂风的当前权重接续，杖击期间触发也保留风势。
var _burst_from: float = 0.0


## 以有限且非零的 [param velocity] 覆盖峰值风向和速度，在 [param duration] 游戏秒内融回当前风场。
## [param build_seconds] 为可选的渐强时间，占用本次狂风的前段。
## 新请求替换当前狂风；天气时间线和自然阵风相位继续推进。
func play_burst(velocity: Vector2, duration: float, build_seconds: float = 0.0) -> void:
	if (not velocity.is_finite() or velocity.is_zero_approx() or not is_finite(duration)
			or duration <= 0.0 or not is_finite(build_seconds)):
		return
	burst_velocity = velocity
	_burst_age = 0.0
	_burst_duration = duration
	_burst_build = clampf(build_seconds, 0.0, duration * 0.75)
	_burst_from = burst_strength if _burst_build > 0.0 else 1.0
	burst_strength = _burst_from


## 以 [param delta] 游戏秒推进，对 [param channels] 的降雪、雪风、云量派生各视觉权重。
## [param snap] 在场景首帧对应阶段快照，后续阶段切换按实际游戏时间过渡。
func advance(delta: float, channels: Vector3, snap: bool = false) -> void:
	if _burst_age < _burst_duration:
		_burst_age = minf(_burst_age + delta, _burst_duration)
		var swell: float = lerpf(_burst_from, 1.0, smoothstep(0.0, _burst_build, _burst_age)) if _burst_build > 0.0 else 1.0 # 先渐强至峰值。
		var release: float = maxf(_burst_duration * 0.15, _burst_build) # 保留瞬发狂风原有的平台期。
		burst_strength = swell * (1.0 - smoothstep(release, _burst_duration, _burst_age))
	_slow_phase = fposmod(_slow_phase + delta / 26.3, 1.0)
	_variation = fposmod(_variation + delta / 41.7, 1.0)
	var breathing: float = 0.5 + 0.5 * sin(TAU * _slow_phase) # 基础起伏及阵风间隔调制。
	var strength: float = 0.84 + 0.16 * sin(TAU * _variation) # 两次峰值的强弱不同。
	_phase = fposmod(_phase + delta * lerpf(1.0 / 13.6, 1.0 / 8.1, breathing), 1.0)
	storm_strength = smoothstep(0.58, 0.93, minf(channels.x, channels.y))
	var wind_event: float = _pulse(Vector4(0.28, 0.50, 0.58, 0.80)) * strength # 前导风先达到峰值。
	gust_pulse = clampf(channels.y * (0.08 + breathing * 0.20 + wind_event * 0.72), 0.0, 1.0)
	var wall_event: float = _pulse(Vector4(0.37, 0.56, 0.67, 0.88)) * strength # 远景雪墙的延迟包络。
	var view_target: float = clampf(channels.z * 0.10 + storm_strength * (0.58 + wall_event * 0.33), 0.0, 1.0) # 稳态叠加阵风损失。
	visibility_loss = view_target if snap else _follow(visibility_loss, view_target, delta, 0.30, 1.05)
	var lens_event: float = _pulse(Vector4(0.565, 0.609, 0.630, 0.695)) * strength # 局部掠雪的短峰。
	var lens_target: float = storm_strength * lens_event # 小雪时不会触发主观白化。
	lens_whiteout = lens_target if snap else _follow(lens_whiteout, lens_target, delta, 0.07, 0.16)
	hud_frost = clampf(channels.x * 0.08 + storm_strength * 0.62 + lens_whiteout * 0.25, 0.0, 1.0)
	var drift_event: float = _pulse(Vector4(0.46, 0.70, 0.78, 0.98)) * strength # 地吹雪的峰值和尾声比镜头更晚。
	var drift_target: float = clampf(channels.x * channels.y * (0.25 + 0.72 * drift_event), 0.0, 1.0) # 持续贴坡雪与延迟尾声。
	ground_drift = drift_target if snap else _follow(ground_drift, drift_target, delta, 0.56, 1.42)


## [param edges] 依次为脉冲起点、平台起止点、结束点，在相位回绕两端都为零。
func _pulse(edges: Vector4) -> float:
	return smoothstep(edges.x, edges.y, _phase) * (1.0 - smoothstep(edges.z, edges.w, _phase))


## 以 [param rise] 或 [param fall] 秒的一阶响应，把 [param current] 推向 [param target]。
## [param delta] 由控制器限制为本帧可消费的游戏秒；零秒不改变状态。
func _follow(current: float, target: float, delta: float, rise: float, fall: float) -> float:
	var seconds: float = rise if target > current else fall # 上升和消退各自的时间尺度。
	return lerpf(current, target, 1.0 - exp(-delta / seconds))
