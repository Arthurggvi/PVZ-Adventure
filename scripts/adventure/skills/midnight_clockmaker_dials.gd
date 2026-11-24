## 只读施放时钟，在受影响的角色脚下绘制逐渐收回的黄铜表盘。
extends Node2D

## 共用本次效果的战斗时钟。
const Slowdown = preload("res://scripts/adventure/skills/battle_action_slowdown.gd")
## 微暗的底色在积雪、海面和教堂等场地上都给细线提供对比。
const SHADOW := Color(0.10, 0.08, 0.18)
## 表盘的金色刻度。
const BRASS := Color(1.0, 0.79, 0.46)
## 秒针和启动回声的冷色高光。
const HIGHLIGHT := Color(0.75, 0.88, 1.0)

## 随作用范围和持续时长一同撤除的本次施放。
var _clock: Slowdown

## 绑定 [param clock] 所有目标的世界坐标和恢复进度。
func _init(clock: Slowdown) -> void:
	_clock = clock
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 390

## [param _delta] 由行动来源管理效果年龄。这里只跟随每帧最终世界坐标。
func _process(_delta: float) -> void:
	queue_redraw()

## 将两个指针和渐退刻度放在当前脚点。足下环穿过地面时保持透视。
func _draw() -> void:
	var elapsed: float = _clock.elapsed # 从战斗时间读取，暂停与快进保持一致。
	var remaining: float = _clock.remaining_fraction() # 刻度按实际剩余时间收回。
	var echo: float = smoothstep(0.0, 0.48, elapsed) # 起手脉冲扩出并快速退场。
	var strength: float = pow(_clock.slowdown_strength(), 0.75) * 0.74 # 亮度与实际减速和滤镜同步退去。
	var arc_end: float = -PI * 0.5 + TAU * remaining # 从十二点向回退，表盘缺口对应实际剩余时间。
	for target: Character000Base in _clock.targets_for_visual(): # 本次施放的存活快照。
		if not is_instance_valid(target) or target.is_death or target.is_hypno \
				or not target.is_visible_in_tree() or target.is_queued_for_deletion():
			continue
		var radius: float = 31.0 if target is ZB000Base else 14.0 # 大体型僵王使用更宽的表盘，单位像素。
		var foot: Vector2 = target.global_position # 普通僵尸原点为脚底，僵王可用专属脚点。
		if target is ZB000Base:
			foot = target.to_global(Vector2(0.0, target.get_boss_feet_offset_y()))
		draw_set_transform(to_local(foot) + Vector2(0.0, -3.0), 0.0, Vector2(1.0, 0.55))
		if echo < 1.0:
			draw_arc(Vector2.ZERO, radius + 15.0 * echo, 0.0, TAU, 36, Color(HIGHLIGHT, (1.0 - echo) * 0.48), 1.2, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(SHADOW, strength * 0.84), 3.0, true)
		draw_arc(Vector2.ZERO, radius, -PI * 0.5, arc_end, 40, Color(BRASS, strength), 1.5, true)
		for mark: int in range(4): # 表盘四个主刻度。
			var direction: Vector2 = Vector2.from_angle(mark * PI * 0.5) # 局部径向。
			draw_line(direction * (radius - 4.0), direction * (radius + 1.0), Color(BRASS, strength * 0.65), 1.2, true)
		draw_line(Vector2.ZERO, Vector2.from_angle(arc_end) * (radius - 4.0), Color(HIGHLIGHT, strength), 1.7, true)
		draw_line(Vector2.ZERO, Vector2.from_angle(2.34) * radius * 0.53, Color(BRASS, strength), 2.0, true)
		draw_circle(Vector2.ZERO, 2.0, Color(BRASS, strength), true, -1.0, true)
