## 电球的方向细尾、稳定亮芯和出膛/分裂短脉冲；只接收表现时钟与真实速度，不参与战斗结算。
extends Node2D

## 电球、电弧及本体共用的电能豌豆专属色表。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 普通电球出膛脉冲时长，单位为有效游戏秒。
const LAUNCH_SECONDS: float = 0.16
## 分裂后代的出生脉冲更短，避免多球重叠时形成白屏。
const SPLIT_SECONDS: float = 0.11

## 当前阶级近白色细芯，原版动画仍承担主球面。
var _core: Color = Color("f0fff9")
## 当前阶级主电色，用于尾迹和球面前缘。
var _rim: Color = Color("4cebbd")
## 只在一条细副尾和出生脉冲上使用的辅色。
var _glow: Color = Color("74cfff")
## 小球降低辅光强度；尺寸只由调用方统一缩放一次。
var _child_ball: bool = false
## 弹体累计有效游戏秒数，暂停时不更新。
var _age: float = 0.0
## 根据实例编号生成的固定相位，不消耗战斗随机序列。
var _phase: float = 0.0
## 由真实帧速度计算的尾迹长度倍率，上界防止高速弹拖满屏幕。
var _speed_ratio: float = 1.0
## 当前原版电球的局部半径，细尾从球面背缘向外伸出。
var _ball_radius: float = 16.0


## 绑定 [param rank] 的颜色和 [param child_ball] 出生类型；[param ball_radius] 为原球面的局部像素半径。
## 小球的尺寸由父级设置 scale，本节点不重复缩放。
func configure(rank: int, child_ball: bool, ball_radius: float = 16.0) -> void:
	var colors: Dictionary = PromotionArt.effect_colors(rank) # 用颜色副本防止污染共享色表。
	_core = colors.core
	_rim = colors.rim
	_glow = colors.glow
	_child_ball = child_ball
	_ball_radius = maxf(4.0, ball_radius)
	_age = 0.0
	_phase = float(get_instance_id() % 29) * 0.23
	queue_redraw()


## [param elapsed] 为弹体累计有效秒数，[param frame_velocity] 为世界像素/秒；斜向与反向弹体同样按真实方向绘制。
## 不启用独立处理时钟，父弹暂停、出界或销毁时，此表现同步停止。
func advance_visual(elapsed: float, frame_velocity: Vector2) -> void:
	_age = maxf(0.0, elapsed)
	if frame_velocity.length_squared() > 0.01:
		# 换回父节点局部方向，兼容战场祖先缩放或旋转；只转动表现节点。
		var local_velocity: Vector2 = frame_velocity # 无父级时世界方向即可作为局部方向。
		var parent_2d := get_parent() as Node2D # 弹体逻辑根节点，不读取或更改其战斗属性。
		if parent_2d != null and not is_zero_approx(parent_2d.global_transform.determinant()):
			local_velocity = parent_2d.global_transform.basis_xform_inv(frame_velocity)
		rotation = local_velocity.angle()
		_speed_ratio = clampf(frame_velocity.length() / 180.0, 0.8, 1.4)
	queue_redraw()


## 细尾先衰减到透明，亮芯半径固定；只有出生的前几帧出现一次小范围脉冲。
func _draw() -> void:
	var onset: float = smoothstep(0.0, 0.10, _age) # 出膛后逐步伸出短尾，枪口处不突然拉长。
	var strength: float = 0.70 if _child_ball else 1.0 # 后代叠加时仍留出敌人轮廓。
	var tail_root: float = _ball_radius * 0.80 # 将尾根贴在各尺寸原球的后缘，不穿过球面中心。
	var tail_length: float = tail_root + (20.0 + 5.0 * _speed_ratio) * onset # 球面外只延伸约四分之一格。
	var shimmer: float = 0.92 + 0.08 * sin(_age * 9.0 + _phase) # 微光只影响辅边，稳定芯不闪断。
	if onset > 0.01:
		# 主尾为透明尖端的窄电带，底色面积有限，外缘不会铺成不透明拖影。
		draw_polygon(PackedVector2Array([Vector2(-tail_length, 0.0), Vector2(-tail_root, -2.0),
			Vector2(-tail_root + 3.0, 0.0), Vector2(-tail_root, 2.0)]), PackedColorArray([
			Color(_rim, 0.0), Color(_rim, 0.13 * strength), Color(_rim, 0.04 * strength), Color(_rim, 0.13 * strength)]))
		_draw_filament(Vector2(-tail_length, -0.6), Vector2(-tail_root, -1.8), Color(_core, 0.62 * strength * onset), 0.75)
		_draw_filament(Vector2(-lerpf(tail_root, tail_length, 0.78), 2.5), Vector2(-tail_root, 3.2), Color(_glow, 0.46 * strength * onset), 0.65)
		# 一小段电折线在尾根游动，轮廓稳定，不每帧重抽随机点。
		var bend: float = sin(_age * 12.0 + _phase) * 0.9 # 小于一像素的摆幅使尾迹有电流感。
		draw_polyline(PackedVector2Array([Vector2(-lerpf(tail_root, tail_length, 0.74), -0.6), Vector2(-lerpf(tail_root, tail_length, 0.55), -1.7 + bend),
			Vector2(-lerpf(tail_root, tail_length, 0.30), 0.6), Vector2(-tail_root, -0.4)]), Color(_rim, 0.47 * strength * shimmer), 0.8, true)
	# 原动画继续描绘球面，只增加稳定小芯与不完整的细边，避免整颗变成实心荧光圆。
	draw_circle(Vector2.ZERO, 3.0, Color(_core, 0.72 * strength))
	draw_arc(Vector2.ZERO, _ball_radius * 0.74, -1.10, 0.72, 11, Color(_rim, 0.52 * strength * shimmer), 0.8, true)
	draw_arc(Vector2.ZERO, _ball_radius * 0.64, -2.65, -1.82, 7, Color(_core, 0.65 * strength), 0.7, true)
	var pulse_seconds: float = SPLIT_SECONDS if _child_ball else LAUNCH_SECONDS # 出膛与分裂分别只有一次脉冲。
	if _age < pulse_seconds:
		_draw_birth_pulse(_age / pulse_seconds, strength)


## 在 [param start] 与 [param finish] 之间绘制单条细尾；[param tint] 含峰值透明度，[param width] 为头端像素宽度。
func _draw_filament(start: Vector2, finish: Vector2, tint: Color, width: float) -> void:
	var side: Vector2 = (finish - start).normalized().orthogonal() * width * 0.5 # 三角形尾端透明，末端宽度小于一像素。
	draw_polygon(PackedVector2Array([start, finish + side, finish - side]), PackedColorArray([Color(tint, 0.0), tint, tint]))


## [param progress] 为出生脉冲的归一化时间，[param strength] 为小球衰减；短弧与三根火花结束后不再绘制。
func _draw_birth_pulse(progress: float, strength: float) -> void:
	var fade: float = (1.0 - progress) * (1.0 - progress) * strength # 快速衰减，避免后半段留下灰色完整圆环。
	var radius: float = _ball_radius * lerpf(0.72, 1.18 if not _child_ball else 1.04, progress) # 最大范围只覆盖球边附近。
	draw_arc(Vector2.ZERO, radius, -1.20, 1.20, 15, Color(_rim, 0.55 * fade), 1.0, true)
	draw_arc(Vector2.ZERO, radius * 0.83, 1.90, 3.65, 11, Color(_glow, 0.36 * fade), 0.9, true)
	for index: int in range(3): # 三根定向短火花随弧向外移动，不生成额外节点。
		var angle: float = -0.90 + float(index) * 0.90 + sin(_phase) * 0.08 # 三个方向围绕前方分布。
		var direction := Vector2.from_angle(angle) # 方向已经跟随本节点的真实速度旋转。
		draw_line(direction * (radius - 1.0), direction * (radius + 3.0 - progress * 2.0), Color(_core, 0.65 * fade), 0.8, true)
