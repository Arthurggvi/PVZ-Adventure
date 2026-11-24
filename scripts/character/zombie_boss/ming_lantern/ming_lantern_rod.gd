## 青色灯条：落地后才成为可被攻击的设施，闪烁到期触发水下爆炸。
extends EnemyStructureBase
class_name MingLanternRod

## 落地时通知明灯演出与结算落点。
signal landed(rod: MingLanternRod)
## 倒计时结束或被浪引爆时通知明灯演出与结算爆炸。
signal burst(rod: MingLanternRod)

## 从素材包裁切的透明灯条原画，默认横向。
const ROD: Texture2D = preload("res://assets/adventure/zombies/ming_lantern/lantern_rod.png")
## 落地前的奔落时间，单位战斗秒。
const FALL_TIME := 0.56
## 起点高出落点的垂直距离，单位为局部像素。不同倾角从同一高度进入。
const FALL_HEIGHT := 662.0
## 落地后可被击杀的时长，单位战斗秒。
const FUSE_TIME := 10.0
## 灯条与地表的交点。相对格中心稍偏右，与既有受击框对齐。
const CONTACT := Vector2(14.0, -2.0)
## 灯条未沉入地面时的尺寸，单位为局部像素。
const SHAFT_SIZE := Vector2(108.0, 17.4)
## 水光从灯管尾端内侧发出。与原画重叠的 17 像素遮住拖尾的收口。
const TRAIL_ATTACHMENT_DISTANCE := SHAFT_SIZE.x - 17.0

## 实际作用的逻辑格坐标，X 为行、Y 为列。
var address: Vector2i
## 是否进入落地状态；下降过程不允许碰撞引爆。
var is_planted := false
## 从落点指向入场起点的单位向量，Y 为负。入树前设定，同时决定灯管朝向和飞行路径。
var flight_axis := Vector2.UP
## 入树后经过的战斗秒数。
var _age := 0.0
## 灯身、水面反照和飞溅的加色层。
var _light: Node2D
## 落地后是否已经引爆，防止波浪、计时和销毁同帧重复处理。
var _detonated := false

## 使用通用设施受击框；降落前不可被索敌。
func ready_norm() -> void:
	super.ready_norm()
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	_set_hp_visible(false)

## 无碰撞舞台上复用完整坠落、引信和爆炸。
func ready_show() -> void:
	super.ready_show()
	_set_hp_visible(false)

## 子节点准备完毕后建立灯芯与接触水面的亮层。
func _ready() -> void:
	super._ready()
	_light = MingLanternArt.light_layer(self, _draw_light)

## 可选的实时下坠倍率；钉入后的设施引信使用固定战斗秒。
var fall_rate: Callable

## [param delta] 为战斗秒数；经过插入帧时只通知一次。
func _process(delta: float) -> void:
	_age += delta * float(fall_rate.call()) if not is_planted and fall_rate.is_valid() else delta
	if not is_planted and _age >= FALL_TIME:
		is_planted = true
		if not is_show:
			hurt_box_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
			_set_hp_visible(Global.config_service.display_zombie_HP_label)
		landed.emit(self)
	if is_planted and _age >= FALL_TIME + FUSE_TIME:
		detonate()
	queue_redraw()
	_light.queue_redraw()

## 倒计时或浪触发爆炸，与已经被击杀的设施互斥。
func detonate() -> void:
	if not is_planted or is_death or _detonated or is_queued_for_deletion():
		return
	_detonated = true
	burst.emit(self)
	character_death()

## [param enabled] 只在落地后允许生命标签显示。
func _set_hp_visible(enabled: bool) -> void:
	hp_component.change_display_HP_label(enabled)

## 返回 [param time] 处的飞行灯尖。[param axis] 沿灯管由尖端指向尾端，Y 为负。
static func flight_tip(time: float, axis: Vector2) -> Vector2:
	var progress: float = clampf(time / FALL_TIME, 0.0, 1.0) # 归一化时间，到落地帧时正好取 1。
	var height: float = FALL_HEIGHT * (1.0 - pow(progress, 2.08)) # 剩余垂直距离随时间加速缩短。
	return CONTACT + axis * (height / -axis.y)

## 返回 [param time] 处拖尾的历史接点。[param axis] 为飞行时的灯管轴线。
static func flight_trail_attachment(time: float, axis: Vector2) -> Vector2:
	return flight_tip(time, axis) + axis * TRAIL_ATTACHMENT_DISTANCE

## 返回当前灯管尾端在局部空间的变换。原点跟随下沉和回弹，X 轴朝向尾迹。
func trail_attachment() -> Transform2D:
	var angle: float = _angle() # 与原画共用实时俯仰，接地后的摆动也计入。
	var origin: Vector2 = _tip() + Vector2.from_angle(angle) * TRAIL_ATTACHMENT_DISTANCE # 带状水光在可见灯管内部收口。
	return Transform2D(angle, origin)

## 返回当前姿态。下半截入地，反弹的力只驱动深度和俯仰。
func _angle() -> float:
	var angle: float = flight_axis.angle() # 整段飞行保持灯管与速度共线。
	if not is_planted:
		return angle
	var contact_age: float = _age - FALL_TIME # 压入地面时额外侧倒，之后带阻尼地回到支撑角。
	var kick: float = sin(contact_age * 22.0) * exp(-contact_age * 6.8) * 0.28 # 一次主摆后逐渐静止。
	return angle + signf(flight_axis.x) * kick

## 返回当前灯尖。已插入的部分在地表下，灯身与地表的交点保持固定。
func _tip() -> Vector2:
	if not is_planted:
		return flight_tip(_age, flight_axis)
	var contact_age: float = _age - FALL_TIME # 从撞击开始计时，单位战斗秒。
	var buried: float = 19.0 * (1.0 - exp(-contact_age * 17.0)) \
		+ 7.0 * sin(contact_age * 26.0) * exp(-contact_age * 8.5) # 下刺后微弹，最低处埋在湿地板。
	var axis := Vector2.from_angle(_angle()) # 由下端指向露在外面的灯身。
	return CONTACT + Vector2(buried * axis.x / axis.y, buried)

## 返回灯身实际发亮的重心，与倾倒后的位置和入地深度保持一致。
func _light_center() -> Vector2:
	var distance: float = 55.0 if not is_planted else 45.0 # 插入状态从地表算露出部分。
	return (CONTACT if is_planted else _tip()) + Vector2.from_angle(_angle()) * distance

## 灯条由低频呼吸过渡到急闪；相位积分保证速度连续加快。
func _intensity() -> float:
	if not is_planted:
		return 0.98
	var time: float = _age - FALL_TIME # 插入后才消耗十秒引信。
	var phase: float = TAU * (0.68 * time + 0.225 * time * time) # 频率从 0.68 增至 5.18 Hz。
	return 0.32 + 0.68 * pow(0.5 + 0.5 * cos(phase), 1.35)

## 向 [param lighting] 提供随灯身下落的照明，落地后表面随引信脉冲逐次亮起。
func draw_scene_light(lighting: MingLanternLighting) -> void:
	var pulse: float = _intensity() # 引信闭合时仍留有较弱的余光。
	lighting.cast(self, _light_center(), Vector2(141, 163), Color("24dfff"), pulse * 0.72)
	if is_planted:
		var contact: float = 1.0 - smoothstep(FALL_TIME, FALL_TIME + 0.41, _age) # 初次碰撞的扩散比常亮投影更强。
		lighting.cast(self, CONTACT + Vector2(5, 7), Vector2(188, 105), Color("78fff0"),
			pulse * 0.19 + contact * 0.55)

## 飞行与斜插沿用原画。插入的那一截被地表截掉，前沿的水膜贴住灯身。
func _draw() -> void:
	var tip: Vector2 = _tip() # 灯尖在触地后进入槽缝。
	var angle: float = _angle() # 入地后围绕同一个落点摆动。
	var intensity: float = _intensity() # 端帽不随引信完全熄灭。
	var brightness: float = 0.43 + 0.57 * intensity # 原画暗下去时仍保留立体轮廓。
	if is_planted:
		_draw_footprint(intensity)
	var covered: float = maxf(0.0, (tip.y - CONTACT.y) / -sin(angle)) if is_planted else 0.0 # 沿灯身裁去水面以下的端帽。
	var source_x: float = ROD.get_width() * covered / SHAFT_SIZE.x # 世界长度换算为原图裁切。
	draw_set_transform(tip, angle)
	draw_texture_rect_region(ROD, Rect2(covered, -SHAFT_SIZE.y * 0.5, SHAFT_SIZE.x - covered, SHAFT_SIZE.y),
		Rect2(source_x, 0.0, ROD.get_width() - source_x, ROD.get_height()),
		Color(brightness, brightness, 0.72 + 0.28 * brightness))
	draw_set_transform(Vector2.ZERO)
	if is_planted:
		_draw_surface_lip(intensity)

## [param intensity] 让水面裂口和投影响应灯芯。黑色压痕留在地上。
func _draw_footprint(intensity: float) -> void:
	MingLanternArt.glow(self, CONTACT + Vector2(1, 7), Vector2(104, 45), Color("020c1cba"))
	draw_set_transform(CONTACT, -0.08 * signf(flight_axis.x))
	# 不规则的暗色凹口和碎屑沿水面的横向透视展开。
	var slot := PackedVector2Array([Vector2(-31, 4), Vector2(-14, -3), Vector2(-9, -6), Vector2(9, -5),
		Vector2(17, -2), Vector2(31, 3), Vector2(17, 7), Vector2(6, 12), Vector2(-12, 8)]) # 地面开口的多边形。
	draw_colored_polygon(slot, Color("040c1dd3"))
	draw_polyline(PackedVector2Array([Vector2(-28, 5), Vector2(-17, 8), Vector2(-15, 5), Vector2(-9, 9),
		Vector2(3, 10), Vector2(11, 8), Vector2(24, 6)]), Color("137c8f", 0.46 + intensity * 0.27), 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(11, -3), Vector2(20, -7), Vector2(25, -6), Vector2(36, -10)]),
		Color("55b9c9", intensity * 0.37), 1.3, true)
	draw_set_transform(Vector2.ZERO)

## 用 [param intensity] 绘制压在灯身前的水膜和薄反光，盖住与地面的交接线。
func _draw_surface_lip(intensity: float) -> void:
	var rim := PackedVector2Array([Vector2(-18, 0), Vector2(-11, 2), Vector2(-7, 0), Vector2(1, 1),
		Vector2(9, -1), Vector2(11, 2), Vector2(18, -1), Vector2(11, 7), Vector2(1, 8), Vector2(-13, 5)]) # 水的前沿略高于压痕。
	draw_set_transform(CONTACT, 0.0)
	draw_colored_polygon(rim, Color("0b2a3ee5"))
	draw_polyline(PackedVector2Array([Vector2(-16, 0), Vector2(-11, 2), Vector2(-7, 0), Vector2(1, 1),
		Vector2(9, -1), Vector2(11, 2), Vector2(17, -1)]), Color("74fbf6", 0.38 + 0.52 * intensity), 1.25, true)
	draw_set_transform(Vector2.ZERO)

## [param canvas] 绘制灯芯与击穿地表时外推的水纹。独立拖尾由落点节点保留。
func _draw_light(canvas: Node2D) -> void:
	var center: Vector2 = _light_center() # 加色光斑以可见灯身为重心。
	var intensity: float = _intensity() # 灯芯、反射和地面随引信一起变亮。
	canvas.draw_set_transform(center, _angle())
	MingLanternArt.glow(canvas, Vector2.ZERO, Vector2(194, 91), Color(MingLanternArt.CYAN, intensity * 0.73))
	MingLanternArt.glow(canvas, Vector2.ZERO, Vector2(158, 42), Color("c3ffff", intensity * 0.63))
	canvas.draw_set_transform(Vector2.ZERO)
	if not is_planted:
		return
	MingLanternArt.glow(canvas, CONTACT + Vector2(6, 6), Vector2(178, 71), Color("28cbf6", intensity * 0.32))
	var time: float = _age - FALL_TIME # 入水后才生成半秒的碎浪与上浮气泡。
	if time < 0.74:
		_draw_impact(canvas, time)

## 在 [param canvas] 绘制 [param time] 秒处的触地水花。波纹减速并拉扁，气泡随后上浮。
func _draw_impact(canvas: Node2D, time: float) -> void:
	var impact: float = 1.0 - smoothstep(0.015, 0.42, time) # 青白落点光先闪后收。
	var spread: float = 1.0 - exp(-time * 5.0) # 水波从狭窄裂口被向外推开。
	var ripple: float = (1.0 - smoothstep(0.17, 0.65, time)) * smoothstep(0.0, 0.06, time) # 薄浪消散后留地面暗槽。
	MingLanternArt.glow(canvas, CONTACT, Vector2(205, 90), Color("a0fff6", impact * 0.69))
	canvas.draw_set_transform(CONTACT, 0.0, Vector2(1.0, 0.28))
	canvas.draw_arc(Vector2.ZERO, lerpf(17.0, 79.0, spread), -0.2, PI * 1.78, 30, Color("9cfff7", ripple * 0.74), 2.0, true)
	canvas.draw_arc(Vector2.ZERO, lerpf(11.0, 59.0, spread), PI * 0.59, TAU + PI * 0.27, 29, Color("27d7ff", ripple * 0.59), 2.5, true)
	canvas.draw_set_transform(Vector2.ZERO)
	for index: int in range(11): # 稀疏小泡随大小具有不同上浮高度。
		var seed: float = float(index) * 2.39996 # 用黄金角错开飞溅方向。
		var point := CONTACT + Vector2(cos(seed) * 69.0, sin(seed) * 15.0) * spread # 水阻后横向位移逐渐停止。
		point.y -= time * (22.0 + fposmod(seed * 43.0, 64.0)) # 形成接触后从地表升起的气泡。
		var size: Vector2 = Vector2.ONE * (4.0 + fposmod(seed * 7.0, 12.0)) # 极小泡沫间夹少数膨大的气泡。
		canvas.draw_texture_rect(MingLanternArt.BUBBLE, Rect2(point - size * 0.5, size), false,
			Color("8af6ff", (0.6 + 0.4 * ripple) * (1.0 - smoothstep(0.2, 0.74, time))))
