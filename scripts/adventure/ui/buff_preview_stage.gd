## 单次 Buff 演示场景，角色、特效、护卫与计时都由本节点持有。
extends Node2D

## 无脚本角色外观和安全属性动画。
const Actor: GDScript = preload("res://scripts/adventure/ui/buff_preview_actor.gd")
## 纯展示数值与状态编排。
const Model: GDScript = preload("res://scripts/adventure/ui/buff_preview_model.gd")
## 按需使用的原生视觉效果。
const Effects: GDScript = preload("res://scripts/adventure/ui/buff_preview_fx.gd")
## 双栏读数及方向、命中等机制提示。
const Overlay: GDScript = preload("res://scripts/adventure/ui/buff_preview_overlay.gd")
## 当前条目副本，不保留可写存档或战斗状态。
var _entry: Dictionary = {}
## 正常与状态组各自的纯视觉骨架。
var _actors: Array[Actor] = []
## 各侧原生效果的独立容器。
var _effects: Array[Effects] = []
## 各侧已经走过的演示距离，单位为舞台像素。
var _travel: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## 当前教学循环内秒数。
var _elapsed: float = 0.0
## 覆盖在角色之上的纯图形读数。
var _overlay: Overlay
## 转伤条目的合格护卫外观；不具有防具或生命组件。
var _guardian: Actor

## 根据 [param entry] 创建两组相同样本，资源必须已由详情宿主准备。
func setup(entry: Dictionary) -> void:
	_entry = entry.duplicate(true)
	var subject: String = Actor.subject_for(entry) # 同一示例物种，保证两侧可直接比较。
	for index: int in range(2): # 对照组在左，施加状态组在右。
		var actor: Actor = Actor.new() # 角色场景本身不会进入此树。
		actor.z_index = 1
		add_child(actor)
		actor.build(subject)
		_actors.append(actor)
		var effects: Effects = Effects.new() # 原生粒子和动画也只属于这一侧。
		effects.z_index = 2
		add_child(effects)
		effects.build(entry)
		_effects.append(effects)
	if entry.get("preview_id", &"") == &"damage_transfer":
		_guardian = Actor.new()
		_guardian.z_index = 1
		add_child(_guardian)
		_guardian.build("zombie", 78.0)
	_overlay = Overlay.new()
	_overlay.z_index = 10
	add_child(_overlay)
	_overlay.setup(entry)
	advance(0.0)
	queue_redraw()

## 用 [param delta] 秒推进当前示例；周期结束重置本地画面，不声称永久状态自然到期。
func advance(delta: float) -> void:
	_elapsed += maxf(0.0, delta)
	if _elapsed >= Model.cycle_seconds(_entry):
		_elapsed = fposmod(_elapsed, Model.cycle_seconds(_entry))
		_travel = PackedFloat32Array([0.0, 0.0])
	var frames: Array[Dictionary] = [] # 同帧两侧读数交给覆盖层一起绘制。
	var positions: Array[Vector2] = [] # 原生效果与读数跟随演员脚点。
	for index: int in range(_actors.size()): # 两组同一个时钟，仅状态输入不同。
		var frame: Dictionary = Model.frame(_entry, _elapsed, index == 1) # 无任何正式角色或全局状态参与。
		var actor: Actor = _actors[index] # 当前组的纯视觉骨架。
		_travel[index] += float(frame["move"]) * delta * 23.0
		var drift: float = fposmod(_travel[index] + 34.0, 68.0) - 34.0 # 每侧独立短跑道，始终不越过中线。
		actor.position = Vector2(105 + index * 210 + drift, 208) + Vector2(frame["offset"])
		if str(frame["special"]) == "transfer":
			actor.position.x -= 23.0
		actor.pose(frame["pose"])
		var tint: Color = frame["tint"] # 原生状态色与受击余辉在本示例内组合。
		tint.a *= float(frame["alpha"])
		if bool(frame["health_visible"]) and float(frame["health"]) <= 0.0:
			frame["rate"] = 0.0
			tint *= Color(0.55, 0.55, 0.55)
		actor.advance(delta * float(frame["rate"]), tint, bool(frame["flip"]))
		_effects[index].position = actor.position
		_effects[index].render_frame(frame, _elapsed)
		frames.append(frame)
		positions.append(actor.position)
	if _guardian != null:
		_guardian.visible = _elapsed >= 1.0
		_guardian.position = positions[1] + Vector2(57, 0)
		_guardian.advance(delta, Color.WHITE)
	_overlay.update_frame(frames, positions, _elapsed)

## 舞台背景保留两侧相同光照，分区与地面帮助辨认移动、抛起和换行。
func _draw() -> void:
	draw_rect(Rect2(0, 0, 420, 330), Color("142c29"))
	for index: int in range(2): # 相同颜色的草地避免把背景变化误读为状态染色。
		var left: float = index * 210.0 + 8.0 # 各侧内部起点，保证有可见中缝。
		draw_rect(Rect2(left, 53, 194, 159), Color("45644c"))
		draw_rect(Rect2(left, 184, 194, 28), Color("526d44"))
		draw_line(Vector2(left + 6, 208), Vector2(left + 188, 208), Color("8ea26e"), 2.0)
		for mark: int in range(6): # 地面刻度让两个样本的速度差清楚可见。
			draw_line(Vector2(left + 18 + mark * 31, 204), Vector2(left + 18 + mark * 31, 211), Color("779363"), 1.0)
