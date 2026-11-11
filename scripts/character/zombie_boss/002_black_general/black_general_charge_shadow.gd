## 二阶段转场的分路冲锋残影，只扫掠施加劣化。
extends Node2D
class_name BlackGeneralChargeShadow

## 复用 Boss 的纯美术骨架，避免实例化角色生命和碰撞组件。
const VISUAL_SCENE: PackedScene = preload("res://scenes/character/zombie_boss/black_general_visual.tscn")
## 影子拖尾的初始透明度，低于本体拖尾。
const TRAIL_OPACITY: float = 0.26

## 影子所在的零起始行。
var lane: int
## 开始冲锋前的剩余战斗秒数。
var _delay: float
## 距离下次生成拖尾的秒数。
var _trail_wait: float = 0.0
## 影子单独保存扫掠命中记录。
var _charge := BlackGeneralCharge.new()
## 冲锋期间播放的纯视觉角色。
var _visual: BlackGeneralVisual

## 取 [param boss] 的外观比例，在 [param row] 路的 [param origin] 等待 [param delay] 秒后冲锋。
func setup(boss: ZB002BlackGeneral, row: int, origin: Vector2, delay: float) -> void:
	lane = row
	_delay = delay
	top_level = true
	z_as_relative = false
	z_index = row * 50 + 39
	hide()
	boss.add_child(self)
	global_position = origin
	_visual = VISUAL_SCENE.instantiate()
	_visual.transform = boss.global_transform.affine_inverse() * boss.visual.global_transform
	_visual.modulate = Color(0.12, 0.09, 0.14, 0.78)
	add_child(_visual)
	_visual.set_phase2(true)
	_charge.begin(0)

## 用 [param step] 推进等待和移动，扫过 [param cells] 内的植物。
## [param boss] 提供冲锋速度和拖尾的生命周期，返回是否到达本行停止线。
func advance(boss: ZB002BlackGeneral, cells: Array, step: float) -> bool:
	var movement_step: float = step - _delay # 延时结束的当帧只移动剩余时间对应的距离。
	_delay = maxf(0.0, -movement_step)
	if movement_step <= 0.0:
		return false
	if not visible:
		show()
		_visual.play_action(&"charge")
	_trail_wait -= movement_step
	if _trail_wait <= 0.0:
		BlackGeneralChargeTrail.spawn(_visual, boss, z_index - 1, TRAIL_OPACITY)
		_trail_wait += BlackGeneralChargeTrail.INTERVAL
	return _charge.advance(boss, cells, movement_step, self)
