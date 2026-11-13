## 双发射手的持续场纯视觉接口；辉夜24核与地狱吸取不受视觉降级影响。
extends Node2D
class_name RepeaterFieldVisual

## 当前持续场种类：辉夜或地狱，不共享易变材质。
var _kind: StringName
## 同一战斗场传入的可暂停秒数。
var _age: float = 0.0
## 父级决定场的总寿命。
var _lifetime: float = 3.0
## 当前地形的真实格距。
var _pitch: Vector2
## 独立星核几何和GPU星云；视觉质量只影响其绘制循环。
var _galaxy: RepeaterGalaxyVisual
## 只有一层材质与少量吸入余烬的黑洞。
var _abyss: RepeaterAbyssVisual
## 本次上次实际送给GPU的年龄，用于限速视觉更新。
var _last_visual_age: float = -1.0
## 是否已把该场登记到统一视觉预算。
var _registered: bool = false

## [param seed] 是局部视觉随机数；[param pitch] 不会覆盖当前棋盘的物理几何。
func configure(kind: StringName, seed: int, pitch: Vector2, lifetime: float) -> void:
	_kind = kind
	_pitch = Vector2(maxf(1.0, absf(pitch.x)), maxf(1.0, absf(pitch.y)))
	_lifetime = maxf(0.01, lifetime)
	if kind == &"kaguya":
		_galaxy = RepeaterGalaxyVisual.new()
		add_child(_galaxy)
		_galaxy.configure(seed, _pitch, _lifetime)
	elif kind == &"hell":
		_abyss = RepeaterAbyssVisual.new()
		add_child(_abyss)
		_abyss.configure(_pitch, _lifetime)
	if not _registered:
		RepeaterVisualBudget.enter(&"galaxy" if kind == &"kaguya" else &"vortex")
		_registered = true
	set_age(0.0)

## 场离开树时同时退还视觉预算，不需要周期性扫描死节点。
func _exit_tree() -> void:
	if _registered:
		RepeaterVisualBudget.leave(&"galaxy" if _kind == &"kaguya" else &"vortex")
		_registered = false

## 父场每帧传入一个视觉年龄；高负载自动限制昂贵绘制更新频率。
func set_age(seconds: float) -> void:
	var next_age: float = clampf(seconds, 0.0, _lifetime)
	if _last_visual_age >= 0.0 and next_age < _lifetime \
			and next_age - _last_visual_age < RepeaterVisualBudget.interval():
		return
	_age = next_age
	_last_visual_age = _age
	visible = _age < _lifetime
	if is_instance_valid(_galaxy):
		_galaxy.set_age(_age)
	if is_instance_valid(_abyss):
		_abyss.set_age(_age)

## 物理持续场随时可取24枚准确星核位置；不调用_redraw或Shader。
func get_fragment_positions_at(seconds: float) -> PackedVector2Array:
	if not is_instance_valid(_galaxy):
		return PackedVector2Array()
	return _galaxy.positions_at(seconds)

## 视觉预算只减画面点数，触碰半径仍固定为五像素。
func get_fragment_radius() -> float:
	return RepeaterGalaxyVisual.TOUCH_RADIUS
