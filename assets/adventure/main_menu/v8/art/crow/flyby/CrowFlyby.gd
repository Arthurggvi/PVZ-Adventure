## 使用本机 DS 审核飞行帧的偶发飞掠；时序为本项目自制，并非官方动画时间轴。
extends Node2D

## 已规范化的四帧目录，保持本机原始帧来源。
@export var frame_folder := "res://assets/adventure/main_menu/v8/art/crow/flyby/frames"
## 两次完整飞掠之间的最小等待秒数。
@export_range(8.0, 40.0, 0.5) var interval_min_seconds := 14.0
## 两次完整飞掠之间的最大等待秒数。
@export_range(8.0, 60.0, 0.5) var interval_max_seconds := 26.0
## 在 1920×1080 设计画布中的水平速度，单位像素/秒。
@export_range(50.0, 400.0, 1.0) var travel_speed := 195.0
## 自制四帧循环的播放频率。
@export_range(3.0, 14.0, 0.5) var flap_fps := 7.0
## 设计画布右侧屏外起点。
@export var fly_start_x := 2020.0
## 岸边路径终点，末段淡出避免突然消失。
@export var fly_end_x := 1220.0
## 眼睛锚点路径高度，避开主入口与功能台。
@export var fly_y := 820.0
## 乌鸦自身缩放，仍继承整张画布的分辨率适配。
@export_range(0.25, 2.0, 0.05) var crow_scale := 1.0
## 单个绘制节点；Node2D 不参与 GUI 命中检测。
var _sprite: Sprite2D
## 经过审核且眼睛对齐的飞行纹理。
var _frames: Array[Texture2D] = []
## 当前是否处于飞掠阶段。
var _active := false
## 本次飞掠已运行的秒数。
var _t := 0.0
## 首次入场等待3秒；之后使用14～26秒随机等待。
var _wait := 3.0
## 一次完整路径播放结束，可用于运行验收。
signal flyby_completed

## 加载仅有的四帧，缺失时停止装饰而不影响菜单功能。
func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "BirdFrames"
	_sprite.centered = false
	_sprite.offset = Vector2(-140, -220)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.scale = Vector2.ONE * crow_scale
	_sprite.hide()
	add_child(_sprite)
	for index: int in range(4): # 仅按16、24、17、18的已审核导出顺序读取。
		var path := frame_folder.path_join("fly_%02d.png" % index) # 当前帧资源路径。
		if not ResourceLoader.exists(path):
			push_error("缺少已审核乌鸦帧：" + path)
			set_process(false)
			return
		_frames.append(load(path) as Texture2D)

## [param delta] 为秒；每帧只更新同一个 Sprite，不创建额外鸟或播放器。
func _process(delta: float) -> void:
	if not _active:
		_wait -= delta
		if _wait <= 0.0:
			_active = true
			_t = 0.0
			_sprite.show()
		return
	_t += delta
	var x := fly_start_x - travel_speed * _t # 当前眼睛锚点的横坐标。
	var progress := clampf((fly_start_x - x) / (fly_start_x - fly_end_x), 0.0, 1.0) # 路径归一化进度。
	_sprite.texture = _frames[int(_t * flap_fps) % _frames.size()]
	_sprite.position = Vector2(x, fly_y - 18.0 * sin(progress * PI) + 2.0 * sin(_t * 4.0))
	_sprite.modulate.a = clampf(minf(progress / 0.08, (1.0 - progress) / 0.12), 0.0, 1.0)
	if x <= fly_end_x:
		_active = false
		_sprite.hide()
		_wait = randf_range(interval_min_seconds, maxf(interval_max_seconds, interval_min_seconds))
		flyby_completed.emit()
