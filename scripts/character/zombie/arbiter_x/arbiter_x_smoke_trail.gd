## 双喷口沿实际路程连续排烟。粒子出生后使用世界坐标，不随飞机转弯。
extends Node2D
class_name ArbiterXSmokeTrail

## 只在当前战场明确提供风场时为烟团增加随年龄增强的船尾漂移。
const BattleWind := preload("res://scripts/battle/environment/battle_wind_visual.gd")

## 用户提供的八种烟团，按四列两行存放。
const SMOKE_TEXTURE: Texture2D = preload("res://assets/adventure/zombies/arbiter_x/smoke_atlas.png")
## 烟团在图集中的单格大小，单位为纹理像素。
const TILE_SIZE: Vector2 = Vector2(256.0, 256.0)
## 每架飞机同时绘制的烟粒上限；达到时优先留下更新的尾迹。
const MAX_PUFFS: int = 208
## 所有烟粒的最大寿命，包含撞击之后的余烟，单位为秒。
const MAX_LIFETIME: float = 1.60
## 常规帧率下的密集发射速率，单位为每喷口每秒的烟团数。
const MAX_RATE: float = 74.0


## 一个已经离开喷口的烟团。
class Puff:
	## 世界坐标，绘制时再换算到当前节点。
	var center: Vector2
	## 初始世界漂移速度，单位为像素/秒。
	var velocity: Vector2
	## 从起点扩散到此刻的时间，单位为秒。
	var age: float = 0.0
	## 生命时长，单位为秒。
	var life: float
	## 当前角度，单位为弧度。
	var rotation: float
	## 角速度，单位为弧度/秒。
	var spin: float
	## 成熟烟团的尺寸，单位为世界像素。
	var size: float
	## 烟团纹理对应的图集区域。
	var region: Rect2
	## 刚离开喷口时的烟色，扩散后逐渐混入冷灰。
	var tint: Color


## 现存烟团，按生成先后绘制。
var _puffs: Array[Puff] = []
## 远侧和近侧喷口上一拍的世界变换。
var _prior: Array[Transform2D] = []
## 每个喷口尚不足一粒的发射余数。
var _carry: Vector2 = Vector2.ZERO


## 巡航与俯冲主动推进，发射结束后由节点接管最后一段消散。
func _ready() -> void:
	set_process(false)


## 停止主动供烟后，让画面中的旧烟继续更新至清空。
func release() -> void:
	set_process(not _puffs.is_empty())


## [param delta] 推进停止发射后的余烟。
func _process(delta: float) -> void:
	_age_puffs(delta)
	queue_redraw()
	if _puffs.is_empty():
		set_process(false)


## [param delta] 为场景时间，[param far_pose] 与 [param near_pose] 为两个喷口的世界姿态。
## [param load] 的两个分量是对应的排烟强度，零表示只让该侧旧烟自然消散。
func advance(delta: float, far_pose: Transform2D, near_pose: Transform2D, load: Vector2) -> void:
	if _prior.is_empty():
		_prior.assign([far_pose, near_pose])
	if delta <= 0.0:
		return
	var needs_redraw: bool = not _puffs.is_empty() or load != Vector2.ZERO # 旧尾迹清空时也要刷新一帧。
	_age_puffs(delta)
	_sweep(0, far_pose, delta, load.x)
	_sweep(1, near_pose, delta, load.y)
	if needs_redraw:
		queue_redraw()


## [param delta] 推进现有烟团并就地压缩数组，保持从旧到新的绘制次序。
func _age_puffs(delta: float) -> void:
	var field: Node = BattleWind.from_node(self) # 每批取样一次，旧烟团保持世界坐标。
	var aft: Vector2 = field.wind_for_visual(global_position) if field != null else Vector2.ZERO # 原版关卡不附加漂移。
	var alive_count: int = 0 # 下一个未消亡的烟团写入的位置。
	for puff: Puff in _puffs: # 烟团只改变世界坐标，与当前机体无父级关联。
		puff.age += delta
		if puff.age >= puff.life:
			continue
		puff.center += (puff.velocity * exp(-1.55 * puff.age) + Vector2.UP * 20.0 * puff.age
			+ aft * (0.72 * smoothstep(0.0, 0.68, puff.age))) * delta
		puff.rotation += puff.spin * delta
		_puffs[alive_count] = puff
		alive_count += 1
	_puffs.resize(alive_count)


## 沿 [param nozzle] 对应的实际位移插值发射。
## [param current] 是末端变换，[param delta] 为本帧时长，[param density] 为当前发射强度。
func _sweep(nozzle: int, current: Transform2D, delta: float, density: float) -> void:
	var previous: Transform2D = _prior[nozzle] # 便于在连续两次采样之间补齐尾迹。
	_prior[nozzle] = current
	if density <= 0.0:
		_carry[nozzle] = 0.0
		return
	var displacement: Vector2 = current.origin - previous.origin # 此帧喷口经历的实际路程。
	if displacement.length() > maxf(420.0 * delta, 68.0):
		previous = current # 切行或瞬移不在两个不连续的位置之间画出一条烟柱。
		displacement = Vector2.ZERO
	var emission: float = maxf(MAX_RATE * delta, displacement.length() / 4.5) * density # 高速时按距离补采样。
	var remainder: float = _carry[nozzle] # 保留小数发射相位，不因帧率变化断流。
	var batches: int = floori(remainder + emission) # 一般为 0–3，卡顿帧由以下数量限制处理。
	_carry[nozzle] = remainder + emission - batches
	var drift: Vector2 = (displacement / delta).limit_length(340.0) * 0.18 # 烟初速度携带一部分喷口惯性。
	for batch: int in range(mini(batches, 8)): # 沿经过的路径均匀采样，单帧至多补八粒。
		var part: float = (float(batch + 1) - remainder) / emission if batches <= 8 else float(batch + 1) / 8.0
		_append_puff(previous.interpolate_with(current, clampf(part, 0.0, 1.0)), drift, density)
	if _puffs.size() > MAX_PUFFS:
		_puffs = _puffs.slice(_puffs.size() - MAX_PUFFS)


## 从 [param nozzle] 的轴心排出一粒烟；[param drift] 和 [param density] 分别定义惯性和烟量。
func _append_puff(nozzle: Transform2D, drift: Vector2, density: float) -> void:
	var jet: Vector2 = nozzle.x.normalized() # 喷口的局部 +X 朝向，包括转身与俯仰。
	var variation: Vector2 = Vector2(randf_range(4.0, 11.0), randf_range(-4.0, 4.0) * density) # 在口沿附近散开。
	var puff := Puff.new() # 生成后只沿世界方向漂移。
	puff.center = nozzle.origin + jet * variation.x + jet.orthogonal() * variation.y
	puff.velocity = drift + jet * randf_range(23.0, 59.0) + jet.orthogonal() * randf_range(-22.0, 18.0)
	puff.life = randf_range(0.96, MAX_LIFETIME)
	puff.rotation = randf_range(-PI, PI)
	puff.spin = randf_range(-1.45, 1.45)
	puff.size = randf_range(39.0, 81.0) * lerpf(0.58, 1.13, density)
	puff.tint = Color(0.83, 0.78, 0.73, randf_range(0.44, 0.66) * lerpf(0.82, 1.0, density))
	var atlas_x: int = randi_range(0, 3) # 同一流中随机混合不同烟团轮廓。
	var atlas_y: int = randi_range(0, 1) # 对应图集的上行或下行。
	puff.region = Rect2(Vector2(atlas_x, atlas_y) * TILE_SIZE, TILE_SIZE)
	_puffs.append(puff)


## 用世界坐标保持已有尾迹，并按年龄放大、上浮和渐隐。
func _draw() -> void:
	if _puffs.is_empty():
		return
	var to_local_space: Transform2D = global_transform.affine_inverse() # 抵消机体的缩放、旋转与位移。
	for puff: Puff in _puffs: # 大团在后，小团靠近喷口。
		var progress: float = puff.age / puff.life # 归一化后的烟团年龄。
		var edge: float = lerpf(0.30, 1.0, ease(progress, 0.48)) * puff.size # 先快速膨胀，再缓慢扩散。
		var color: Color = puff.tint.lerp(Color(1.15, 1.18, 1.24, puff.tint.a), progress)
		color.a *= 1.0 - smoothstep(0.29, 1.0, progress)
		draw_set_transform_matrix(to_local_space * Transform2D(puff.rotation, puff.center))
		draw_texture_rect_region(SMOKE_TEXTURE, Rect2(Vector2.ONE * -edge * 0.5, Vector2.ONE * edge),
			puff.region, color)
