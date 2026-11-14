## 寒冰命中的短促霜雾与碎晶；复用原生命中特效脱离、穿透复制及僵王层级管线。
extends BulletEffect000Base

## 原画中的六帧霜雾，仅取单帧做柔和扩散，不创建常驻粒子发射器。
const FROST_PUFF: Texture2D = preload("res://assets/image/particles/bullet/SnowPea_puff.png")
## 命中后的表现年龄，未激活时保持零且不处理帧。
var _age: float = 0.0
## 深寒稍留一缕蓝霜，棱锥则保持最短的碎晶节奏；单位为秒。
var _duration: float = 0.28
## 深寒配色只来自发射快照，不读取目标当前寒冷状态。
var _deep_cold: bool = false
## 棱锥以三片碎晶替代圆豆的五片，减少跨行穿透时的遮挡。
var _prism: bool = false
## 原生溅射贴图，瞬间显示后随霜雾一起淡出。
var _splats: Sprite2D
## 可选攻击来源上下文，切轮或退出战斗后及时回收表现。
var _attack_context: PlantAttackContext
## 可选发射门禁，继承转职弹的阶段有效性，不绑定即将释放的弹体。
var _attack_validity: Callable

## 未命中的模板不处理帧，穿透复制后也从静止状态开始。
func _ready() -> void:
	_splats = get_node_or_null(^"Splats") as Sprite2D
	set_process(false)

## [param is_boss_hit] 沿用原生显示层级；只冻结外观和来源，不触发额外命中或寒冷。
func activate_bullet_effect(is_boss_hit: bool = false) -> void:
	var bullet: Bullet002PeaSnow = get_parent() as Bullet002PeaSnow # 脱离前读取本次弹体，穿透复制同样挂在此父节点。
	if bullet != null:
		_deep_cold = bullet.promotion_shot != null and bullet.promotion_shot.loadout.has(&"deep_cold")
		_prism = bullet.is_prism
		_attack_context = bullet.attack_context
		_attack_validity = bullet.attack_validity
		rotation = bullet.direction.angle()
	_duration = 0.22 if _prism else (0.31 if _deep_cold else 0.28)
	_age = 0.0
	if _splats != null:
		_splats.frame = int(get_instance_id() % _splats.hframes)
		_splats.scale = Vector2.ONE * (0.65 if _prism else 0.82)
		_splats.modulate = Color(0.71, 0.90, 1.0, 0.65) if _deep_cold else Color(0.91, 1.0, 1.0, 0.58)
		_splats.visible = true
	super(is_boss_hit)
	visible = true
	set_process(true)
	queue_redraw()

## [param delta] 为有效表现秒；寿命固定，不在命中结束后留下白团或额外常驻节点。
func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration or (_attack_context != null and not _attack_context.is_active()) \
			or (_attack_validity.is_valid() and not bool(_attack_validity.call())):
		queue_free()
		return
	if _splats != null:
		_splats.modulate.a = maxf(0.0, 1.0 - _age / 0.10) * 0.62
	queue_redraw()

## 三团低透明霜雾和固定数量尖晶均限制在命中点附近，穿透齐射也能看清目标。
func _draw() -> void:
	if not visible:
		return
	var progress: float = clampf(_age / _duration, 0.0, 1.0) # 一次命中的归一化生命周期。
	var fade: float = pow(1.0 - progress, 1.6) # 快速消退，避免末帧停留。
	var spread: float = 1.0 - pow(1.0 - progress, 3.0) # 碎晶先弹开再减速。
	var mist: Color = Color(0.49, 0.73, 1.0, fade * 0.29) if _deep_cold else Color(0.72, 0.94, 1.0, fade * 0.25) # 蓝雾不形成不透明白圈。
	var frame_size: Vector2 = Vector2(FROST_PUFF.get_width() / 6.0, FROST_PUFF.get_height()) # 原画六列等宽帧。
	var source: Rect2 = Rect2(Vector2(frame_size.x * 2.0, 0.0), frame_size) # 中间帧的软边霜纹。
	for index: int in range(3): # 三片固定雾纹沿命中方向微微展开，不堆叠粒子系统。
		var offset: Vector2 = Vector2(-3.0 + spread * float(index * 4), float(index - 1) * (3.0 + spread * 4.0)) # 覆盖范围约二十像素。
		var size: Vector2 = Vector2(17.0 + spread * 11.0, 14.0 + spread * 9.0) * (0.78 if _prism else 1.0) # 冰锥命中略小于普通雪豆。
		draw_texture_rect_region(FROST_PUFF, Rect2(offset - size * 0.5, size), source, mist)
	for index: int in range(3 if _prism else 5): # 每击最多五枚碎晶，数量不随僵尸或帧率增加。
		var angle: float = -1.95 + float(index) * (1.72 if _prism else 0.94) # 以弹体来向为基准，向侧面和前方裂开。
		var direction: Vector2 = Vector2.from_angle(angle) # 碎晶只作视觉运动，不创建碰撞体。
		var point: Vector2 = direction * (4.0 + spread * (10.0 + float(index % 2) * 5.0)) + Vector2(spread * 3.0, 0.0) # 扩散半径最多十九像素。
		var size: float = (3.5 if index % 2 == 0 else 2.7) * (1.0 - progress * 0.65) # 尾段缩小并淡出。
		var side: Vector2 = direction.orthogonal() * size * 0.38 # 薄晶宽度小于长度，区别于雪花白点。
		draw_colored_polygon(PackedVector2Array([point - direction * size, point + side, point + direction * size, point - side]),
			Color(0.67, 0.89, 1.0, fade * 0.78))
		draw_line(point - direction * size * 0.55, point + direction * size * 0.7, Color(0.94, 1.0, 1.0, fade * 0.82), 0.75, true)
