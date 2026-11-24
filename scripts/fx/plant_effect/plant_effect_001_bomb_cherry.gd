## 樱桃主爆与转职分支的表现；范围参数只用于绘制，不决定伤害或控制。
extends BombEffectBase
class_name BombEffectCherryBomb

## 原版 POWIE 的螺旋烟团纹理，仅用于外围高速小烟团。
const CLOUD_TEXTURE := preload("res://assets/image/particles/ExplosionCloud.png")
## 原版柔光让爆心有瞬时热亮，避免以实心色圆遮挡场景。
const GLOW_TEXTURE: Texture2D = preload("res://assets/reanim/Zombie_boss_fireball_superglow.png")
## 原版爆炸卷云自带软明暗层次，作为主体，螺旋烟团只保留在外侧。
const PLUME_TEXTURE: Texture2D = preload("res://assets/image/particles/BossExplosion2.png")
## 原版白热爆心，短闪后让位给翻卷烟焰。
const CORE_TEXTURE: Texture2D = preload("res://assets/image/particles/BossExplosion3.png")
## 原版火球尾焰图集，首片用于扩张火浪，避免串成一圈重复的螺旋图标。
const FIRE_TEXTURE: Texture2D = preload("res://assets/image/particles/Zombie_boss_fireball_particles.png")
## 原版主爆时叠加的果肉迸裂声。
const BURST_SFX := preload("res://assets/audio/sounds/juicy.ogg")
## 原版粒子参数按 100 Hz 推进。
const TICKS_PER_SECOND := 100.0
## 每层以每秒 150 颗的速度发射，达到上限后停止。
const CLOUDS_PER_SECOND := 150.0
## 单层烟团发射上限。
const CLOUD_LIMIT := 14
## 小爆炸的单层烟团上限，连锁触发时保持可读性。
const SMALL_CLOUD_LIMIT := 4
## POWIE 字样停留的原版粒子帧数。
const WORD_TICKS := 50

## 单颗烟团的发射状态。
class BlastCloud:
	## 相对于爆心的像素坐标。
	var position: Vector2
	## 当前速度，每个粒子帧移动的像素数。
	var velocity: Vector2
	## 当前旋转角，单位为弧度。
	var angle: float
	## 烟团的每帧自转角，单位为弧度。
	var spin: float
	## 发射时的贴图缩放。
	var initial_scale: float
	## 已存活的粒子帧数。
	var age := 0
	## 粒子寿命，单位为粒子帧。
	var lifetime: int

## 爆心上方绘制的原版 POWIE 字样。
@onready var explosive_font: Sprite2D = $ExplosiveFont
## 私有随机源，爆炸表现不影响战斗随机抽样。
var _rng := RandomNumberGenerator.new()
## 高速喷出的外层小烟团。
var _small_clouds: Array[BlastCloud] = []
## 较慢扩张的内层大烟团。
var _large_clouds: Array[BlastCloud] = []
## 已发射的每层烟团总数，包含已消失的粒子。
var _launched := 0
## 已模拟的粒子帧数。
var _ticks := 0
## 累积的战斗秒数，用于将引擎帧换算为粒子帧。
var _elapsed := 0.0
## 恶果等小爆炸只播放缩小烟团，不发送震屏事件。
var small_burst: bool = false
## 仅樱桃场景启用分层新版表现；共用本脚本的小丑和爆炸保龄球保留原有演出。
@export var cherry_presentation: bool = false
## 真实伤害范围换算到本节点的半宽、半高；聚变使用完整矩形轮廓。
var _extent: Vector2 = Vector2(120.0, 120.0)
## 震爆外扩范围；零向量表示没有冲击波分支。
var _shock_extent: Vector2 = Vector2.ZERO
## 聚变使用圆角方形火浪，覆盖到 5×5 的四角。
var _fusion: bool = false
## 恐惧之果增加赤红外焰与厚重尾烟，保持暖白爆心。
var _fear: bool = false
## 赤核使用红橙尾焰，火花则增加细长金色飞屑。
var _red_core: bool = false
## 火花分支增加喷射火星的数量，不改变战斗随机源。
var _spark: bool = false
## 子母雷首爆到追爆的真实间隔；中间保留逐渐收紧的余热。
var _echo_delay: float = 0.0
## 当前是否是子母雷的第二次爆炸，用更紧凑的亮芯区分首爆。
var _echo: bool = false
## 烟团位置的横纵扩张倍率；字样独立保留可读大小。
var _cloud_spread: Vector2 = Vector2.ONE

## 按 [param rules] 配置转职表现；[param size]、[param shock_size] 为真实范围的世界尺寸。
## [param echo] 区分子母雷追爆；恶果不继承主爆的大范围烟团或震屏。
func configure_presentation(rules: Dictionary[String, Dictionary], size: Vector2,
		shock_size: Vector2, echo: bool = false) -> void:
	cherry_presentation = true
	_fear = rules.has("cherry_fruit_of_fear")
	_red_core = rules.has("cherry_red_core")
	_spark = rules.has("cherry_spark")
	_echo = echo
	if small_burst:
		return
	var world_scale: Vector2 = global_scale.abs().max(Vector2(0.001, 0.001)) # 首爆可能挂在缩放后的母株上。
	_extent = size / world_scale * 0.5
	_shock_extent = shock_size / world_scale * 0.5
	_fusion = rules.has("cherry_fusion")
	_echo_delay = float(rules.get("cherry_double_blast", {}).get("delay", 0.0)) if not echo else 0.0
	if _fusion:
		_cloud_spread = (_extent / Vector2(140.0, 115.0)).max(Vector2.ONE)

## 只在爆炸后驱动粒子。
func _ready() -> void:
	set_process(false)

## 在爆心播放两层烟团、POWIE 字样和原版幅度的短震。
func _play_effect() -> void:
	_rng.randomize()
	_emit_cloud_pair()
	queue_redraw()
	explosive_font.visible = not small_burst
	# 大范围只扩张烟焰，不把 POWIE 字样拉成覆盖棋盘的巨幅文字。
	if cherry_presentation:
		explosive_font.scale = Vector2.ONE * (0.85 if _echo else 1.0)
	if not small_burst:
		SoundManager.play_sfx_with_pool(BURST_SFX)
		EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(4, 5) if _fusion or _fear else Vector2(3, 4), 0.12])
	set_process(true)

## [param delta] 自上一帧经过的战斗秒数。
func _process(delta: float) -> void:
	_elapsed += delta
	# 第一对烟团在爆炸当帧出现，后续按原版发射节拍追加。
	var target_tick := 1 + floori(_elapsed * TICKS_PER_SECOND)
	# 恶果的烟团更少，也不显示原爆炸的大字样。
	var cloud_limit: int = SMALL_CLOUD_LIMIT if small_burst else CLOUD_LIMIT
	while _ticks < target_tick:
		_ticks += 1
		_advance_clouds(_small_clouds, 0.15)
		_advance_clouds(_large_clouds, 0.12)
		# 150 颗/秒在 100 Hz 下交替发射一颗和两颗，直到达到单层上限。
		var expected := mini(cloud_limit, floori(_ticks * CLOUDS_PER_SECOND / TICKS_PER_SECOND))
		while _launched < expected:
			_emit_cloud_pair()
	explosive_font.visible = not small_burst and _elapsed < WORD_TICKS / TICKS_PER_SECOND
	queue_redraw()
	var presentation_finished: bool = not cherry_presentation \
		or _elapsed >= (0.65 if small_burst else maxf(0.95, _echo_delay)) # 非樱桃消费者沿用原版烟团结束即回收。
	if presentation_finished and not explosive_font.visible and _small_clouds.is_empty() and _large_clouds.is_empty():
		queue_free()

## 每层各发射一颗烟团。
func _emit_cloud_pair() -> void:
	_small_clouds.append(_create_cloud(Vector2(20.0, 25.0), Vector2(0.5, 0.5)))
	_large_clouds.append(_create_cloud(Vector2(5.0, 12.0), Vector2(1.2, 1.6)))
	_launched += 1

## 从爆心外 10–50 像素沿径向抛出烟团。
## [param speed_range] 每个粒子帧的初速度范围，单位为像素。
## [param scale_range] 初始贴图缩放的最小和最大倍率。
func _create_cloud(speed_range: Vector2, scale_range: Vector2) -> BlastCloud:
	# 本次发射的径向方向，同时决定初始位置和速度。
	var direction := Vector2.from_angle(_rng.randf_range(0.0, TAU))
	# 新粒子在发射时随机选定速度、旋转和寿命。
	var cloud := BlastCloud.new()
	cloud.position = direction * _rng.randf_range(10.0, 50.0)
	cloud.velocity = direction * _rng.randf_range(speed_range.x, speed_range.y)
	cloud.angle = _rng.randf_range(0.0, TAU)
	cloud.spin = deg_to_rad(_rng.randf_range(-200.0, 200.0)) / TICKS_PER_SECOND
	cloud.initial_scale = _rng.randf_range(scale_range.x, scale_range.y)
	cloud.lifetime = _rng.randi_range(40, 60)
	return cloud

## [param clouds] 推进一层烟团，并移除寿命结束的粒子。
## [param initial_friction_x] 此层水平速度每帧损失的初始比例。
func _advance_clouds(clouds: Array[BlastCloud], initial_friction_x: float) -> void:
	# 反向遍历，删除到期粒子时不会跳过其他粒子。
	for index in range(clouds.size() - 1, -1, -1):
		# 当前推进的粒子。
		var cloud := clouds[index]
		cloud.age += 1
		if cloud.age >= cloud.lifetime:
			clouds.remove_at(index)
			continue
		# 寿命前 40% 保持初始阻力，随后逐步将速度降到零。
		var friction_progress := inverse_lerp(0.4, 1.0, maxf(0.4, float(cloud.age) / cloud.lifetime))
		cloud.velocity *= Vector2(1.0 - initial_friction_x, 0.82) * (1.0 - friction_progress)
		cloud.position += cloud.velocity
		cloud.angle += cloud.spin

## 先绘制小烟团，再绘制大烟团；字样由子节点覆盖在上方。
func _draw() -> void:
	if cherry_presentation:
		_draw_pressure_front()
		_draw_heat_flash()
		_draw_trailing_smoke()
	_draw_clouds(_small_clouds, Vector2(0.7, 0.0))
	_draw_clouds(_large_clouds, Vector2(0.9, 0.4))
	draw_set_transform(Vector2.ZERO)
	if cherry_presentation:
		_draw_core_bloom()
		_draw_sparks()
		_draw_echo_seed()

## [param clouds] 当前烟团层。
## [param green_range] 颜色从初始到寿命结束的绿色分量，红色为 1，蓝色为 0。
func _draw_clouds(clouds: Array[BlastCloud], green_range: Vector2) -> void:
	# 让纹理围绕粒子中心旋转。
	var inner: bool = cherry_presentation and green_range.x > 0.8 # 樱桃内层改用有明暗体积的卷云，其他爆炸仍用原版纹理。
	var texture: Texture2D = PLUME_TEXTURE if inner else CLOUD_TEXTURE # 两层使用不同轮廓，避免所有粒子像复制图标。
	var texture_origin := -texture.get_size() * 0.5
	for cloud: BlastCloud in clouds:
		# 粒子寿命进度，用来驱动颜色、缩小和淡出。
		var progress := float(cloud.age) / cloud.lifetime
		# 原版保持初始大小至寿命的 60%，随后缩小。
		var cloud_scale := cloud.initial_scale * clampf(inverse_lerp(1.0, 0.6, progress), 0.0, 1.0)
		# 原版保持全不透明至寿命的 70%，随后淡出。
		var alpha := clampf(inverse_lerp(1.0, 0.7, progress), 0.0, 1.0)
		var spread: Vector2 = _cloud_spread * (0.62 if inner else 1.0) # 中心卷云保持重叠，不能随着聚变散成空心圈。
		var tint := Color(1.0, lerpf(green_range.x, green_range.y, progress), 0.0, alpha) # 主体从暖白亮芯降温至橙红。
		if _fear or _red_core:
			tint.g *= 0.72 if _fear else 0.86
			tint.b = 0.04
		var hot: float = 1.0 - smoothstep(0.0, 0.22, progress) # 只在初生一瞬出现白热，不长期糊白。
		if cherry_presentation:
			tint = tint.lerp(Color(1.0, 0.95, 0.65, alpha), hot * 0.7)
		draw_set_transform(cloud.position * spread, cloud.angle,
			Vector2.ONE * cloud_scale * (0.72 if inner else 1.0) * (1.12 if _fear else 1.0))
		draw_texture(texture, texture_origin, tint)
	draw_set_transform(Vector2.ZERO)

## 在伤害范围边缘抛出有纹理的火浪；震爆使用更外侧、较淡的尘浪。
func _draw_pressure_front() -> void:
	if small_burst:
		return
	_draw_front(_extent, 0.0, false)
	if _shock_extent != Vector2.ZERO:
		_draw_front(_shock_extent, 0.035, true)

## 按 [param extent] 绘制扩张前沿；[param delay] 为纯表现错峰，[param dust] 选择震爆尘浪。
func _draw_front(extent: Vector2, delay: float, dust: bool) -> void:
	var age: float = _elapsed - delay # 前沿从爆心快速推向外圈。
	if age < 0.0 or age > 0.52:
		return
	var travel: float = 1.0 - pow(1.0 - clampf(age / 0.42, 0.0, 1.0), 3.0) # 先猛推、后减速。
	var opacity: float = (1.0 - smoothstep(0.18, 0.52, age)) * (0.42 if dust else 0.72) # 外圈不留下硬边。
	var count: int = 40 if _fusion else 24 # 大范围以衔接的火浪覆盖四角，而不是稀疏摆一圈小图标。
	for index: int in range(count): # 确定性分布，与战斗随机数无关。
		var angle: float = TAU * float(index) / float(count) # 均匀发散方向。
		var direction := Vector2(cos(angle), sin(angle)) # 基础圆形轮廓。
		if _fusion:
			direction = Vector2(signf(direction.x) * pow(absf(direction.x), 0.42),
				signf(direction.y) * pow(absf(direction.y), 0.42))
		var point: Vector2 = direction * extent * travel # 聚变扩成圆角方形，不能只加大圆形而漏掉四角。
		var size: float = (42.0 if dust else 58.0) * (0.8 + 0.2 * sin(float(index) * 2.39)) # 烟团尺寸错落，避免规则光环感。
		var tint := Color(0.85, 0.64, 0.37, opacity) if dust else Color(1.0, 0.34 if _fear else 0.57, 0.06, opacity) # 尘浪与火浪可辨认。
		draw_set_transform(point, angle, Vector2(1.0, 0.8))
		if dust:
			draw_texture_rect(PLUME_TEXTURE, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false, tint)
		else:
			draw_texture_rect_region(FIRE_TEXTURE, Rect2(Vector2(-size * 0.5, -size * 0.32), Vector2(size, size * 0.64)),
				Rect2(0.0, 0.0, 110.0, 74.0), Color(1.0, 0.75 if _fear else 0.96, 0.70, opacity))
	draw_set_transform(Vector2.ZERO)

## 爆心短闪只用柔光纹理；高阶保留亮芯和赤红外缘，不用大块不透明色遮屏。
func _draw_heat_flash() -> void:
	var strength: float = 1.0 - smoothstep(0.025, 0.21, _elapsed) # 快速起爆、迅速让出烟团轮廓。
	if strength <= 0.0:
		return
	var size: Vector2 = Vector2(210.0, 160.0) * (1.2 if _fear else 1.0) # 白热集中在爆心，不随 5×5 范围整片糊白。
	draw_texture_rect(GLOW_TEXTURE, Rect2(-size * 0.5, size), false, Color(1.0, 0.68, 0.25, strength * 0.85))

## 带不规则边缘的爆心快速撑开、回落；亮度在烟云前方，大小始终局限于中心。
func _draw_core_bloom() -> void:
	var strength: float = 1.0 - smoothstep(0.05, 0.24, _elapsed) # 白热仅占爆炸开头的瞬间。
	if strength <= 0.0:
		return
	var size: float = lerpf(90.0, 190.0 if _fear else 150.0, smoothstep(0.0, 0.16, _elapsed)) # 先冲开，再由时间包络收暗。
	draw_texture_rect(CORE_TEXTURE, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false,
		Color(1.0, 0.91, 0.53, strength * 0.9))

## 爆炸后半段残留少量灰褐烟团；短暂上升后淡出，给主爆增加重量。
func _draw_trailing_smoke() -> void:
	if small_burst or _elapsed < 0.14:
		return
	var opacity: float = smoothstep(0.14, 0.3, _elapsed) * (1.0 - smoothstep(0.40, 0.90, _elapsed)) # 火焰过后才显出烟尾。
	for index: int in range(7): # 全部等阶固定少量烟团，恶果连锁不额外发烟。
		var angle: float = TAU * float(index) / 7.0 # 分散在爆心外围。
		var point: Vector2 = Vector2.from_angle(angle) * Vector2(65.0, 42.0) * _cloud_spread # 范围扩张只影响分布。
		point.y -= (_elapsed - 0.14) * 42.0
		var size: float = (58.0 + float(index % 3) * 10.0) * (0.8 + _elapsed * 0.45) # 烟团缓慢膨胀。
		draw_set_transform(point, float(index) * 1.7)
		draw_texture_rect(PLUME_TEXTURE, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false,
			Color(0.20, 0.14 if _fear else 0.18, 0.15, opacity * 0.34))
	draw_set_transform(Vector2.ZERO)

## 径向火星带短拖尾，火花偏金色、赤核与四阶偏赤红；小连锁维持较低数量。
func _draw_sparks() -> void:
	var count: int = 6 if small_burst else (24 if _spark else 16) # 每次爆炸固定的粒子预算。
	for index: int in range(count): # 用下标生成稳定差异，不在绘制时抽随机数。
		var phase: float = float(index) * 2.39996 # 黄金角分布让喷射方向自然错开。
		var lifetime: float = 0.42 + fposmod(phase, 0.32) # 粒子错峰退场。
		var progress: float = _elapsed / lifetime # 超过寿命不再绘制。
		if progress >= 1.0:
			continue
		var direction := Vector2.from_angle(phase) # 抛射初始方向。
		var velocity: Vector2 = direction * (160.0 + fposmod(phase * 73.0, 180.0)) * _cloud_spread # 聚变向更大范围喷射。
		var point: Vector2 = velocity * _elapsed + Vector2(0.0, 160.0 * _elapsed * _elapsed) # 简单抛物线而非匀速直线。
		var tail: Vector2 = (velocity + Vector2(0.0, 320.0 * _elapsed)).normalized() * (5.0 + 7.0 * (1.0 - progress)) # 随速度缩短拖尾。
		var tint := Color(1.0, 0.39 if _red_core or _fear else 0.70, 0.10, 1.0 - smoothstep(0.45, 1.0, progress)) # 火星寿命后段淡出。
		draw_line(point - tail, point, Color(tint, tint.a * 0.32), 3.2, true)
		draw_line(point - tail * 0.45, point, tint, 1.5, true)

## 子母雷在两爆之间保留收紧的余热，追爆到时自然接续，不额外触发爆炸。
func _draw_echo_seed() -> void:
	if small_burst or _echo_delay <= 0.0 or _elapsed < 0.24 or _elapsed >= _echo_delay:
		return
	var progress: float = inverse_lerp(0.24, _echo_delay, _elapsed) # 随真实追爆延迟收束亮芯。
	var size: Vector2 = Vector2(90.0, 65.0) * lerpf(1.0, 0.45, progress) # 更小、更亮，形成第二次起爆前的停顿。
	draw_texture_rect(GLOW_TEXTURE, Rect2(-size * 0.5, size), false, Color(1.0, 0.30, 0.04, 0.45 + progress * 0.4))
