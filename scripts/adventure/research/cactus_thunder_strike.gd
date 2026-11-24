## 惊雷的全高放电与冲击余光。同一战场只建立一个绘制节点。
extends Node2D

## 主干从可见区域外接入，镜头震动开始后仍不露出首端。
const ABOVE_VIEW: float = 102.0
## 和落地粒子共用的表现寿命，单位为战斗秒。
const IMPACT_LIFETIME: float = 0.58
## 密集触发的两次全景高闪最短间隔，单位为战斗秒。
const FLASH_INTERVAL: float = 0.40
## 同一战场同屏绘制的最大雷击数。
const BOLT_LIMIT: int = 3
## 每次落地释放的碎光数量。
const SPARKS: int = 17
## 横向锯齿沿垂直分段变化，保留短斜肩和较长的放电段。
const PROFILE: Array[float] = [0.0, -0.28, 0.06, -0.11, 0.49, 0.34, 0.92, 0.66,
	0.71, 0.13, 0.26, -0.50, -0.23, -0.76, -0.32, -0.44, 0.26, 0.03, 0.44, 0.21, 0.06, 0.0]

## 一次真实落雷。固定轮廓附着在世界空间，随相机冲击整体移动。
class Strike:
	## 单一主通道的画布顶点。
	var trunk := PackedVector2Array()
	## 离开主干的两个短分支，均在地面上方熄灭。
	var forks: Array[PackedVector2Array] = []
	## 地面碎光的初始速度，只在触发时计算。
	var sparks := PackedVector2Array()
	## 当前格子的本地脚点。
	var foot: Vector2
	## 全高主干进入画面的天空位置。
	var sky: Vector2
	## 经过出生时棋盘缩放的冲击范围。
	var footprint: Vector2
	## 从落雷到当前已经度过的战斗秒数。
	var age: float = 0.0
	## 是否为目前这一组的全景闪光、音效和震动主雷。
	var primary: bool

## 本场正在播放的落雷，绘制数量不参与伤害结算。
var _strikes: Array[Strike] = []
## 再允许一次全景闪光前的剩余战斗秒数。
var _flash_lock: float = 0.0
## 只影响外观的局部序号，使落雷可以向不同方向偏折。
var _sequence: int = 0
## 所有落点、天空亮斑和镜头散光共用的径向透明度。
var _halo: GradientTexture2D

## 使用普通画布加色，无屏幕拷贝或额外渲染通道。
func _ready() -> void:
	name = &"CactusThunderStrike"
	z_index = 372
	var additive := CanvasItemMaterial.new() # 主干与余辉把光加到已有战场颜色上。
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = additive
	var profile := Gradient.new() # 暂存径向亮度曲线，只在第一道可见雷时创建。
	profile.offsets = PackedFloat32Array([0.0, 0.13, 0.33, 0.68, 1.0])
	profile.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.80), Color(1.0, 1.0, 1.0, 0.40),
		Color(1.0, 1.0, 1.0, 0.092), Color(1.0, 1.0, 1.0, 0.0)])
	_halo = GradientTexture2D.new()
	_halo.width = 128
	_halo.height = 128
	_halo.gradient = profile
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(1.0, 0.5)
	visible = not get_tree().paused
	set_process(false)

## [param what] 通知暂停或恢复；菜单打开时收起正在播放的全屏闪光。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		hide()
	elif what == NOTIFICATION_UNPAUSED:
		show()

## [param foot] 是落雷格的真实世界脚点，[param footprint] 为格子尺寸。
## 返回本次是否负责全景高闪，调用者在同一击合并镜头与雷声。
func strike(foot: Vector2, footprint: Vector2) -> bool:
	var view: Rect2 = get_viewport_rect() # 使用当前相机可见区确定雷从哪里进入画面。
	var to_screen: Transform2D = get_global_transform_with_canvas() # 与平台、缩放和当前相机偏移一致。
	var landing: Vector2 = to_screen * to_local(foot) # 只按投影判断可见性，落点仍保存在世界层。
	if not view.grow(25.0).has_point(landing):
		return false
	var arc := Strike.new() # 固定图形只在触发时创建，闪光过程中复用。
	arc.foot = to_local(foot)
	arc.footprint = footprint
	arc.primary = _flash_lock <= 0.0
	_sequence += 1
	_build_arc(arc, landing, view, to_screen.affine_inverse())
	if _strikes.size() == BOLT_LIMIT:
		_strikes.remove_at(1 if _strikes[0].primary else 0)
	_strikes.append(arc)
	if arc.primary:
		_flash_lock = FLASH_INTERVAL
	set_process(true)
	queue_redraw()
	return arc.primary

## 从 [param view] 上方到 [param landing] 构建 [param arc] 的单一通道。
## [param to_local_canvas] 将屏幕设计点转回真实世界层。
func _build_arc(arc: Strike, landing: Vector2, view: Rect2, to_local_canvas: Transform2D) -> void:
	var sign_x: float = -1.0 if _sequence % 2 == 1 else 1.0 # 交替朝两侧入场，保持单道斜轴。
	var top_y: float = view.position.y - ABOVE_VIEW # 超出镜头上缘一截，绝无空中截断。
	var height: float = landing.y - top_y # 决定倾斜、分支长度与每阶垂直距离。
	var offset: float = clampf(height * 0.24, 56.0, 139.0) # 保留竖向下砸的主轴。
	# 选择落点附近实际可见的入射列，保留横向安全余量。
	var start := Vector2(clampf(landing.x - sign_x * offset, view.position.x + 12.0,
		view.end.x - 12.0), top_y)
	var lateral: float = clampf(height * 0.082, 20.0, 55.0) # 中途锯齿按可见高度变化。
	for index: int in range(PROFILE.size()): # 生成一条从天空到地面的不重复路径。
		var t: float = float(index) / float(PROFILE.size() - 1) # 末点必须精确到脚点。
		var point: Vector2 = start.lerp(landing, t) # 沿天空到地面确定纵向位置。
		point.x += sign_x * lateral * PROFILE[index]
		arc.trunk.append(to_local_canvas * point)
	arc.sky = to_local_canvas * Vector2(lerpf(start.x, landing.x, ABOVE_VIEW / height), view.position.y + 6.0)
	arc.forks.append(_build_fork(arc.trunk[5], to_local_canvas.basis_xform(Vector2(-sign_x * lateral * 2.1, height * 0.21))))
	arc.forks.append(_build_fork(arc.trunk[11], to_local_canvas.basis_xform(Vector2(sign_x * lateral * 1.8, height * 0.16))))
	for index: int in range(SPARKS): # 不分配粒子节点，速度与位置随时间统一计算。
		var scatter: float = (float(index) / float(SPARKS - 1) - 0.5) * 2.0 # 侧飞角在两边展开。
		var speed: float = 106.0 + 56.0 * sin((index + _sequence) * 3.18) # 碎光长度略有差异。
		arc.sparks.append(Vector2(scatter * speed * 1.85, -speed * (1.30 - absf(scatter) * 0.57)))

## 从主干 [param root] 朝 [param span] 画较短的单支电光，前端留在空中。
func _build_fork(root: Vector2, span: Vector2) -> PackedVector2Array:
	return PackedVector2Array([root, root + span * Vector2(0.23, 0.32), root + span * Vector2(0.15, 0.51),
		root + span * Vector2(0.62, 0.62), root + span * Vector2(0.71, 0.83), root + span])

## [param delta] 为特效实际游戏秒，暂停不推进，最后一圈余光散尽后停止刷新。
func _process(delta: float) -> void:
	_flash_lock = maxf(0.0, _flash_lock - delta)
	for index: int in range(_strikes.size() - 1, -1, -1): # 按固定上限回收已结束的雷击。
		var arc: Strike = _strikes[index] # 当前活跃雷击状态。
		arc.age += delta
		if arc.age >= IMPACT_LIFETIME:
			_strikes.remove_at(index)
	set_process(not _strikes.is_empty())
	queue_redraw()

## 全景只闪一次，主干随之快速转为残光，地面冲击继续扩散。
func _draw() -> void:
	var exposure: float = 0.0 # 多发同屏时只选最亮的合成峰值。
	for arc: Strike in _strikes: # 全屏提亮的代价与同时命中数量无关。
		if arc.primary:
			exposure = maxf(exposure, 1.0 - smoothstep(0.025, 0.125, arc.age))
	if exposure > 0.0:
		var view: Rect2 = get_viewport_rect() # 抵消正在摇晃的相机变换，保持完整视口。
		var from_screen: Transform2D = get_global_transform_with_canvas().affine_inverse() # 从屏幕还原画布角点。
		draw_colored_polygon(PackedVector2Array([from_screen * view.position, from_screen * Vector2(view.end.x, view.position.y),
			from_screen * view.end, from_screen * Vector2(view.position.x, view.end.y)]), Color("c6dcff", exposure * 0.32))
	for arc: Strike in _strikes: # 每道雷只有一条明亮的主干。
		_draw_arc(arc)
		_draw_impact(arc)

## 以 [param arc] 的同一空间轮廓绘制空气散射、饱和边沿和白热主干。
func _draw_arc(arc: Strike) -> void:
	var return_stroke: float = 1.0 - smoothstep(0.044, 0.218, arc.age) # 单峰白热，随后单调衰减。
	var residual: float = 1.0 - smoothstep(0.12, 0.34, arc.age) # 主干消失后留一丝短暂残光。
	if residual <= 0.0:
		return
	var weight: float = 1.0 if arc.primary else 0.68 # 并发副雷仍从天空落地。
	var light: float = return_stroke * weight # 局部震撼程度随同一放电峰值衰减。
	_glow(arc.sky, Vector2(372.0, 133.0), Color("83acff", light * 0.78))
	draw_polyline(arc.trunk, Color("3a62ff", light * 0.22), 52.0 * light + 12.0, true)
	draw_polyline(arc.trunk, Color("657dff", light * 0.42), 23.0 * light + 8.0, true)
	draw_polyline(arc.trunk, Color("7bbdff", maxf(light * 0.80, residual * 0.10)), 11.0 * light + 3.5, true)
	for fork: PackedVector2Array in arc.forks: # 两支微弱放电都在主干上部散开。
		draw_polyline(fork, Color("678bff", light * 0.37), 8.5 * light + 1.0, true)
		draw_polyline(fork, Color("d0edff", light * 0.67), 2.3 * light + 0.65, true)
	draw_polyline(arc.trunk, Color("edfbff", maxf(light, residual * 0.17)), 5.6 * light + 1.35, true)
	draw_polyline(arc.trunk, Color(Color.WHITE, light * 0.9), 3.8 * light + 0.8, true)

## [param arc] 在脚点给出压地核心、扩散薄层和向外弹起的碎光。
func _draw_impact(arc: Strike) -> void:
	var t: float = arc.age / IMPACT_LIFETIME # 地面余辉比空中白芯慢一拍。
	var blast: float = 1.0 - smoothstep(0.02, 0.21, arc.age) # 先亮到白，快速退成蓝色。
	var fade: float = 1.0 - smoothstep(0.16, 1.0, t) # 波环和细碎亮线继续扩出去。
	var at: Vector2 = arc.foot # 与电弧末端、碰撞格共点。
	_glow(at - Vector2(0.0, 18.0), Vector2(255.0, 173.0), Color("73baff", fade * 0.65))
	_glow(at - Vector2(0.0, 7.0), Vector2(158.0, 72.0), Color("e4f7ff", blast * 0.93))
	_glow(at, Vector2(arc.footprint.x * 3.3, arc.footprint.y * 0.97), Color("258cfc", fade * 0.39))
	var span: float = lerpf(10.0, arc.footprint.x * 1.29, pow(t, 0.62)) # 由格内横向掠过地面。
	draw_set_transform(at, 0.0, Vector2(1.0, 0.36))
	draw_arc(Vector2.ZERO, span, 0.0, TAU, 42, Color("95d9ff", fade * 0.64), 3.6 * fade + 0.8, true)
	draw_arc(Vector2.ZERO, span * 0.71, 0.08, TAU - 0.08, 34, Color("e0f8ff", fade * 0.58), 1.8, true)
	draw_set_transform(Vector2.ZERO)
	draw_line(at - Vector2(38.0 * blast, 0.0), at + Vector2(38.0 * blast, 0.0), Color("ffffff", blast), 3.2, true)
	for velocity: Vector2 in arc.sparks: # 碎光弹起后受模拟重力，下落并变细。
		var position: Vector2 = at + velocity * arc.age + Vector2(0.0, 172.0 * arc.age * arc.age) # 全部从同一落点飞出。
		var tangent: Vector2 = velocity + Vector2(0.0, 344.0 * arc.age) # 飞溅拖尾总是反向跟随碎光。
		draw_line(position - tangent * 0.047 * fade, position, Color("cfefff", fade * 0.76), 1.2 + blast, true)

## 在 [param center] 绘制 [param sizes] 规定的软边加色光斑，使用 [param tint] 共同衰减。
func _glow(center: Vector2, sizes: Vector2, tint: Color) -> void:
	if tint.a > 0.003:
		draw_texture_rect(_halo, Rect2(center - sizes * 0.5, sizes), false, tint)
