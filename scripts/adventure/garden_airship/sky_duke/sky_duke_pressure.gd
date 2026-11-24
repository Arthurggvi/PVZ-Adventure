## 单一战斗画布上的公爵气压几何。只在有效演出期间持有固定槽位。
extends Node2D

## 各种爆压的扇面、线条、余烬共用一个纯绘制器。
const Geometry := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_pressure_geometry.gd")
## 技能和转阶段在同帧时仍有各自的局部形状，超过预算先回收装饰。
const MAX_BURSTS := 4

## 与发令时间共享的时钟，单位为战斗秒。
var _seconds: float = 0.0
## 局内风在此帧的世界速度，单位为像素每秒。
var _wind := Vector2.ZERO
## 可复用的爆压槽位，常驻无节点或材质分配。
var _bursts: Array[Geometry.Burst] = []


## 坐标保持在正式战场画布。真导弹和预警仍保留自身排序。
func _ready() -> void:
	z_index = 260
	for index: int in MAX_BURSTS: # 只在本局首次启用公爵演出时分配。
		_bursts.append(Geometry.Burst.new())


## 在 [param origin] 按 [param axis] 绘制 [param kind]，只返回美术槽位是否可用。
## [param phase] 控制颜料，[param born] 为战斗秒，[param seed_value] 使笔触可重现。
## [param power] 为 0 至 1 的强度，[param reduced] 控制装饰密度。
func start(kind: StringName, phase: int, origin: Vector2, axis: Vector2, born: float,
		seed_value: int, power: float, reduced: bool) -> bool:
	var slot: Geometry.Burst = _find_slot(kind) # 优先使用空槽，保留已发生的关键波。
	if slot == null:
		return false
	slot.kind = kind
	slot.origin = origin
	slot.axis = axis.normalized()
	slot.born = born
	slot.duration = 0.84 if kind == &"teleport_out" else (0.77 if kind == &"pressure" else 1.12)
	slot.light = Color("ffd9df") if phase >= 2 else Color("dbf8ff")
	slot.edge = Color("ac233e") if phase >= 2 else Color("32658d")
	slot.variation = float(posmod(seed_value, 997)) * 0.17
	slot.power = clampf(power, 0.0, 1.0)
	slot.sparks = (28 if phase >= 2 else 12) if not reduced else (15 if phase >= 2 else 7)
	queue_redraw()
	return true


## [param seconds] 和 [param wind_world] 用于解析采样。过期槽立即释放。
func update_frame(seconds: float, wind_world: Vector2) -> void:
	_seconds = seconds
	_wind = wind_world
	for slot: Geometry.Burst in _bursts: # 只迭代固定四个槽。
		if seconds - slot.born >= slot.duration:
			slot.born = INF
	queue_redraw()


## 返回仍保留的可见爆压数量，供关卡回收和验收采样。
func active_count() -> int:
	var count := 0 # 空闲槽不计入当前爆压预算。
	for slot: Geometry.Burst in _bursts: # 只读阶段内的槽位占用。
		count += int(is_finite(slot.born))
	return count


## 清理丢弃还在场上的所有爆压图形。
func clear() -> void:
	for slot: Geometry.Burst in _bursts: # 重用已预留对象，无需重建池。
		slot.born = INF
	queue_redraw()


## 为 [param kind] 选空闲槽，没有空间时只允许关键效果抢占环境气爆。
func _find_slot(kind: StringName) -> Geometry.Burst:
	var decoration: Geometry.Burst # 尚未消散的环境气爆可让给现场指令。
	for slot: Geometry.Burst in _bursts: # 容量用满时保留已有技能主要尾迹。
		if not is_finite(slot.born) or _seconds - slot.born >= slot.duration:
			return slot
		if slot.kind == &"pressure":
			decoration = slot
	return decoration if kind != &"pressure" else null


## 从原世界锚点绘制脱离的余波，不跟随人物或传送中的透明帧。
func _draw() -> void:
	for slot: Geometry.Burst in _bursts: # 待启和空闲槽都不写入绘制命令。
		var age: float = _seconds - slot.born # 真实跳过过期时点，无补发闪光。
		if age < 0.0 or age >= slot.duration:
			continue
		Geometry.draw_burst(self, to_local(slot.origin), slot, age, _wind)
