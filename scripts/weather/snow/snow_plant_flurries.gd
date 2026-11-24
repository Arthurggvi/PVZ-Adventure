## 植物上脱落的短寿命雪粒。用单个画布项统筹预算，沿同一雪风场漂移。
extends Node2D
class_name SnowPlantFlurries

## 一粒脱落的雪在战斗世界中的局部投影。
class Flake:
	## 控制器空间中的位置，单位像素。
	var position: Vector2
	## 控制器空间速度，单位像素/秒。
	var velocity: Vector2
	## 剩余寿命，单位秒。
	var remaining: float
	## 绘制半径，单位像素。
	var radius: float


## 同帧可见的短寿命雪粒，预算为低档 24、高档 72。
var _flakes: Array[Flake] = []
## 本场积雪的独立随机数来源，和战斗投掷及刷怪随机数分离。
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


## 让脱落粉雪位于植物之上，仍受战斗场景与天气控制器生命周期管理。
func _ready() -> void:
	z_index = 31
	_random.randomize()


## 从 [param origin] 的世界位置释放粉雪，沿 [param wind] 的像素/秒速度取向。
## [param high_quality] 控制数量上限，低档仍有可见抖落。
func shed(origin: Vector2, wind: Vector2, high_quality: bool) -> void:
	var limit: int = 72 if high_quality else 24 # 限制全战场并发量。
	var count: int = mini(5 if high_quality else 2, limit - _flakes.size()) # 每次只释放少量附着粉雪。
	var local_origin: Vector2 = to_local(origin) # 保留原始脱离坐标，后续不追随移动植物。
	for index: int in range(count): # 当前抖落内的独立雪粒。
		var flake: Flake = Flake.new() # 只在预算内生成短寿命数据。
		flake.position = local_origin + Vector2(_random.randf_range(-4.0, 4.0), _random.randf_range(-2.0, 2.0))
		flake.velocity = wind * 0.28 + Vector2(_random.randf_range(-19.0, 19.0), _random.randf_range(-31.0, 4.0))
		flake.remaining = _random.randf_range(0.30, 0.56)
		flake.radius = _random.randf_range(0.85, 1.55)
		_flakes.append(flake)
	if count > 0:
		queue_redraw()


## 按 [param delta] 的游戏秒数推进脱落粒子；[param wind] 为同场风速（像素/秒）。
## [param high_quality] 从高档转低档时立即收紧粒子上限。
func advance(delta: float, wind: Vector2, high_quality: bool) -> void:
	if _flakes.is_empty():
		return
	if not high_quality and _flakes.size() > 24:
		_flakes.resize(24)
	for index: int in range(_flakes.size() - 1, -1, -1): # 从后向前更新，原位移除已消散雪粒。
		var flake: Flake = _flakes[index] # 当前短寿命实例。
		flake.remaining -= delta
		if flake.remaining <= 0.0:
			_flakes.remove_at(index)
			continue
		flake.velocity.x = move_toward(flake.velocity.x, wind.x * 0.36, 90.0 * delta)
		flake.velocity.y += delta * (88.0 + maxf(wind.y, 0.0) * 0.18)
		flake.position += flake.velocity * delta
	queue_redraw()


## 将所有有限雪粒合并绘制为小而无光晕的半透明雪点。
func _draw() -> void:
	for flake: Flake in _flakes: # 当前仍悬浮的雪粒。
		var opacity: float = 0.68 * smoothstep(0.0, 0.24, flake.remaining) # 接近消散时渐隐。
		draw_circle(flake.position, flake.radius, Color(0.82, 0.90, 0.94, opacity), true, -1.0, true)
