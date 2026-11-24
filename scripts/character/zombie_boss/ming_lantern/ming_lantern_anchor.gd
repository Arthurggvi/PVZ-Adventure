## 明灯的巨锚。锚尖加速至触地，水面承受冲量向外散开，锚身从同一水线下沉。
extends Node2D
class_name MingLanternAnchor

## 锚尖第一次触地，伤害、镜头冲击和撞击声由此一起触发。
signal anchor_landed

## 从地面预兆出现到锚尖触地的战斗秒数。
const IMPACT_TIME := 0.78
## 短暂预兆后开始下坠的战斗时刻。
const FALL_START := 0.16
## 锚尖从落点右上方进入，向左下方加速。
const FALL_OFFSET := Vector2(51.0, -620.0)
## 锚身使用原画比例，尺寸单位为局部像素。
const ANCHOR_SIZE := Vector2(218.0, 240.0)
## 锚尖在原画中的归一化坐标，旋转和触地均绕此点。
const TIP_UV := Vector2(0.5, 0.996)
## 下坠的水迹只保留短暂的战斗秒数。
const TRAIL_TIME := 0.18
## 触地受力后保持一拍，再开始缓沉。
const SINK_DELAY := 0.16
## 触地后锚身完全没入的战斗秒数。
const SINK_END := 1.44
## 冲击水纹扫过棋盘后退亮的战斗秒数。
const SURGE_TIME := 1.10
## 给水纹波峰与碎沫预留的面片外边距比例。
const FIELD_MARGIN := 1.23
## 原画来自明灯素材包。
const ANCHOR: Texture2D = preload("res://assets/adventure/zombies/ming_lantern/anchor.png")
## 通过世界空间的实际水线裁切下沉的锚身。
const ANCHOR_SHADER: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_anchor.gdshader")
## 受力后贴着地面扩散的水脊、冲击纹和碎沫。
const SURGE_SHADER: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_anchor_impact.gdshader")

## 落地的 3×3 参考半宽高，由实际格子尺寸确定。
var extent := Vector2(141.0, 100.0)
## 水纹沿着棋盘传播，到达这片水域的世界坐标边缘时散开。
var water_area: Rect2
## 入树后经过的战斗秒数，贯穿下坠、撞击和沉没。
var _age := 0.0
## 起浪位置决定泡沫细纹相位，不占用战斗随机源。
var _phase := 0.0
## 地面水纹的世界横纵半径，横向延伸以贴合棋盘视角。
var _surface_extent := Vector2.ZERO
## 绕锚尖旋转的实际锚身。
var _body: Sprite2D
## 根据锚尖位移与地面水线计算可见金属的材质。
var _body_material: ShaderMaterial
## 落地后铺在锚身背后的水面冲击面片。
var _surge: ColorRect
## 与真实触地帧同步的扩散水面材质。
var _surge_material: ShaderMaterial
## 在锚身前回落的飞溅泡沫。
var _spray: Node2D

## 组装锚身、水面和前景泡沫。所有部件以真实触地点作为原点。
func _ready() -> void:
	_phase = global_position.dot(Vector2(0.028, 0.051))
	_surface_extent = extent * Vector2(3.36, 1.15)
	_surge_material = ShaderMaterial.new()
	_surge_material.shader = SURGE_SHADER
	_surge_material.set_shader_parameter(&"field_margin", FIELD_MARGIN)
	_surge_material.set_shader_parameter(&"phase", _phase)
	_surge_material.set_shader_parameter(&"water_min", water_area.position)
	_surge_material.set_shader_parameter(&"water_max", water_area.end)
	_surge = ColorRect.new()
	_surge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surge.position = -_surface_extent * FIELD_MARGIN
	_surge.size = _surface_extent * (FIELD_MARGIN * 2.0)
	_surge.material = _surge_material
	_surge.z_index = -2 # 让棋盘水纹先进入滔天震颤的折射快照。
	_surge.hide()
	add_child(_surge)
	_body_material = ShaderMaterial.new()
	_body_material.shader = ANCHOR_SHADER
	_body_material.set_shader_parameter(&"surface_y", global_position.y)
	_body_material.set_shader_parameter(&"phase", _phase)
	_body = Sprite2D.new()
	_body.texture = ANCHOR
	_body.centered = false
	_body.offset = -ANCHOR.get_size() * TIP_UV
	_body.scale = ANCHOR_SIZE / ANCHOR.get_size()
	_body.material = _body_material
	_body.z_index = 1 # 锚身盖住水面上的震颤折射。
	add_child(_body)
	_spray = Node2D.new()
	_spray.z_index = 2 # 喷起的泡沫位于锚身前方。
	_spray.draw.connect(_draw_spray)
	add_child(_spray)
	_update_pose()

## 读取本体下坠动作倍率的可选入口。触地余波使用固定战斗秒。
var fall_rate: Callable

## [param delta] 为战斗秒数。锚身越过触地时间后精确落位，且只通知一次命中。
func _process(delta: float) -> void:
	var before: float = _age # 跨越触地帧时仍投出一次冲击。
	_age += delta * float(fall_rate.call()) if before < IMPACT_TIME and fall_rate.is_valid() else delta
	_update_pose()
	if before < IMPACT_TIME and _age >= IMPACT_TIME:
		anchor_landed.emit()
	if _age >= IMPACT_TIME + SINK_END:
		queue_free()
		return
	queue_redraw()
	_spray.queue_redraw()

## 返回 [param time] 时的锚尖局部位置。下降曲线在撞地前持续加速。
func _fall_tip(time: float) -> Vector2:
	var progress: float = clampf((time - FALL_START) / (IMPACT_TIME - FALL_START), 0.0, 1.0) # 出发点和落点都保持精确。
	return FALL_OFFSET * (1.0 - pow(progress, 2.36))

## 推进触地后的压入、缓沉和地面冲击。水面保持固定，遮住逐渐下降的锚身。
func _update_pose() -> void:
	var contact_time: float = _age - IMPACT_TIME # 负值处于下坠阶段，零为触地。
	if contact_time < 0.0:
		_body.position = _fall_tip(_age)
		_body.rotation = lerpf(-0.115, -0.032, smoothstep(FALL_START, IMPACT_TIME, _age))
		return
	var compression: float = 21.0 * (1.0 - exp(-contact_time * 42.0)) # 前几个触地帧迅速压入，越过冲击后保持重量。
	var sink: float = smoothstep(SINK_DELAY, SINK_END, contact_time) # 锚沿水线缓缓没入，末段再沉稳收住。
	var settle: float = sin(contact_time * 18.0) * exp(-contact_time * 9.6) # 一次短促受力晃动，锚尖不反弹离地。
	_body.position = Vector2(-8.0 * sink, compression + (ANCHOR_SIZE.y + 9.0) * sink)
	_body.rotation = -0.032 - 0.059 * settle + 0.12 * sink
	_body_material.set_shader_parameter(&"immersed", true)
	_body_material.set_shader_parameter(&"contact_time", contact_time)
	_surge.visible = contact_time < SURGE_TIME
	if _surge.visible:
		_surge_material.set_shader_parameter(&"elapsed", contact_time)

## 绘制收束的落点水纹和短促灰蓝水迹。常规透明合成让残迹融进水体。
func _draw() -> void:
	if _age < IMPACT_TIME:
		var warning: float = smoothstep(0.015, 0.14, _age) # 水面先出现一圈收聚的细纹。
		var gathering: float = smoothstep(0.14, IMPACT_TIME, _age) # 受重物压迫，落点附近逐渐收束。
		MingLanternArt.glow(self, Vector2(0.0, 7.0), extent * Vector2(1.55, 0.77), Color("234758", warning * 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.34))
		draw_arc(Vector2.ZERO, extent.x * lerpf(0.82, 0.34, gathering), 0.08, TAU - 0.52, 38,
			Color("80aeb6", warning * (0.25 + gathering * 0.27)), 1.45, true)
		draw_set_transform(Vector2.ZERO)
	if _age > FALL_START and _age < IMPACT_TIME + TRAIL_TIME:
		_draw_trail()

## 水流沿锚身两侧被短暂拖着走。每段在原处卷开，触地后不继续写入。
func _draw_trail() -> void:
	var first: float = maxf(FALL_START, _age - TRAIL_TIME) # 最老仍可见的一段水迹。
	var last: float = minf(_age, IMPACT_TIME) # 只沿下坠轨迹取样。
	var tilt: float = Vector2(-FALL_OFFSET.x, -FALL_OFFSET.y).angle() - PI * 0.5 # 沿斜向下的流动拉长截面。
	for index: int in range(13): # 相邻软边彼此重叠，短路径连续而不露出方形切口。
		var fraction: float = float(index) / 12.0 # 从较老的水迹向锚身后方靠近。
		var birth: float = lerpf(first, last, fraction) # 这一段水迹被锚身拉开的时刻。
		var age_ratio: float = (_age - birth) / TRAIL_TIME # 从新生水流到扩散殆尽的比例。
		var bend: float = sin(birth * 29.0 + _phase) * 23.0 * age_ratio # 老段沿落水方向轻微偏转。
		var center: Vector2 = _fall_tip(birth) + Vector2(bend, -ANCHOR_SIZE.y * 0.30 - age_ratio * 26.0) # 近端从锚爪后方流出。
		var opacity: float = (1.0 - smoothstep(0.03, 1.0, age_ratio)) * smoothstep(0.0, 0.27, fraction) # 尾端柔和消散。
		draw_set_transform(center, tilt)
		MingLanternArt.glow(self, Vector2.ZERO, Vector2(87.0 + 45.0 * age_ratio, 122.0), Color("284c58", opacity * 0.31))
		MingLanternArt.glow(self, Vector2(36.0 + age_ratio * 19.0, -8.0), Vector2(31.0 + 24.0 * age_ratio, 116.0), Color("6c9a9e", opacity * 0.19))
		MingLanternArt.glow(self, Vector2(-39.0 - age_ratio * 13.0, 5.0), Vector2(25.0 + 21.0 * age_ratio, 102.0), Color("668a90", opacity * 0.13))
	draw_set_transform(Vector2.ZERO)

## 在真实触地帧把泡沫推出，以水阻消耗横向冲量，再让细沫扬起、回落和消失。
func _draw_spray() -> void:
	var elapsed: float = _age - IMPACT_TIME # 与水纹使用同一个撞击时钟。
	if elapsed <= 0.0 or elapsed >= SURGE_TIME:
		return
	_draw_splash_sheets(elapsed)
	for index: int in range(46): # 黄金角铺开泡沫，一部分上扬水柱会在触地瞬间被拖长。
		var seed: float = float(index) * 2.39996 + _phase # 独立控制这一片泡沫的出射方向和轮廓。
		var time: float = elapsed - fposmod(seed * 0.039, 0.072) # 边缘溅起略晚于正面水花。
		var lifetime: float = 0.34 + fposmod(seed * 0.27, 0.53) # 大水花回落后还留少量浮沫。
		if time <= 0.0 or time >= lifetime:
			continue
		var fraction: float = time / lifetime # 从喷出、扬起到回落。
		var impulse: float = exp(-time * 8.9) # 泡沫的水平速度被水阻迅速消耗。
		var direction := Vector2(cos(seed), sin(seed) * 0.58) # 俯视水面的纵向范围要比左右窄。
		var push: Vector2 = direction * extent * (0.69 + fposmod(seed * 0.97, 1.29)) # 每片泡沫的最大水平位移。
		var lift: float = 14.0 + fposmod(seed * 34.8, 71.0) # 一些较大的碎水片高一些，细泡贴水飘散。
		var point: Vector2 = push * (1.0 - impulse) + Vector2(0.0, -4.0 * lift * fraction * (1.0 - fraction)) # 水花先扬起再回落。
		var velocity: Vector2 = push * (8.9 * impulse) + Vector2(0.0, -4.0 * lift * (1.0 - 2.0 * fraction) / lifetime) # 拉伸方向追随真实运动。
		var size: float = 4.3 + fposmod(seed * 11.2, 13.0) # 水珠从细斑到近距离的可见泡沫。
		var stretch: float = 1.0 + impulse * 2.35 # 初次喷出呈撕开的水丝，减速后恢复为小气泡。
		var opacity: float = smoothstep(0.0, 0.025, time) * (1.0 - smoothstep(0.43, 1.0, fraction)) # 水丝消失时不会定格。
		_spray.draw_set_transform(point, velocity.angle(), Vector2(stretch, 1.0))
		_spray.draw_texture_rect(MingLanternArt.BUBBLE, Rect2(Vector2.ONE * size * -0.5, Vector2.ONE * size),
			false, Color(0.73, 0.94, 0.96, 0.88 * opacity))

## 撞击后的 [param elapsed] 秒内，两股水先横向扬起，再坍回扩散的水纹。
func _draw_splash_sheets(elapsed: float) -> void:
	if elapsed >= 0.32:
		return
	var reach: float = 1.0 - exp(-elapsed * 12.0) # 水刚被挤出时横向位移最快。
	var lift: float = smoothstep(0.0, 0.06, elapsed) * (1.0 - smoothstep(0.10, 0.31, elapsed)) # 扬起后回落到棋盘的水面。
	var fade: float = smoothstep(0.0, 0.022, elapsed) * (1.0 - smoothstep(0.13, 0.32, elapsed)) # 薄水片并入泡沫与前缘水纹。
	_spray.draw_set_transform(Vector2.ZERO)
	for side: float in [-1.0, 1.0]: # 两股水同时受力，使用不同的破碎相位。
		var roots := PackedVector2Array() # 浪脚留在水面，与冲击面片相接。
		var crests := PackedVector2Array() # 水片高度沿着水股变化，外缘中段扬得最高。
		var root_colors := PackedColorArray() # 根部使用透明水色，让水片与地面接合。
		var crest_colors := PackedColorArray() # 透光的薄水片在断续峰顶挂出浅色泡沫。
		for index: int in range(15): # 密采样不规则边缘，避免变成一块直边的三角形。
			var section: float = float(index) / 14.0 # 从落点方向走向水股外缘。
			var taper: float = sin(PI * section) # 水股在两端都收薄。
			var churn: float = sin(section * 17.0 + side * _phase - elapsed * 19.0) # 表面扯出高低不同的水舌。
			var root_point := Vector2(side * extent.x * reach * (0.16 + 1.18 * section), extent.y * reach * (0.13 + 0.36 * section * section)) # 水股沿着前景水面展开。
			var height: float = 3.0 + taper * (57.0 + 22.0 * churn) * lift # 水舌中段上扬，回落前边缘开始断开。
			roots.append(root_point)
			crests.append(root_point - Vector2(0.0, height))
			root_colors.append(Color(0.17, 0.43, 0.49, taper * fade * 0.19))
			crest_colors.append(Color(0.69, 0.88, 0.91, taper * fade * (0.38 + 0.28 * maxf(0.0, churn))))
		crests.reverse()
		crest_colors.reverse()
		_spray.draw_polygon(roots + crests, root_colors + crest_colors)

## 将落点和贴地传播的冲击反光交给 [param lighting]，锚身的下坠水迹不参与投光。
func draw_scene_light(lighting: MingLanternLighting) -> void:
	var elapsed: float = _age - IMPACT_TIME # 水脊形成前只保留画在地上的少量水纹。
	if elapsed < 0.0 or elapsed >= SURGE_TIME:
		return
	var pressure: float = 1.0 - exp(-elapsed * 5.1) # 与着色器的压力前缘共用扩散速度。
	var front: float = 0.065 + 0.935 * pressure # 让光场投射到正在扫过棋盘的波前。
	var vigor: float = smoothstep(0.0, 0.038, elapsed) * (1.0 - smoothstep(0.16, SURGE_TIME, elapsed)) # 大面积反光退去后保留低矮细纹。
	lighting.cast(self, Vector2.ZERO, _surface_extent * (front / 0.72), Color("83c9d0"), vigor * 0.37, true)
	lighting.cast(self, Vector2.ZERO, extent * Vector2(1.14, 0.69),
		Color("b6e5eb"), (1.0 - smoothstep(0.02, 0.29, elapsed)) * 0.54)
