## 没入绝望的移动红光和触地散晕。两段都复用教堂的红光遮罩及真实投影。
extends RefCounted

## 正式光场与光束前沿供本组件消费。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 光带与发光点共享已经采样的实际世界坐标。
const Ribbon = preload("res://scripts/fx/savior_despair_meteor_mesh.gd")
## 临地和触地起始的名义半径，单位为格距。
const CONTACT_RADIUS := 1.34
## 触地红晕回收到原有黑暗的战斗秒数。
const DURATION := 0.74

## 池中的垂足在真实战场内，脱离灯光登记后仍可复用。
var _anchors: Array[Marker2D] = []
## 正在空中或正在散开的原光源编号。
var _slots := PackedInt32Array()
## 真实棋盘格距。
var _span: float
## 按光束顺序排列的落点。
var _points := PackedVector2Array()
## 触地时的实际受击范围。
var _areas: Array[Rect2] = []
## 吸收路灯花的脚点和玻璃，未吸收时为 Vector2.INF。
var _feet := PackedVector2Array()
## 和脚点同帧保留，灯在命中时死亡也可以收束。
var _glass := PackedVector2Array()
## 负数时还在空中或已经回收。
var age := -1.0
## 光场使用的世界画布。
var _world: Node2D
## 暖灯、原红灯及地面投影都由该节点处理。
var _field: LightField

## [param world] 为战场，[param field] 为它的低分辨率光场。
func configure(world: Node2D, field: LightField) -> void:
	_world = world
	_field = field

## [param points] 和 [param span] 由权威落点提供。池仅在容量不足时创建节点。
func begin(points: PackedVector2Array, span: float) -> void:
	if not is_instance_valid(_field):
		return
	_span = span
	_points = points
	while _anchors.size() < points.size():
		var anchor := Marker2D.new() # 同一束从上方到触地只占用一个登记项。
		_world.add_child(anchor)
		_anchors.append(anchor)
	for index: int in range(points.size()): # 实际强度随后随前沿和高度提交。
		var anchor: Marker2D = _anchors[index] # 作为红灯原点与投影地面垂足。
		_slots.append(index)
		_field.register_light(anchor, LightField.Tone.RED, _span * CONTACT_RADIUS, Vector2.ZERO,
			anchor, _span, _span * 0.18, 0.0, false, true)

## 用 [param ribbon] 已经下移的前沿照亮实际砖面。[param progress] 由战斗钟给出。
func update_fall(ribbon: Ribbon, progress: float) -> void:
	for index: int in _slots: # 每束的微小横移同样传给影子。
		var front: Vector2 = ribbon.front(index) # 显示用的世界发光位置，无镜头偏移。
		var foot := Vector2(front.x, _points[index].y) # 把发光点垂直投到该行底面。
		var elevation: float = maxf(0.0, foot.y - front.y) # 此帧离真实落点的高度。
		var height_in_cells: float = elevation / _span # 各种棋盘按同一比例调光。
		var distant: float = smoothstep(0.0, 4.65, height_in_cells) # 高处宽而弱，近地收亮。
		var radius: float = _span * lerpf(CONTACT_RADIUS, 4.18, distant) # 临地自然接到红晕的初始宽度。
		var power: float = smoothstep(0.025, 0.23, progress) * lerpf(1.0, 0.31, distant) # 抬掌、压降与暖色恢复共用的能量包络。
		_set_light(index, foot, front, radius, _span * 0.96 + elevation * 0.63, power)

## 从已命中的原光源编号 [param hits]、[param areas]、[param feet] 和 [param glass] 接续散晕。
func impact(hits: PackedInt32Array, areas: Array[Rect2], feet: PackedVector2Array, glass: PackedVector2Array) -> void:
	age = 0.0 # 公用尾迹在常亮战场也会依时收回。
	if not is_instance_valid(_field):
		return
	for index: int in _slots: # 飞行时已撤销的格子没有触地红晕。
		if not hits.has(index):
			_field.unregister_light(_anchors[index].get_instance_id())
	_slots = hits
	_areas = areas
	_feet = feet
	_glass = glass

## 推进触地后的 [param delta] 战斗秒。落下、散开和复熄共用同一组红灯。
func advance(delta: float) -> void:
	if age < 0.0:
		return
	age += delta
	if age >= DURATION:
		clear()
		return
	if not is_instance_valid(_field):
		return
	var wave: float = 1.0 - pow(1.0 - clampf(age / 0.29, 0.0, 1.0), 2.45) # 真正撞地后先快速散开。
	var spread: float = 0.88 * wave + 0.12 * smoothstep(0.11, 0.71, age) # 外沿退光时仍缓慢向外移。
	var impact_power: float = 1.0 - smoothstep(0.046, 0.43, age) # 主反光比边缘残光更早收掉。
	var lingering_power: float = 1.0 - smoothstep(0.17, DURATION, age) # 石砖在最后一段才回到全黑。
	var power: float = lerpf(impact_power, lingering_power, 0.22) * lerpf(1.0, 0.86, spread) # 合成同一盏灯的亮度。
	for hit: int in range(_slots.size()): # 避让叠区的工作由原灯光遮罩的有界混合完成。
		var index: int = _slots[hit] # 与空中使用同一个光源和投影身份。
		var point: Vector2 = _points[index] # 仍是碰撞提交的格心。
		var area: Rect2 = _areas[hit] # 包含真实边格裁切。
		if _glass[hit].is_finite():
			_capture_lamp(hit, point, area, spread, power)
			continue
		var extent: Vector2 = (point - area.position).max(area.end - point) # 格心至最远角，兼容裁过的边格。
		var radius: float = lerpf(_span * CONTACT_RADIUS, extent.length() * 1.30, spread) # 从光柱接到 3×3，边格处逐渐融进暗处。
		_set_light(index, point, point, radius, _span * lerpf(0.96, 0.72, spread), power, area, spread)

## 撤销所有临时红光并保留可重用的世界垂足。
func clear() -> void:
	if is_instance_valid(_field):
		for index: int in _slots: # 同步撤销以覆盖失败演出与亡语引发的退场。
			if is_instance_valid(_anchors[index]):
				_field.unregister_light(_anchors[index].get_instance_id())
	_slots = PackedInt32Array()
	_points = PackedVector2Array()
	_areas = []
	_feet = PackedVector2Array()
	_glass = PackedVector2Array()
	age = -1.0

## 整条轨道销毁时归还世界锚点，首轨普通收尾只调用 [method clear]。
func dispose() -> void:
	clear()
	for anchor: Marker2D in _anchors: # 退还池中仍挂在战场根节点下的所有垂足。
		if is_instance_valid(anchor):
			anchor.queue_free()
	_anchors.clear()

## 第 [param hit] 个有效命中的红晕从 [param point] 沿 [param area] 收进既有灯罩。
## [param spread] 与 [param power] 为当前扩散率和原入射能量。
func _capture_lamp(hit: int, point: Vector2, area: Rect2, spread: float, power: float) -> void:
	var capture: float = smoothstep(0.016, 0.31, age) # 先短促展开，再有方向地收紧。
	var glass: Vector2 = _glass[hit] # 等到灯被击毁也沿用同一个世界坐标。
	var center: Vector2 = point.lerp(glass, capture) + Vector2.UP * (_span * 0.21 * sin(PI * capture)) # 吸收在后半段抬向灯罩。
	var foot: Vector2 = point.lerp(_feet[hit], capture) # 投影仍落在地面而不是灯罩上。
	var radius: float = _span * lerpf(CONTACT_RADIUS * 0.89 + 0.28 * spread, 0.53, capture) # 灯旁的红芒最窄。
	var strength: float = power * (0.93 - 0.36 * capture) * (1.0 - smoothstep(0.29, 0.55, age)) # 灯罩最后一缕残红逐渐退入暖光。
	_set_light(_slots[hit], foot, center, radius, _span * lerpf(0.96, 1.20, capture), strength,
		area.expand(glass + Vector2.UP * _span * 0.28), 0.0, true)

## 将 [param index] 束的一组位姿传给现有光场。
## [param foot] 是垂足，[param center] 是发光中心，[param radius] 和 [param height] 使用世界单位。
## [param power] 为入射强度。[param area] 控制裁剪，[param spread] 推开亮度，[param absorbing] 表现暖色压低。
func _set_light(index: int, foot: Vector2, center: Vector2, radius: float, height: float, power: float,
		area: Rect2 = Rect2(), spread: float = 0.0, absorbing: bool = false) -> void:
	var anchor: Marker2D = _anchors[index] # 此束的稳定身份，在空中和地面继续参与同一投影选择。
	var id: int = anchor.get_instance_id() # 光场登记索引。
	anchor.global_position = foot
	_field.set_red_light_shape(id, center - foot, radius, height, area, spread, absorbing)
	_field.set_light_intensity(id, LightField.Tone.RED, power)
