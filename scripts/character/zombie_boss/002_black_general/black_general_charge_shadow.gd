## 二阶段转场的分路冲锋残影，只扫掠施加劣化。
extends Node2D
class_name BlackGeneralChargeShadow

## 复用 Boss 的纯美术骨架，避免实例化角色生命和碰撞组件。
const VISUAL_SCENE: PackedScene = preload("res://scenes/character/zombie_boss/black_general_visual.tscn")
## 影子拖尾的初始透明度，低于本体拖尾。
const TRAIL_OPACITY: float = 0.31
## 分路残影的拖尾淡出秒数，短于本体拖尾。
const TRAIL_LIFETIME: float = 0.84
## 四路分身的定格间隔略宽，给地面火线留出可读空间。
const TRAIL_INTERVAL: float = 0.21

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
## 冲锋者各部件共用的瓦解进度。
var _ink: ShaderMaterial
## 当前正在延伸的地面轨迹。
var _wake: BlackGeneralChargeWake

## 取 [param boss] 的外观比例，在 [param row] 路的 [param origin] 等待 [param delay] 秒后冲锋。
func setup(boss: ZB002BlackGeneral, row: int, origin: Vector2, delay: float) -> void:
	lane = row
	_delay = delay
	top_level = true
	z_as_relative = false
	# 保留每行深度的同时，让外侧黑影与终点火焰始终位于本体后方。
	z_index = mini(row * 50 + 39, boss.z_index - 7)
	hide()
	boss.add_child(self)
	global_position = origin
	_visual = VISUAL_SCENE.instantiate()
	_visual.transform = boss.global_transform.affine_inverse() * boss.visual.global_transform
	_visual.modulate = Color(0.96, 0.90, 1.0, 0.86)
	add_child(_visual)
	_visual.set_phase2(true)
	_ink = BlackGeneralChargeTrail.make_ink(1.05, origin.x + row * 31.0)
	for sprite: Sprite2D in _visual.find_children("*", "Sprite2D", true, false): # 骨架各部件沿同一噪声场破碎。
		sprite.material = _ink
		if sprite.name == &"Cape" or String(sprite.name).begins_with("HeldFlag"):
			sprite.self_modulate.a = 0.48
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
		BlackGeneralChargeTrail.spawn(_visual, boss, z_index - 1, TRAIL_OPACITY, TRAIL_LIFETIME)
		_trail_wait += TRAIL_INTERVAL
	var feet: Vector2 = global_position # 轨迹的右端从首次真正移动的位置起算。
	var finished: bool = _charge.advance(boss, cells, movement_step, self) # 本帧是否到达停止线。
	if global_position.x < feet.x:
		if _wake == null:
			_wake = BlackGeneralChargeWake.spawn(boss, feet, z_index - 2, 0.60)
		_wake.follow(global_position.x)
	return finished

## 退场由停止线触发。先急停，再让轮廓破碎，轨迹在原地慢慢熄灭。
func finish() -> void:
	if _wake == null:
		queue_free()
		return
	_release_wake()
	_visual.play_action(&"charge_stop")
	BlackGeneralShadowBurst.erupt(self, global_position, z_index + 1, 0.76)
	var decay := create_tween() # 给急停留出一拍，再开始崩解。
	decay.tween_interval(0.12)
	decay.tween_method(BlackGeneralChargeTrail.set_dissolve.bind(_ink), 0.0, 1.0, 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	decay.parallel().tween_property(_visual, "modulate:a", 0.0, 0.37).set_delay(0.30)
	decay.tween_interval(0.36) # 让终点的余焰播完再销毁节点。
	decay.tween_callback(queue_free)

## 战斗被中断时停止影子，已有轨迹继续耗散。
func cancel() -> void:
	_release_wake()
	queue_free()

## 固定尾迹范围并交由其自身淡出。
func _release_wake() -> void:
	if is_instance_valid(_wake):
		_wake.retire(1.06)
		_wake = null
