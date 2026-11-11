## 举旗时从脚下升起的黑焰；初始向上集中，末端化为散开的烟缕。
extends Node2D

## 沿用黑将军身上的黑焰动画帧。
const FLAME_FRAMES: SpriteFrames = preload("res://assets/adventure/zombies/black_general/parts/fx/generated/BlackSmoke_Back.tres")
## 烟缕在脚下横向展开的起点，单位像素。
const FOOT_OFFSETS := [0.0, -17.0, 16.0, -31.0, 29.0, 7.0]
## 每缕烟焰起飞前的错峰时间，单位秒。
const WISP_INTERVAL: float = 0.06

## 将黑焰挂到 [param host]，从脚下的世界坐标 [param origin] 升起。
## [param depth] 为绝对绘制层级。
func ignite(host: Node2D, origin: Vector2, depth: int) -> void:
	top_level = true
	z_as_relative = false
	z_index = depth
	host.add_child(self)
	global_position = origin
	for index: int in range(FOOT_OFFSETS.size()): # 中央火柱先起，外侧火团逐步展开。
		_rise(index)
	var cleanup := create_tween() # 等最晚发出的烟缕散尽后释放。
	cleanup.tween_interval(1.55)
	cleanup.tween_callback(queue_free)

## [param index] 决定单缕火焰的起点、大小和飘散方向。
func _rise(index: int) -> void:
	var offset_x: float = FOOT_OFFSETS[index] # 脚边生成位置。
	var wisp := AnimatedSprite2D.new() # 独立播放黑焰帧的烟缕。
	var rise_time: float = 1.50 - index * 0.08 # 中央火柱上升最久。
	var width: float = 0.64 if index == 0 else 0.30 # 外侧火团更细。
	var opacity: float = 0.93 if index == 0 else 0.67 # 保留浓黑的中央火舌。
	var launch_delay: float = index * WISP_INTERVAL # 错开每缕的起飞时刻。
	wisp.sprite_frames = FLAME_FRAMES
	wisp.position = Vector2(offset_x, -22.0)
	wisp.scale = Vector2(width, width * 0.65)
	wisp.modulate = Color(0.76, 0.70, 0.82, 0.0)
	add_child(wisp)
	wisp.play(&"loop")
	wisp.frame = index * 3 % FLAME_FRAMES.get_frame_count(&"loop")
	var drift := wisp.create_tween() # 先从地面涌出，再向上拉长、散开并淡出。
	drift.tween_interval(launch_delay)
	drift.tween_property(wisp, "position", Vector2(offset_x * 2.7 + 18.0, -246.0 + index * 14.0), rise_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.parallel().tween_property(wisp, "scale", Vector2(width * 1.7, width * 2.0), rise_time)
	var fade := wisp.create_tween() # 先亮出火形，升至上方时化开。
	fade.tween_interval(launch_delay)
	fade.tween_property(wisp, "modulate:a", opacity, 0.12)
	fade.tween_property(wisp, "modulate:a", 0.0, rise_time - 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
