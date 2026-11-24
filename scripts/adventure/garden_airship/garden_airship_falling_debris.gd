## 飞艇装饰边缘脱落的碎片。用同一飞行时钟更新，按深度投影到随镜头移动的船底画布。
extends Node2D

## 共享事件定义，阵风时序由本局大气系统负责。
const Atmosphere := preload("res://scripts/adventure/garden_airship/garden_airship_atmosphere.gd")
## 航行状态只标定碎屑横向速度。坠落、深度和回收沿用本池。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 按船框着色器的分段横向拉伸和场景位移采样实际船壳下缘，单位为战场像素。
const HULL_EDGES := [Vector2(424, 717), Vector2(478, 715), Vector2(536, 713),
	Vector2(644, 723), Vector2(708, 710), Vector2(754, 695), Vector2(810, 694)]
## 强下降前半段的脱落相位，紧密的前脉冲后跟两片迟释放碎屑。
const DROP_CUES := [0.24, 0.252, 0.271, 0.293, 0.313, 0.336, 0.355, 0.379, 0.443, 0.545]
## 云缘擦过时的小组脱落相位。
const EDGE_CUES := [0.29, 0.338, 0.40]
## 单局固定的绘制槽位数，从不为某次气流扩容。
const POOL_SIZE: int = 12
## 深处的空气散射色，接近船下透过薄云看到的冷灰蓝。
const FAR_AIR := Color(0.57, 0.68, 0.77)

## 形状及运动数据均按叶片、木屑、暗铁片排序。
enum Kind { LEAF, WOOD, METAL }
## 强风依次扯动轻重不同的饰面碎片。
const DROP_KINDS := [Kind.WOOD, Kind.LEAF, Kind.METAL]
## 特征轮廓的局部顶点，接近船体时宽约十四战场像素。
static var _silhouettes: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(-7, 2), Vector2(-4, -2), Vector2(1, -4), Vector2(7, -2), Vector2(4, 2), Vector2(0, 4)]),
	PackedVector2Array([Vector2(-7, 4), Vector2(-4, -3), Vector2(3, -4), Vector2(7, -2), Vector2(2, 2), Vector2(-2, 4)]),
	PackedVector2Array([Vector2(-6, -2), Vector2(-1, -5), Vector2(6, -2), Vector2(3, 4), Vector2(-3, 3)]),
]
## 各材质的叶脉、木纹与金属折面，和外轮廓一起翻滚。
static var _facets: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(-5, 2), Vector2(4, -2), Vector2(1, 1)]),
	PackedVector2Array([Vector2(-5, 2), Vector2(-3, -2), Vector2(5, -2)]),
	PackedVector2Array([Vector2(-5, -2), Vector2(-1, -4), Vector2(4, -2), Vector2(1, 0)]),
]
## 材质在近景的固有颜色和表面受光色。
const BODY_COLORS := [Color("#546a35"), Color("#855132"), Color("#435562")]
const FACET_COLORS := [Color("#a2ad5d"), Color("#c29161"), Color("#91a7ac")]
## 各材质的模拟落体加速度，单位为投影前的像素每秒平方。
const GRAVITIES := Vector3(59.0, 116.0, 162.0)
## 各材质横向速度被气流带动的速率，单位为每秒。
const DRAGS := Vector3(2.60, 1.22, 0.65)
## 各材质的存活秒数基值，重片下降更快。
const LIFETIMES := Vector3(2.24, 1.91, 1.63)

## 固定槽位由一个普通绘制节点和它的亮面组成；场景离开时整体释放。
class Fragment extends Polygon2D:
	## 小折面或纹理，用独立颜色跟随轮廓的透视和翻转。
	var facet := Polygon2D.new()
	## 脱落位置，使用船框所在的战场坐标。
	var origin := Vector2.ZERO
	## 飞离边缘时的局部初速度，用投影前的像素每秒表示。
	var initial_speed := Vector2.ZERO
	## 出生时的目标风速，横向阻力使速度逐步接近它。
	var air_speed: float = 0.0
	## 飞行时钟记录的出生时刻，单位为秒。
	var born: float = 0.0
	## 本片在深处完全不可见的年龄，单位为秒。
	var lifetime: float = 1.0
	## 从本局已释放数派生的稳定变体，范围是 0 到 1。
	var variant: float = 0.0
	## 碎片的材质索引。
	var kind: int = Kind.LEAF

	## 一个槽位只在局内创建一次，发射时重新指定材质和位姿。
	func _init() -> void:
		add_child(facet)
		hide()

## 本局的固定碎片池，各节点只在有效飞行步上重设位姿。
var _pool: Array[Fragment] = []
## 发射序号也决定槽位和碎片变体，全局随机源不参与。
var _release_count: int = 0
## 真实爆炸的小碎片只占普通落物池短时间内的一小部分。
var _last_combat_release: float = -1.0
## 上一次采样的飞行时钟，用于检测局内重置。
var _previous_flight: float = 0.0
## 上一次采样的交战时钟，用于定位两帧之间的释放时刻。
var _previous_battle: float = 0.0
## 上一次采样的事件，用于识别新一轮气流。
var _previous_event: int = Atmosphere.Event.CRUISE
## 上一次采样的事件归一化时间；跳帧时也能跨过多个释放点。
var _previous_phase: float = 0.0

## 固定预建所有可复用的绘制节点。
func _ready() -> void:
	for slot: int in POOL_SIZE: # 每个槽位对应一个可独立翻滚的轮廓。
		var fragment := Fragment.new() # 复用外形、折面与变换。
		add_child(fragment)
		_pool.append(fragment)

## [param seconds] 为共用的飞行时间，[param battle_seconds] 仅在交战或事件收尾期间推进。
## [param atmosphere] 提供当前事件相位与时长，[param wind] 决定脱落处的续吹速度。
## [param motion] 为兼容渲染选项的动效权重，[param reduced] 为低画质档。暂停时保持现有位姿。
func apply_flight(seconds: float, battle_seconds: float, atmosphere: Atmosphere,
		wind: Wind, motion: float, reduced: bool) -> void:
	if seconds < _previous_flight or battle_seconds < _previous_battle:
		_reset()
	var event_kind: int = atmosphere.event_kind # 与导演使用同一事件身份。
	var phase: float = atmosphere.phase # 已经过的归一化有效时刻。
	if battle_seconds > _previous_battle:
		var sparse: bool = reduced or motion < 0.45 # 低画质与现有特效选项减少同时出现的轮廓。
		match event_kind:
			Atmosphere.Event.CRUISE:
				var interval: float = 10.9 if sparse else 6.7 # 平流中每隔若干秒仅一片叶子。
				var release_at: float = 2.6 + floorf((battle_seconds - 2.6) / interval) * interval # 只补最近一次巡航吹落。
				if release_at > _previous_battle:
					_release(seconds - battle_seconds + release_at, wind, Kind.LEAF)
			Atmosphere.Event.DOWNDRAFT:
				_release_cues(DROP_CUES, seconds, atmosphere, wind, sparse)
			Atmosphere.Event.CLOUD_EDGE:
				if not sparse:
					_release_cues(EDGE_CUES, seconds, atmosphere, wind, sparse)
	for fragment: Fragment in _pool: # 隐藏槽位没有可更新的碎片。
		if fragment.visible:
			_project(fragment, seconds - fragment.born, motion)
	_previous_flight = seconds
	_previous_battle = battle_seconds
	_previous_event = event_kind
	_previous_phase = phase

## 在 [param atmosphere] 的 [param cues] 中拾取经过的释放点，将出生时刻还原到 [param seconds] 所在的时钟。
## [param wind] 决定初速度，[param sparse] 仅保留下降组中每四片的一片。
func _release_cues(cues: Array, seconds: float, atmosphere: Atmosphere, wind: Wind, sparse: bool) -> void:
	var phase: float = atmosphere.phase # 直接从事件的有效时钟回推，跨入事件的长帧也不会过早脱落。
	var event_kind: int = atmosphere.event_kind # 用事件类型区分材质组合与上一帧相位。
	var earlier: float = _previous_phase if event_kind == _previous_event and phase >= _previous_phase else 0.0 # 新气流事件从相位零开始。
	for index: int in cues.size(): # 同一释放点只在跨过它的那一帧处理。
		var cue: float = cues[index] # 当前事件内的释放相位。
		if cue <= earlier or cue > phase or (sparse and index % 4 != 0):
			continue
		var delay: float = (phase - cue) * atmosphere.duration_seconds # 保留相应释放点到当前相位的真实时差。
		var kind: int = DROP_KINDS[index % DROP_KINDS.size()] # 阵风中的轻重碎屑交错。
		if event_kind == Atmosphere.Event.CLOUD_EDGE:
			kind = Kind.WOOD if index == 1 else Kind.LEAF
		_release(seconds - delay, wind, kind)

## 把 [param at] 处可见爆炸的一片小碎屑交给原飞行时钟 [param seconds] 和当前 [param wind]。
func release_combat(at: Vector2, seconds: float, wind: Wind) -> void:
	if _pool.is_empty() or not at.is_finite() or seconds - _last_combat_release < 0.28:
		return
	for slot: int in range(_pool.size() - 1, -1, -1): # 战斗余片只借空槽，优先保留已有船腹落物。
		if not _pool[slot].visible:
			_last_combat_release = seconds
			_release(seconds, wind, Kind.METAL, at, slot)
			return

## 释放一片 [param kind]，出生于 [param born]，初始气流来自 [param wind]。
## [param at] 和 [param slot] 指定战斗余片的爆心及空槽，默认使用原机腹饰边。
func _release(born: float, wind: Wind, kind: int, at: Vector2 = Vector2.INF, slot: int = -1) -> void:
	var hull: bool = slot < 0 # 战斗余片不推进原有船腹饰边序号。
	var fragment: Fragment = _pool[_release_count % POOL_SIZE if hull else slot] # 环境落物保留自己的固定轮换。
	var variant: float = fposmod((_release_count if hull else born) * 0.618033989, 1.0) # 连续碎片错开尺寸、转动速度与寿命。
	fragment.origin = HULL_EDGES[_release_count * 3 % HULL_EDGES.size()] if hull else at
	fragment.air_speed = lerpf(45.0, 116.0, wind.strength_at(fragment.origin.x, 0.08)) \
		* wind.sample_flow_ratio(fragment.origin.x, 0.08, 0.15) # 出生时确定世界横速，后续解析轨迹连续。
	fragment.initial_speed = Vector2(12.0 + 0.38 * fragment.air_speed + variant * 19.0, 14.0 + kind * 8.0)
	fragment.born = born
	fragment.lifetime = LIFETIMES[kind] * lerpf(0.91, 1.09, variant)
	fragment.variant = variant
	fragment.kind = kind
	fragment.polygon = _silhouettes[kind]
	fragment.facet.polygon = _facets[kind]
	fragment.show()
	if hull:
		_release_count += 1

## 将 [param fragment] 按 [param age] 投影到船底，年龄以秒计。
## [param motion] 仅弱化轮廓可见度；尺度和淡出随深度推进，便于近层云在船底遮住碎片。
func _project(fragment: Fragment, age: float, motion: float) -> void:
	if age >= fragment.lifetime:
		fragment.hide()
		return
	var progress: float = clampf(age / fragment.lifetime, 0.0, 1.0) # 归一化的远离船体进度。
	var depth: float = pow(progress, 1.38) # 加速远离观察面，最终进入船下低云或薄雾所在深度。
	var perspective: float = 1.0 / (1.0 + 1.9 * depth) # 与云带一致，近清晰、远缩小。
	var kind: int = fragment.kind # 同一材质同时决定风阻、重力和颜色。
	var drag: float = DRAGS[kind] # 给定时间内收敛至相对风的速率。
	var x: float = fragment.air_speed * age + (fragment.initial_speed.x - fragment.air_speed) * (1.0 - exp(-drag * age)) / drag # 解析积分避免帧率改变轨迹。
	var y: float = fragment.initial_speed.y * age + 0.5 * GRAVITIES[kind] * age * age # 屏幕坐标的下落为正。
	var spin: float = (6.5 - kind * 1.35) * lerpf(0.74, 1.22, fragment.variant) # 叶片翻得较快，铁片较慢。
	var angle: float = fragment.variant * TAU + age * spin * signf(fragment.variant - 0.45) # 发射变体决定独立旋转方向。
	var flip: float = 0.48 + 0.52 * absf(cos(angle * 1.34)) # 侧面比正面窄，仍留清楚轮廓。
	var haze: float = smoothstep(0.12, 1.0, progress) # 暖色和细节被逐渐混入远层散射色。
	var fade: float = 1.0 - smoothstep(0.46, 1.0, progress) # 仍在视口内部时结束淡出。
	fragment.position = fragment.origin + Vector2(x, y) * perspective
	fragment.rotation = angle
	fragment.scale = Vector2(1.0, flip) * perspective * lerpf(0.84, 1.18, fragment.variant)
	fragment.color = BODY_COLORS[kind].lerp(FAR_AIR, haze)
	fragment.facet.color = FACET_COLORS[kind].lerp(FAR_AIR, haze)
	fragment.modulate.a = fade * lerpf(0.32, 1.0, motion)

## 清除前一段时钟留下的碎片与释放历史。
func _reset() -> void:
	for fragment: Fragment in _pool: # 复用槽位，隐藏旧一局留下的轮廓。
		fragment.hide()
	_release_count = 0
	_last_combat_release = -1.0
	_previous_flight = 0.0
	_previous_battle = 0.0
	_previous_event = Atmosphere.Event.CRUISE
	_previous_phase = 0.0
