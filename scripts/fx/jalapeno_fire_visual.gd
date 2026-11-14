## 火爆辣椒专用火浪；保留原始火焰逐帧姿态，仅负责表现，不参与伤害结算。
extends Node2D
class_name JalapenoFireVisual

## 原始 fire.reanim 的三帧燃烧与九帧上升熄灭，包含导入场景曾遗漏的中间帧。
const FRAMES: Array[Texture2D] = [
	preload("res://assets/reanim/fire1.png"), preload("res://assets/reanim/fire2.png"),
	preload("res://assets/reanim/fire3.png"), preload("res://assets/reanim/fire4.png"),
	preload("res://assets/reanim/fire4b.png"), preload("res://assets/reanim/fire5.png"),
	preload("res://assets/reanim/fire5b.png"), preload("res://assets/reanim/fire6.png"),
	preload("res://assets/reanim/fire6b.png"), preload("res://assets/reanim/fire7.png"),
	preload("res://assets/reanim/fire7b.png"), preload("res://assets/reanim/fire8.png")]
## 原始熄灭帧的左上角位置；基线与原场景 Body 的 -101 像素偏移一致。
const DONE_OFFSETS: Array[Vector2] = [Vector2(-41.8, -74.6), Vector2(-43.9, -78.1),
	Vector2(-41.5, -86.9), Vector2(-42.0, -94.9), Vector2(-44.6, -104.4),
	Vector2(-43.9, -115.6), Vector2(-44.0, -130.1), Vector2(-45.7, -131.3), Vector2(-44.4, -140.5)]
## 主火保持约一秒，随后完整播放原版十二帧每秒的退火。
const MAIN_HOLD: float = 0.9
## 地火先让主爆露出轮廓，再在原有五秒伤害时限内持续燃烧。
const GROUND_APPEAR: float = 0.56
## 原版退火阶段的时长，单位为战斗秒。
const DONE_DURATION: float = 0.75

## 该火焰是否属于由爆炸控制器回收的持续地火。
var is_ground: bool = false
## 由引爆中心向外传递的纯美术延迟，最多 0.12 秒，不延迟伤害。
var wave_delay: float = 0.0
## 当前地块的宽度，控制横向衔接，保持原火舌高度。
var cell_width: float = 80.0
## 列与行形成的固定相位，让相邻火舌不会整齐复制。
var variation: float = 0.0
## 当前表现时间；普通战斗暂停随场景树暂停。
var _elapsed: float = 0.0
## 美术预览冻结开关；固定取样不会改变任何战斗状态。
var _preview_frozen: bool = false

## 在 [param cell] 的地面创建火焰。[param origin_column] 是引爆列；[param ground] 选择持续地火。
## 返回由调用方持有的表现节点；主火自行结束，地火必须由原伤害控制器回收。
static func spawn_cell(cell: PlantCell, origin_column: int, ground: bool = false) -> JalapenoFireVisual:
	var flame := JalapenoFireVisual.new() # 每格持有自己的表现，跟随移动平台而不移交给 bombs。
	flame.is_ground = ground
	flame.cell_width = cell.size.x
	flame.variation = float(cell.row_col.y * 7 + cell.row_col.x * 3)
	flame.wave_delay = minf(0.12, absf(float(cell.row_col.y - origin_column)) * 0.018)
	flame.z_index = cell.row_col.x * 50 + 40
	flame.z_as_relative = false
	cell.add_child(flame)
	flame.position = Vector2(cell.size.x * 0.5, cell.size.y)
	return flame

## 在预览容器 [param parent] 内按 [param point] 创建同一套真实表现；不需要正式战场。
## [param elapsed] 为固定取样秒数，[param ground] 选择残火，[param width] 为格宽。
## [param phase] 控制相邻火舌差异，供画廊复现连续整行；返回可再次取样的节点。
static func preview(parent: Node, point: Vector2, elapsed: float, ground: bool = false,
		width: float = 80.0, phase: float = 0.0) -> JalapenoFireVisual:
	var flame := JalapenoFireVisual.new() # 预览与正式运行共用绘制路径。
	flame.is_ground = ground
	flame.cell_width = width
	flame.variation = phase
	flame.position = point
	parent.add_child(flame)
	flame.set_preview_time(elapsed)
	return flame

## 把表现冻结在 [param elapsed] 秒，可用于逐帧美术检查；不会发送任何游戏事件。
func set_preview_time(elapsed: float) -> void:
	_preview_frozen = true
	_elapsed = maxf(0.0, elapsed)
	queue_redraw()

## [param delta] 为暂停后不再流逝的战斗秒数；主火在完整退火后自行销毁。
func _process(delta: float) -> void:
	if _preview_frozen:
		return
	_elapsed += delta
	if not is_ground and _elapsed >= wave_delay + MAIN_HOLD + DONE_DURATION:
		queue_free()
		return
	queue_redraw()

## 地火与主火使用相同原版贴图，分别强调贴地余焰和连成整行的火舌。
func _draw() -> void:
	var age: float = _elapsed - wave_delay # 视觉火浪只影响绘制，不更改结算时间。
	if age < 0.0:
		return
	if is_ground:
		_draw_ground(age)
	else:
		_draw_main(age)

## 以 [param age] 秒绘制主火、贴地热光与少量上扬火星；保留原始火舌轮廓。
func _draw_main(age: float) -> void:
	var release: float = maxf(0.0, age - MAIN_HOLD) # 只在退火段开始计时。
	if release >= DONE_DURATION:
		return
	var strength: float = 1.0 - smoothstep(0.04, DONE_DURATION, release) # 余光随火舌退去。
	var onset: float = 1.0 + 0.12 * (1.0 - smoothstep(0.0, 0.16, age)) # 点火一瞬略抬高，随后回归原版比例。
	var spread: float = maxf(0.8, cell_width / 100.0) # 原贴图宽 113，保证相邻标准格轻微交叠。
	_draw_heat(strength, false)
	if release == 0.0:
		var frame_index: int = int(floor(age * 12.0 + fmod(variation, 3.0))) % 3 # 恢复 FIRE1、2、3 的顺序循环。
		_draw_frame(frame_index, Vector2(-45.0 * spread / 0.8, -70.8 * onset), Vector2(spread, 0.8 * onset), 1.0)
	else:
		var done_index: int = mini(8, int(floor(release * 12.0))) # 原始九帧上升退火逐张播放。
		var offset: Vector2 = DONE_OFFSETS[done_index] # 保留原版退火移动轨迹。
		offset.x *= spread / 0.8
		_draw_frame(done_index + 3, offset, Vector2(spread, 0.844 if done_index == 0 else 0.8), 1.0 - smoothstep(0.56, 0.75, release))
	_draw_embers(age, strength, false)

## 以 [param age] 秒绘制贴地的疏密三簇残火，避免复制整排缩小的大爆炸。
func _draw_ground(age: float) -> void:
	if age < GROUND_APPEAR:
		return
	var strength: float = smoothstep(GROUND_APPEAR, GROUND_APPEAR + 0.28, age) # 主爆转余火时柔和显现。
	strength *= 1.0 - smoothstep(4.65, 5.0, _elapsed)
	_draw_heat(strength, true)
	for cluster: int in range(3): # 三簇火苗高低错落，留出地面和角色脚部的可读空间。
		var seed: float = variation + float(cluster) * 2.13 # 固定相位避免每帧随机闪烁。
		var flicker: float = 0.93 + sin(age * 12.0 + seed) * 0.07 # 仅轻微改变火舌大小。
		var size_factor: float = (0.31 if cluster != 1 else 0.43) * flicker # 中间簇稍高，侧簇低矮。
		var center: Vector2 = Vector2((float(cluster) - 1.0) * cell_width * 0.28, -1.0) # 火苗根部贴住格子底边。
		var frame_index: int = int(floor(age * 12.0 + seed)) % 3 # 每簇保留完整三帧原火。
		_draw_frame(frame_index, center + Vector2(-56.5, -87.0) * size_factor, Vector2.ONE * size_factor, strength)
	_draw_embers(age, strength, true)

## 绘制 [param index] 帧到 [param point]，按 [param frame_scale] 缩放并使用 [param opacity] 透明度。
func _draw_frame(index: int, point: Vector2, frame_scale: Vector2, opacity: float) -> void:
	var texture: Texture2D = FRAMES[index] # 原版资源保持不变，不对角色或全场套用滤色。
	draw_texture_rect(texture, Rect2(point, texture.get_size() * frame_scale), false, Color(1.0, 1.0, 1.0, opacity))

## [param strength] 为当前亮度包络；[param ground] 缩窄地火，热光只铺在脚下。
func _draw_heat(strength: float, ground: bool) -> void:
	var half_width: float = cell_width * 0.55 # 轻微重叠形成连续火线，不显示格子边界。
	var height: float = 6.0 if ground else 10.0 # 地火保持更低的光照带。
	for layer: int in range(3, 0, -1): # 三层透明椭圆将亮芯自然融进地面。
		var radius: float = float(layer) / 3.0 # 外圈更宽更淡。
		draw_set_transform(Vector2(0.0, -2.5), 0.0, Vector2(half_width * radius, height * radius))
		draw_circle(Vector2.ZERO, 1.0, Color(1.0, 0.32 + 0.12 * float(3 - layer), 0.025, strength * (0.07 if ground else 0.1)))
	draw_set_transform(Vector2.ZERO)

## 按 [param age] 绘制少量火星；[param strength] 控制退场，[param ground] 降低高度与数量。
func _draw_embers(age: float, strength: float, ground: bool) -> void:
	var count: int = 3 if ground else 5 # 每格严格限制数量，三行晋升时仍保持轮廓清楚。
	for spark: int in range(count): # 固定分布随时间上升，避免随机抖动。
		var seed: float = float(spark) * 1.71 + variation * 0.41 # 角色之外的纯视觉相位。
		var cycle: float = fposmod(age * (0.8 if ground else 1.35) + seed, 1.0) # 每颗火星的归一化生命。
		var point: Vector2 = Vector2(sin(seed * 3.7) * cell_width * 0.42 + sin(cycle * 5.0 + seed) * 5.0,
			-8.0 - cycle * (42.0 if ground else 104.0)) # 主爆火星略高于火舌，余火更收敛。
		var opacity: float = strength * sin(cycle * PI) * (0.65 if ground else 0.9) # 出生和消亡均无突跳。
		draw_line(point, point + Vector2(-1.2, 3.8), Color(1.0, 0.68, 0.14, opacity), 1.5, true)
