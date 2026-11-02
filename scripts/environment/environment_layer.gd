## 两场景共用的少量环境节点容器；只管理效果生命周期及船体美术浮动。
extends Node2D

## 单效果组件，不引入全局服务。
const EFFECT = preload("res://scripts/environment/environment_sprite.gd")
## 集中可调的效果配置路径。
@export_file("*.json") var configuration: String
## 已实例化的有界效果节点。
var effects: Array[AnimatedSprite2D] = []
## 总效果开关。
var enabled := true
## 云是否可以显示；关闭去云背景时必须同步停云。
var clouds_enabled := true
## 可选的原有船体节点。
var ship: Control
## 船体初始位置，用于关闭效果时恢复。
var ship_origin: Vector2
## 船体初始旋转，不改变码头或按钮。
var ship_rotation := 0.0
## 船体浮动本地时钟。
var elapsed := 0.0

## 按数据创建固定数量效果，所有Node2D不参与GUI命中。
func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(configuration)) # 本场景的效果数据。
	if data.get("ship_float", false):
		ship = get_node("../ship") as Control
		ship_origin = ship.position
		ship_rotation = ship.rotation
	for entry: Dictionary in data.effects: # 仅在场景加载时分配节点。
		var effect := EFFECT.new() # 复用同一组件处理各类局部效果。
		effect.name = entry.name
		add_child(effect)
		effect.configure(entry, ship)
		effects.append(effect)
	visibility_changed.connect(_apply_running)
	_apply_running()

## [param active] 为总FX开关；[param clean_sky] 控制云层是否与去云背景配套。
func set_flags(active: bool, clean_sky: bool) -> void:
	enabled = active
	clouds_enabled = clean_sky
	_apply_running()

## 隐藏、关闭与场景卸载不会留下独立Timer、Tween或烟团队列。
func _apply_running() -> void:
	var running := enabled and is_visible_in_tree() # 继承场景可见性。
	set_process(running)
	for effect in effects: # 云开关只影响云，其他效果仍可独立使用。
		effect.set_running(running and (clouds_enabled or not effect.settings.get("cloud", false)))
	if not running and is_instance_valid(ship):
		elapsed = 0.0
		ship.position = ship_origin
		ship.rotation = ship_rotation

## [param delta] 为秒；只动船体美术及烟囱随动点，交互牌、码头和海岸不动。
func _process(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	elapsed += delta
	ship.position = ship_origin + Vector2(0, 4.5 * sin(elapsed * TAU / 7.5))
	ship.rotation = ship_rotation + deg_to_rad(0.25) * sin(elapsed * TAU / 8.0)
