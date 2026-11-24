## 一个复用的世界空间产物。位置不再依附爆点，压强波和短闪则留在真正起点。
extends RefCounted

## 顺序与共享 Shader 的材质分支及批次绘制顺序一致。
enum Kind { GLOW, SMOKE, PRESSURE, RAYS, FLAME, CORE, SPARK, METAL }

## R6 风向也用作火团和烟团形变的平行基底。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 运动速度、重力与位移都用世界像素。
const Motion := preload("res://scripts/adventure/garden_airship/garden_airship_blast_motion.gd")

## 当前绘制类型。
var kind: Kind
## 来源类别，用于统计实际共享容量。
var profile: StringName
## 产物独立的世界位置，压力波始终保存真实爆心。
var position: Vector2
## 产物的瞬时世界速度，单位为像素每战斗秒。
var velocity: Vector2
## 按战斗时钟累计的年龄，单位为秒。
var age: float
## 本次占用槽位的最长战斗秒数。
var life: float
## 阻力时间常数，单位为战斗秒。零允许压力波固定在爆点。
var tau: float
## 竖直加速度，向下为正，单位为世界像素每战斗秒平方。
var gravity: float
## 基准形状宽度，单位为世界像素。
var size: float
## 火焰纹理或金属片的初始角度，单位为弧度。
var angle: float
## 确定性 0 到 1 的形变、旋转和图集相位。
var phase: float
## 出生时的处理帧，用于保留真正的首帧爆心。
var born_frame: int
## 该火团剩余烟丝数。仅少数主要火团有距离发射预算。
var trail_left: int
## 沿实际运动路径累计、尚未产生下一团烟的距离，单位为世界像素。
var trail_carry: float

## 用 [param wind]、参考换算 [param factor] 推进 [param step] 战斗秒，保持出生点之后的独立运动。
func advance(wind: Wind, factor: float, step: float) -> void:
	age += step
	if tau <= 0.0 or step <= 0.0:
		return
	var flow: Vector2 = Motion.flow_velocity(wind, position + velocity * (step * 0.5), factor, tau * 0.36) # 只取一次位置和响应滞后。
	var motion: Vector4 = Motion.integrate(velocity, flow, Vector2(0.0, gravity), tau, step) # 同帧中心的局部气流近似恒定。
	position += Vector2(motion.x, motion.y)
	velocity = Vector2(motion.z, motion.w)

## 返回风捕获当前团块的程度。不同团块错开拉伸与熄灭，保持破碎轮廓。
func stretch() -> float:
	return smoothstep(0.037 + phase * 0.031, 0.175 + phase * 0.044, age) * (0.68 + 0.32 * phase)

## 返回单位面片的世界变换。火团窄化和拖尾围绕各自物理锚点演进。
func draw_transform() -> Transform2D:
	var progress: float = clampf(age / life, 0.0, 1.0) # 当前外观的有界寿命比例。
	var draw_size: Vector2 = Vector2.ONE * size # 面片全宽和全高，单位为世界像素。
	var center: Vector2 = position # 只有面片内的形变偏心不写回真实世界位置。
	var turn: float = angle # 旋转由本次种子确定，飞行拖尾另外沿速度计算。
	match kind:
		Kind.GLOW:
			draw_size *= Vector2(1.0 + 0.16 * progress, 0.62)
			turn = 0.0
		Kind.SMOKE:
			var spread: float = smoothstep(0.01, 0.34, age) # 风卷形成的横向烟带。
			draw_size *= (0.61 + 0.47 * sqrt(progress)) * Vector2(1.0 + spread * (1.26 + phase), 1.0 - 0.28 * spread)
			turn = lerp_angle(turn * 0.20, velocity.angle(), spread)
			center -= Wind.DIRECTION * draw_size.x * (0.15 * spread)
		Kind.PRESSURE:
			var outward: float = sqrt(progress) # 起初扩散更快，压力波晚期迅速散去。
			draw_size *= (0.52 + 1.68 * outward) * Vector2(1.0, angle * (1.0 - 0.12 * progress))
			turn = 0.0
		Kind.RAYS:
			draw_size *= lerpf(0.61, 1.32, sqrt(progress))
		Kind.FLAME:
			var capture: float = stretch() # 上风侧快速压缩、各团在背风侧以不同尺度拉出。
			draw_size *= (0.86 + 0.29 * smoothstep(0.0, 0.085, age)) * Vector2(1.0 + capture * (1.16 + phase), 1.0 - 0.37 * capture)
			turn = lerp_angle(angle, Wind.DIRECTION.angle(), capture) + sin(phase * TAU + age * 17.0) * 0.16 * capture
			center += Wind.DIRECTION * draw_size.x * (0.16 * capture)
		Kind.CORE:
			draw_size *= (0.69 + 0.67 * smoothstep(0.0, 0.055, age)) * Vector2(1.0 + 0.33 * progress, 1.0 - 0.24 * progress)
			turn *= 1.0 - progress
		Kind.SPARK:
			var span: float = clampf(velocity.length() * (0.009 + 0.012 * phase), size * 1.3, size * 11.0) # 速度曝光而成的亮尾全长。
			draw_size = Vector2(lerpf(size * 1.3, span, smoothstep(0.0, 0.032, age)), size * (1.0 - 0.5 * progress))
			turn = velocity.angle()
			center -= Vector2.from_angle(turn) * draw_size.x * 0.35
		Kind.METAL:
			draw_size *= Vector2(1.0, 0.48 + 0.30 * absf(sin(phase * TAU + age * 31.0)))
			turn += age * lerpf(-29.0, 36.0, phase)
	return Transform2D(turn, draw_size, 0.0, center)

## 返回不透明度及温度色。烟使用普通透明混合，短热核没有全屏闪层。
func draw_tint() -> Color:
	var progress: float = clampf(age / life, 0.0, 1.0) # 当前外观的有界寿命比例。
	var remaining: float = 1.0 - progress # 余下的比例也乘入各类不透明度。
	match kind:
		Kind.GLOW:
			return Color(1.0, 0.55, 0.19, 0.22 * remaining * remaining)
		Kind.SMOKE:
			var opacity: float = smoothstep(0.01, 0.09 + 0.04 * phase, age) * remaining * (0.47 + 0.16 * phase) # 浅烟迅速形成，消散不留下黑屏。
			return Color(0.96 + 0.04 * progress, 0.79 + 0.20 * progress, 0.64 + 0.33 * progress, opacity)
		Kind.PRESSURE:
			return Color(1.0, 0.79, 0.44, (0.46 + 0.18 * sin(progress * PI)) * remaining * remaining)
		Kind.RAYS:
			return Color(1.0, 0.81, 0.42, 0.88 * remaining * remaining)
		Kind.FLAME:
			var cooling: float = smoothstep(0.02, 0.24 + 0.065 * phase, age) # 暖黄通过橙红衰减，分团保留不同热度。
			var opacity: float = (0.73 + 0.24 * phase) * remaining # 重型机匣保留原本较厚的烟火比例。
			if profile == &"fighter":
				opacity = (0.91 + 0.07 * phase) * (1.0 - smoothstep(0.14, 1.0, progress))
				return Color(1.0 - 0.14 * cooling, 0.75 - 0.53 * cooling, 0.44 - 0.35 * cooling, opacity)
			return Color(1.0 - 0.18 * cooling, 0.77 - 0.56 * cooling, 0.40 - 0.31 * cooling, opacity)
		Kind.CORE:
			return Color(1.0, 0.99 - 0.31 * progress, 0.90 - 0.43 * progress, 1.0 - smoothstep(0.18, 1.0, progress))
		Kind.SPARK:
			return Color(1.0, 0.96 - 0.69 * progress, 0.62 - 0.51 * progress, remaining * (0.79 + 0.21 * phase))
		Kind.METAL:
			return Color(0.68 - 0.26 * progress, 0.45 - 0.19 * progress, 0.29 - 0.11 * progress, minf(1.0, remaining * 2.0))
	return Color.TRANSPARENT
