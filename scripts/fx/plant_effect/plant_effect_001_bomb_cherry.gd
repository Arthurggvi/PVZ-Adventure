extends BombEffectBase
class_name BombEffectCherryBomb

## 原版 POWIE 的烟团纹理，两层共用。
const CLOUD_TEXTURE := preload("res://assets/image/particles/ExplosionCloud.png")
## 原版粒子参数按 100 Hz 推进。
const TICKS_PER_SECOND := 100.0
## 每层以每秒 150 颗的速度发射，达到上限后停止。
const CLOUDS_PER_SECOND := 150.0
## 单层烟团发射上限。
const CLOUD_LIMIT := 14
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

## 只在爆炸后驱动粒子。
func _ready() -> void:
	set_process(false)

## 在爆心播放两层烟团、POWIE 字样和原版幅度的短震。
func activate_bomb_effect() -> void:
	super()
	_rng.randomize()
	_emit_cloud_pair()
	queue_redraw()
	EventBus.push_event(MainGameCamera.SHAKE_EVENT, [Vector2(3, 4), 0.12])
	set_process(true)

## [param delta] 自上一帧经过的战斗秒数。
func _process(delta: float) -> void:
	_elapsed += delta
	# 第一对烟团在爆炸当帧出现，后续按原版发射节拍追加。
	var target_tick := 1 + floori(_elapsed * TICKS_PER_SECOND)
	while _ticks < target_tick:
		_ticks += 1
		_advance_clouds(_small_clouds, 0.15)
		_advance_clouds(_large_clouds, 0.12)
		# 150 颗/秒在 100 Hz 下交替发射一颗和两颗，直到达到单层上限。
		var expected := mini(CLOUD_LIMIT, floori(_ticks * CLOUDS_PER_SECOND / TICKS_PER_SECOND))
		while _launched < expected:
			_emit_cloud_pair()
	explosive_font.visible = _elapsed < WORD_TICKS / TICKS_PER_SECOND
	queue_redraw()
	if not explosive_font.visible and _small_clouds.is_empty() and _large_clouds.is_empty():
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
	_draw_clouds(_small_clouds, Vector2(0.7, 0.0))
	_draw_clouds(_large_clouds, Vector2(0.9, 0.4))

## [param clouds] 当前烟团层。
## [param green_range] 颜色从初始到寿命结束的绿色分量，红色为 1，蓝色为 0。
func _draw_clouds(clouds: Array[BlastCloud], green_range: Vector2) -> void:
	# 让纹理围绕粒子中心旋转。
	var texture_origin := -CLOUD_TEXTURE.get_size() * 0.5
	for cloud: BlastCloud in clouds:
		# 粒子寿命进度，用来驱动颜色、缩小和淡出。
		var progress := float(cloud.age) / cloud.lifetime
		# 原版保持初始大小至寿命的 60%，随后缩小。
		var cloud_scale := cloud.initial_scale * clampf(inverse_lerp(1.0, 0.6, progress), 0.0, 1.0)
		# 原版保持全不透明至寿命的 70%，随后淡出。
		var alpha := clampf(inverse_lerp(1.0, 0.7, progress), 0.0, 1.0)
		draw_set_transform(cloud.position, cloud.angle, Vector2.ONE * cloud_scale)
		draw_texture(CLOUD_TEXTURE, texture_origin, Color(1.0, lerpf(green_range.x, green_range.y, progress), 0.0, alpha))
