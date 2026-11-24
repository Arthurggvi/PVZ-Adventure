## 状态舞台的对照读数与机制标记；每帧重绘固定图元，不生成战斗弹体或拾取物。
extends Node2D

## 原生阳光纹理路径，只有光能或产量条目才加载。
const Effects: GDScript = preload("res://scripts/adventure/ui/buff_preview_fx.gd")
## 与原图鉴共用的完整中文字库，桌面和移动端均不依赖系统字体。
const FONT_PATH: String = "res://assets/fonts/方正少儿_GBK.ttf"
## 当前图鉴字体的只读引用。
var _font: Font
## 当前两侧画面参数，由舞台负责更新。
var _frames: Array[Dictionary] = []
## 各示例角色脚底位置，命中和状态标记跟随角色。
var _positions: Array[Vector2] = []
## 当前本地循环秒数。
var _time: float = 0.0
## 只供本视口绘制的阳光图像，没有可拾取节点。
var _sun: Texture2D
## 用于区分血池与动作仪表的条目身份。
var _id: StringName = &""

## 按 [param entry] 准备少量纯图像与中文标签样式。
func setup(entry: Dictionary) -> void:
	_font = load(FONT_PATH) as Font
	_id = entry.get("preview_id", &"")
	if _id in [&"sun_infusion", &"sun_yield"]:
		_sun = load(Effects.SUN_PATH) as Texture2D

## 接收 [param frames]、[param positions] 和 [param time] 后只请求一次重绘。
func update_frame(frames: Array[Dictionary], positions: Array[Vector2], time: float) -> void:
	_frames = frames
	_positions = positions
	_time = time
	queue_redraw()

## 绘制两侧同规格读数，使动作、伤害与资源效果都能直接比较。
func _draw() -> void:
	for index: int in range(_frames.size()): # 同一时刻的左侧基线和右侧状态。
		var frame: Dictionary = _frames[index] # 当前侧的纯展示快照。
		var left: float = index * 210.0 + 12.0 # 每侧固定宽度，边缘留空不碰父窗口木框。
		var feet: Vector2 = _positions[index] # 角色可能正逃跑、被抛起或换行。
		_text("未施加" if index == 0 else "施加后", Vector2(left, 26), 186, 17, Color("f7e6bc"))
		_text("对照示例" if index == 0 else ("准备施加" if _time < 1.0 else "状态演示"), Vector2(left, 46), 186, 12, Color("b4c9bd"))
		_text(str(frame["metric"]), Vector2(left, 233), 186, 15, Color("fff1bc"))
		_meter(frame, left)
		_text(str(frame["detail"]), Vector2(left, 286), 186, 12, Color("cbd9d0"))
		_signals(frame, feet, left)
	_text("循环示意 · 演示会自动重置", Vector2(12, 318), 396, 12, Color("9eb4a6"))

## 在 [param left] 起始位置绘制 [param frame] 的生命、护甲或机制进度。
func _meter(frame: Dictionary, left: float) -> void:
	var health_mode: bool = bool(frame.get("health_visible", false)) # 控制类显示节拍，承伤类显示示例生命。
	var value: float = clampf(float(frame["health"]) / float(frame["max_health"]), 0.0, 1.0) if health_mode else float(frame["counter"]) # 归一化可见读数。
	if value < 0.0:
		value = fposmod(_time * float(frame["rate"]), 1.0) if float(frame["rate"]) > 0.0 else 0.0
	draw_rect(Rect2(left + 9, 245, 168, 7), Color("0c1b19"))
	draw_rect(Rect2(left + 9, 245, 168 * value, 7), Color("77be78") if health_mode else Color("83c9c0"))
	if float(frame["armor"]) > 0.0:
		draw_rect(Rect2(left + 9, 254, 168 * minf(1.0, float(frame["armor"]) / float(frame.get("armor_max", 300.0))), 4), Color("80caf3"))
	var caption: String = "示例生命 %d / %d" % [int(frame["health"]), int(frame["max_health"])] if health_mode else "动作 / 状态进度" # 标记读数性质。
	_text(caption, Vector2(left, 269), 186, 11, Color("9fb7ac"))

## 根据 [param frame] 在 [param feet] 周围画机制提示；[param left] 为当前半区起点。
func _signals(frame: Dictionary, feet: Vector2, left: float) -> void:
	var special: String = str(frame["special"]) # 仅用于选择教学图形，不表示实战特效节点。
	var hit: float = float(frame["hit"]) # 刚发生示例事件时的余辉，0至1。
	var shot: float = float(frame["shot"]) # 同侧弹道进度，负值表示没有事件。
	var chest: Vector2 = feet + Vector2(0, -65) # 状态标记不依赖样本骨架的内部节点名。
	if shot >= 0.0:
		var start: Vector2 = Vector2(left + 5, chest.y) # 承伤示例从半区左边射入。
		var finish: Vector2 = chest + Vector2(-8, 0) # 到角色前方结束，不参与任何碰撞。
		if bool(frame["outgoing"]):
			start = chest + Vector2(24, -8)
			finish = Vector2(left + 181, chest.y - 8)
		draw_circle(start.lerp(finish, shot), 5, Color("b3e26e"))
	if hit > 0.0:
		var hit_color: Color = Color("a9f28f") if special == "heal" else Color("fff0bc") # 回复和命中以颜色区分。
		hit_color.a = hit
		draw_arc(chest, 27 + (1.0 - hit) * 12, 0, TAU, 28, hit_color, 2.0)
		_text(str(frame["value"]), chest + Vector2(-45, -30 - (1.0 - hit) * 18), 90, 18, hit_color)
	match special:
		"bite":
			draw_rect(Rect2(left + 14, 158, 24, 38), Color("bfa36b"))
			_text("靶", Vector2(left + 14, 181), 24, 14, Color("473b28"))
			if hit > 0.0:
				draw_arc(Vector2(left + 28, 171), 21, -1.0, 1.0, 16, Color("fff0bc"), 3.0)
		"stun":
			_text("★  ★  ★", chest + Vector2(-40, -67), 80, 18, Color("fff28f"))
		"sleep":
			_text("Z z", chest + Vector2(17, -42), 55, 22, Color("d2c1ff"))
		"enemy":
			_text("敌近", Vector2(left + 130, 191), 53, 13, Color("f4b4a2"))
		"skill", "spawns":
			var center: Vector2 = Vector2(left + 164, 83) # 独立技能/刷怪时钟，不暗示冻结身体。
			draw_circle(center, 14, Color("263d3c"))
			draw_arc(center, 14, -PI / 2.0, TAU * maxf(float(frame["counter"]), 0.01) - PI / 2.0, 28, Color("b0a5e1"), 3.0)
			_text("技能" if special == "skill" else "刷怪", center + Vector2(-24, 31), 48, 11, Color("c6beda"))
			if bool(frame["paused"]):
				draw_line(center + Vector2(-7, -7), center + Vector2(7, 7), Color("eb8d8d"), 3.0)
		"ward", "armor":
			draw_arc(chest, 47, -2.4, 2.4, 40, Color(0.43, 0.83, 1.0, 0.8), 3.0)
		"water":
			draw_rect(Rect2(left, 184, 186, 28), Color(0.12, 0.54, 0.72, 0.65))
			for wave: int in range(3): # 三条水纹只表示拖入水下的过程。
				draw_arc(Vector2(left + 35 + wave * 56, 193), 20, 0, PI, 16, Color("82d7dd"), 2.0)
		"transfer":
			_arrow(chest + Vector2(12, -8), chest + Vector2(57, 18), Color("95d9ef"))
			_text("护卫", chest + Vector2(33, -26), 60, 12, Color("b2e3f5"))
			draw_rect(Rect2(chest.x + 30, feet.y + 2, 48 * float(frame["aux"]) / 1000.0, 4), Color("80bcd2"))
		"detonation":
			if hit > 0.0:
				draw_arc(chest, 20 + (1.0 - hit) * 65, 0, TAU, 48, Color(1.0, 0.65, 0.2, hit), 5.0)
		"sun":
			if _sun != null and hit > 0.0:
				var location: Vector2 = chest + Vector2(28, -38 - (1.0 - hit) * 24) # 原纹理只在本视口短暂上浮。
				draw_texture_rect(_sun, Rect2(location, Vector2(32, 32)), false, Color(1, 1, 1, hit))
				_text("+%d" % int(frame["aux"]), location + Vector2(-5, 47), 50, 14, Color("ffe28b"))

## 绘制从 [param start] 指向 [param finish] 的机制箭头；[param color] 指定提示颜色。
func _arrow(start: Vector2, finish: Vector2, color: Color) -> void:
	var direction: Vector2 = (finish - start).normalized() # 箭头只表明转移方向，不对应真实路由距离。
	draw_line(start, finish, color, 3.0)
	draw_line(finish, finish - direction.rotated(0.5) * 10, color, 3.0)
	draw_line(finish, finish - direction.rotated(-0.5) * 10, color, 3.0)

## 将 [param message] 居中于 [param origin] 起始的 [param width] 宽区域，字号上限 [param font_size]、颜色 [param color]。
## 中文较长时缩至11像素；所有文案都是短标签，避免跑出舞台边界。
func _text(message: String, origin: Vector2, width: float, font_size: int, color: Color) -> void:
	var fitted: int = font_size # 只缩当前读数，不改变其他区域排版。
	while fitted > 11 and _font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > width:
		fitted -= 1
	draw_string(_font, origin, message, HORIZONTAL_ALIGNMENT_CENTER, width, fitted, color)
