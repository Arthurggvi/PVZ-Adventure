## 一个有界环境效果：循环帧、漂移云或复用单个节点的烟团/气泡。
extends AnimatedSprite2D

## 整图局部遮罩着色器。
const MASK_SHADER = preload("res://shaders/adventure/environment_mask.gdshader")
## 本效果的数据配置，生命周期由所在场景拥有。
var settings: Dictionary
## 设计空间中的初始锚点。
var base_position: Vector2
## 不带动画的设计绘制尺寸。
var draw_size: Vector2
## 本地时钟；停止时不推进，不使用全局Timer。
var elapsed := 0.0
## 当前烟团/气泡选择过的周期编号。
var puff_cycle := -1
## 每个粒子周期的有限随机偏移，不创建新节点。
var puff_offset := Vector2.ZERO
## 部分气泡周期留空，使疏密独立变化。
var puff_visible := true
## 可选的随动船体，不创建第二套船节点。
var anchor: Control
## 背景真实显示区域的局部原点，遮罩不能以单个精灵UV采样。
var mask_origin: Vector2

## [param data] 为效果配置；[param ship] 为现有船体，可为空；[param background_region] 为真实背景显示区。
func configure(data: Dictionary, ship: Control, background_region: Rect2) -> void:
	settings = data
	base_position = Vector2(data.position[0], data.position[1])
	draw_size = Vector2(data.size[0], data.size[1])
	anchor = ship if data.get("anchor", "") == "ship" else null
	mask_origin = background_region.position
	centered = false
	sprite_frames = SpriteFrames.new()
	sprite_frames.clear("default")
	for path: String in data.frames: # 只加载配置指向的独立运行素材。
		sprite_frames.add_frame("default", load(path) as Texture2D)
	sprite_frames.set_animation_speed("default", float(data.get("fps", 1.0)))
	if data.has("mask"):
		var region := ShaderMaterial.new() # 每个移动效果需要独立的局部原点参数。
		region.shader = MASK_SHADER
		region.set_shader_parameter("region_mask", load(data.mask))
		region.set_shader_parameter("alpha_channel", data.get("mask_alpha", false))
		region.set_shader_parameter("canvas_size", background_region.size)
		material = region
	set_running(true)

## [param running] 关闭时停止内部帧动画并清空粒子相位，恢复后不积攒烟或气泡。
func set_running(running: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if running else Node.PROCESS_MODE_DISABLED
	elapsed = 0.0
	puff_cycle = -1
	visible = running
	if running and settings.get("mode", "loop") != "puff":
		play()
		frame = int(float(settings.get("phase", 0.0)) * sprite_frames.get_animation_speed("default")) % sprite_frames.get_frame_count("default")
	else:
		stop()
	if running:
		_process(0.0)

## [param delta] 为秒。复用此节点，不逐帧创建粒子或Tween。
func _process(delta: float) -> void:
	elapsed += delta
	var mode: String = settings.get("mode", "loop") # 当前效果的运动种类。
	var time := elapsed + float(settings.get("phase", 0.0)) # 配置相位，避免全部同步。
	var period: float = settings.get("period", 8.0) # 缓慢的漂移或粒子周期。
	var wave := sin(time * TAU / period) # 平滑变化，不频闪。
	var opacity: float = settings.get("opacity", 0.5) # 素材原Alpha之外的强度上限。
	var current_size := draw_size # 本帧的实际绘制尺寸。
	position = base_position
	modulate.a = opacity
	if mode == "cloud":
		position.x = fposmod(base_position.x + elapsed * float(settings.speed) + draw_size.x, 1920.0 + draw_size.x) - draw_size.x
	elif mode == "drift":
		var drift: Array = settings.get("drift", [0, 0]) # 仅数像素范围的摆动。
		position += Vector2(drift[0] * wave, drift[1] * cos(time * TAU / period))
		modulate.a *= 0.75 + 0.25 * wave
	elif mode == "water_drift":
		var travel: float = settings.travel # 在有限海面范围漂移，周期间隙淡出而非跳闪。
		var progress := fposmod(time * float(settings.speed) / travel, 1.0) # 按原背景像素/秒换算后的运动进度。
		position += Vector2((progress - 0.5) * travel, 2.0 * sin(progress * TAU))
		modulate.a *= sin(progress * PI)
	elif mode == "ripple":
		var phase := fposmod(time / period, 1.0) # 局部涟漪扩散后消退。
		current_size *= 0.85 + 0.2 * phase
		position += (draw_size - current_size) / 2
		modulate.a *= sin(phase * PI)
	elif mode == "puff":
		var cycle := int(time / period) # 每个周期独立选一种烟/气泡形态，不顺序连播。
		if cycle != puff_cycle:
			puff_cycle = cycle
			frame = randi_range(0, sprite_frames.get_frame_count("default") - 1)
			var spread: Array = settings.get("spread", [0, 0]) # 只在锚点附近小范围随机。
			puff_offset = Vector2(randf_range(-spread[0], spread[0]), randf_range(-spread[1], spread[1]))
			puff_visible = randf() >= float(settings.get("skip_probability", 0.0))
		var phase := fposmod(time / period, 1.0) # 单个粒子的上升与淡出进度。
		var rise: Array = settings.get("rise", [0, -30]) # 统一风向或上浮位移。
		if is_instance_valid(anchor):
			var local: Array = settings.anchor_offset # 船体局部烟囱口。
			position = anchor.get_transform() * Vector2(local[0], local[1]) - Vector2(draw_size.x / 2, draw_size.y)
		position += puff_offset + Vector2(rise[0], rise[1]) * phase
		current_size *= 0.8 + 0.25 * phase
		modulate.a *= sin(phase * PI) * (1.0 - phase) if puff_visible else 0.0
	var texture_size := sprite_frames.get_frame_texture("default", frame).get_size() # 原帧尺寸。
	scale = current_size / texture_size
	if material != null:
		material.set_shader_parameter("origin", position - mask_origin)
		material.set_shader_parameter("render_size", current_size)
