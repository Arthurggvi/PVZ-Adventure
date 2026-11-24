## 公共的短气压曲线，按当前绝对动作时间出图，无屏幕读回或逐帧图片。
extends RefCounted

## 弧边采样密度。三条不完整弧线共享这套解析形状。
const ARC_STEPS := 19

## 一次脱离人物的世界爆压。槽位仅持有时间、位置与调色参数。
class Burst extends RefCounted:
	## 发令、传送、阶段波或间歇气爆的构图。
	var kind: StringName
	## 原触发画布上的世界位置。
	var origin: Vector2
	## 传播方向，单位向量。
	var axis: Vector2
	## 战斗秒，INF 表示槽位空闲。
	var born: float = INF
	## 有效寿命，单位为战斗秒。
	var duration: float
	## 亮线的高光通道。
	var light: Color
	## 外缘低亮度通道。
	var edge: Color
	## 断弧和尾迹的位置变化。
	var variation: float
	## 归一的气压强度。
	var power: float
	## 本次爆压允许绘制的短尾迹数量。
	var sparks: int


## 将 [param burst] 绘到 [param canvas] 上的 [param origin]。
## [param age] 是波的时龄，[param wind] 是当前帧世界风速，用于已剥离的尾迹。
static func draw_burst(canvas: Node2D, origin: Vector2, burst: Burst, age: float, wind: Vector2) -> void:
	var directional: bool = burst.kind in [&"command", &"sky_order"] # 只有号令具有明确的压缩轴。
	var teleport: bool = burst.kind == &"teleport_out" # 母版负责传送主芯，外围保留撕裂轮廓。
	var phase_wave: bool = burst.kind == &"phase" # 阶段波比常驻气爆起得更宽。
	var basis: Vector2 = burst.axis # 平行于主要传播的单位向量。
	var across: Vector2 = basis.orthogonal() # 在局部爆压坐标的横向单位向量。
	var spread: float = 1.0 - exp(-age * (6.0 if directional else 5.0)) # 先强扩张，再交给环境风拖走。
	var fade: float = 1.0 - smoothstep(0.21 if teleport else 0.11, burst.duration, age) # 传送人物消失后仍留下可辨余波。
	var extent: float = 290.0 if directional else (190.0 if phase_wave else 110.0) # 世界像素下的主要传播距离。
	var radius: float = lerpf(13.0, extent * lerpf(0.65, 1.0, burst.power), spread) # 初生核心干净紧凑。
	var shift: Vector2 = basis * radius * (0.17 if directional else 0.0) + wind * age * age * 0.18 # 脱离后才显著随风偏移。
	for band: int in (3 if directional or phase_wave else 2): # 错开角域的多条短压线。
		var side: float = 1.0 if band % 2 == 0 else -1.0 # 左右或上下两侧错开起笔。
		var from: float = (-0.64 if directional else -1.20) + 0.28 * float(band) # 半弧不会围成常驻护盾。
		var span: float = (1.18 if directional else 2.03) - 0.19 * float(band) # 流向越明确，压缩扇越紧。
		var oval: Vector2 = Vector2(1.0, 0.49 if teleport else (0.71 if directional else 0.86)) # 传送是横向裂隙，纵向号令更集中。
		_draw_band(canvas, origin + shift, basis, across, oval * radius * (1.0 - 0.15 * band),
			side * from + (0.0 if directional or band == 0 else PI), side * span,
			burst.variation + float(band) * 0.8, burst.edge, burst.light,
			fade * burst.power * (0.94 - 0.23 * band), lerpf(3.8, 0.85, spread))
	if directional:
		_draw_signal(canvas, origin, basis, across, burst, age)
	elif teleport:
		for seam: int in 3: # 镜头没有再绘制精灵，只在原锚点两侧留三道被风扯开的切线。
			var displacement: Vector2 = across * float(seam - 1) * radius * 0.17 + shift # 三条断裂的压力面各自漂移。
			var distance: float = radius * (0.31 + 0.16 * seam) # 错开的切线有不同衰减长度。
			var alpha: float = fade * burst.power * (0.64 - 0.11 * seam) # 外缘较暗，母版蓝白核心仍是主角。
			canvas.draw_line(origin + displacement + basis * distance * 0.13, origin + displacement + basis * distance,
				_opacity(burst.edge, alpha), 2.9 - 0.52 * seam, true)
	elif age < 0.16:
		var light: float = (1.0 - age / 0.16) * burst.power # 阶段和环境气爆只在原锚点有一拍白芯。
		canvas.draw_circle(origin, 22.0 * spread + 5.0, _opacity(burst.edge, 0.39 * light), true, -1.0, true)
		canvas.draw_circle(origin, 6.0 + 5.0 * spread, _opacity(burst.light, 0.86 * light), true, -1.0, true)
	_draw_sparks(canvas, origin, basis, burst, age, wind)


## [param origin] 经 [param axis] 和 [param normal] 投影。非封闭弧按 [param oval] 缩放。
## [param start_angle] 与 [param sweep] 是弧度，[param noise] 破坏均匀圆形。
## [param edge] 和 [param core] 绘制低亮边和细白芯，[param opacity] 与 [param width] 为当前强度。
static func _draw_band(canvas: Node2D, origin: Vector2, axis: Vector2, normal: Vector2, oval: Vector2,
		start_angle: float, sweep: float, noise: float, edge: Color, core: Color, opacity: float, width: float) -> void:
	var points := PackedVector2Array() # 同一条弧的外缘与核心共用顶点。
	var colors := PackedColorArray() # 沿弧长两端渐隐，避免硬横截面。
	var glows := PackedColorArray() # 外缘沿同一包络，核心不抵到断口。
	for segment: int in ARC_STEPS: # 节点间距在大半径时仍足以表现薄弧。
		var ratio: float = float(segment) / (ARC_STEPS - 1) # 从起笔到末端的弧长比例。
		var angle: float = start_angle + sweep * ratio # 局部弧角。
		var wobble: float = 1.0 + 0.031 * sin(angle * 7.0 + noise) + 0.018 * cos(angle * 13.0 - noise) # 不规则压力边缘。
		var feather: float = pow(maxf(0.0, sin(PI * ratio)), 0.52) * opacity # 弧尾逐渐消失。
		points.append(origin + (axis * cos(angle) * oval.x + normal * sin(angle) * oval.y) * wobble)
		colors.append(_opacity(core, 0.77 * feather))
		glows.append(_opacity(edge, feather))
	canvas.draw_polyline_colors(points, glows, width * 2.6, true)
	canvas.draw_polyline_colors(points, colors, width, true)


## [param origin] 处的极短指令白芯沿 [param forward] 发散，[param across] 定义侧向轴。
## [param burst] 提供配色，[param age] 超过 0.12 秒时只留外部气浪。
static func _draw_signal(canvas: Node2D, origin: Vector2, forward: Vector2, across: Vector2,
		burst: Burst, age: float) -> void:
	if age >= 0.12:
		return
	var flash: float = (1.0 - smoothstep(0.025, 0.12, age)) * burst.power # 单次峰值快速退去。
	var length: float = lerpf(90.0, 290.0, smoothstep(0.0, 0.065, age)) # 延伸快于主压力短弧。
	canvas.draw_circle(origin, lerpf(10.0, 22.0, age / 0.12), _opacity(burst.edge, 0.53 * flash), true, -1.0, true)
	canvas.draw_circle(origin, 5.0 + 4.0 * flash, _opacity(Color.WHITE, 0.93 * flash), true, -1.0, true)
	for streak: int in 7: # 以手指为基准的短裂线，形成有空白的扇面。
		var side: float = float(streak - 3) # 中间线更细长，两侧不等长。
		var axis: Vector2 = forward.rotated(side * 0.117 + sin(burst.variation + streak) * 0.023) # 信号波的局部方向。
		var reach: float = length * (1.0 - 0.13 * absf(side)) * (0.81 + 0.19 * absf(cos(streak * 2.73 + burst.variation))) # 每条线派生独立长度。
		var base: Vector2 = origin + across * side * 2.4 # 起点近而不压住人物的大半手臂。
		var tips := PackedVector2Array([base, base + axis * reach * 0.32 + across * (3.5 - 0.5 * absf(side)), base + axis * reach]) # 三角尖端呈收束状。
		canvas.draw_polygon(tips, PackedColorArray([_opacity(burst.light, 0.82 * flash),
			_opacity(burst.light, 0.67 * flash), _opacity(burst.edge, 0.0)]))


## [param origin] 处的 [param burst] 沿 [param axis] 发出余烬。按 [param age] 和 [param wind] 拖曳。
static func _draw_sparks(canvas: Node2D, origin: Vector2, axis: Vector2, burst: Burst,
		age: float, wind: Vector2) -> void:
	var directional: bool = burst.kind in [&"command", &"sky_order"] # 气爆向周围放出，舰队信号的粒子沿扇面聚拢。
	for index: int in burst.sparks: # 上限随纹理兼容档调整，无每颗粒子的节点或计时器。
		var key: float = burst.variation + float(index) * 2.39996 # 黄金角分布防止重复放射轮廓。
		var linger: float = (0.30 + 0.68 * absf(cos(key * 0.81))) * burst.duration # 同一次爆射错开消散。
		if age >= linger:
			continue
		var ray: Vector2 = axis.rotated(0.96 * sin(key) if directional else key) # 角域以号令的传播方向为零点。
		var speed: float = 62.0 + 275.0 * absf(sin(key * 1.7)) # 每条余烬以不同速度衰减。
		var run: Vector2 = ray * speed # 炸开后受阻尼，也被现有风拖向船尾。
		var point: Vector2 = origin + run * (1.0 - exp(-3.6 * age)) / 2.58 + wind * (age * age * 0.38) # 解析轨迹支持掉帧后跳到正确位置。
		var alpha: float = pow(1.0 - age / linger, 1.6) * burst.power # 尾段更稀薄。
		var tail: Vector2 = (ray + wind * age * 0.0032).normalized() * lerpf(4.0, 17.0, speed / 337.0) * (0.38 + 0.62 * alpha) # 尾线与瞬时速度同向。
		canvas.draw_line(point - tail, point, _opacity(burst.light if index % 3 == 0 else burst.edge, alpha * 0.85), 1.2 + alpha * 0.66, true)


## 复制 [param color] 的颜料，按 [param opacity] 设置透明度。
static func _opacity(color: Color, opacity: float) -> Color:
	color.a = clampf(opacity, 0.0, 1.0)
	return color
