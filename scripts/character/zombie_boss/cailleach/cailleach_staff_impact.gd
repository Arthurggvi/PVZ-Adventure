## 妇人杖击的表现编排：脚边冰光、横扫雪场、白闪失焦和触地爆鸣。
extends Node2D

## 可在其他战斗演出复用的白闪与失焦画布。
const Whiteout = preload("res://scripts/fx/battle_whiteout.gd")
## 仅本演出使用的贴地光与星芒。
const IMPACT_SHADER: Shader = preload("res://shaders/adventure/wonderland/cailleach_staff_impact.gdshader")
## 将平面原点贴到杖尖，尺寸与贴地光着色器一致。
const LIGHT_BOUNDS := Rect2(-272.0, -210.0, 544.0, 330.0)
## 触地光与碎冰的生命周期，单位游戏秒。
const LIFETIME: float = 1.34
## 吹向左侧的峰值风速，世界像素/秒。
const WIND_VELOCITY := Vector2(-1420.0, -14.0)
## 从触地到融回环境风的完整游戏秒数。峰值保持约四分之一秒，再沿风场包络逐渐回落。
const WIND_DURATION: float = 1.65
## 触地的高频星闪、厚低频和逐渐退开的共振尾声。
## 高频取自 Freesound 的 CC0 素材 462095（LilMati）与 817275（CVLTIV8R）。
const SOUND_PATH: String = "res://resources/adventure/audio/cailleach_staff_impact.ogg"
## 附着在触地点的独立可变材质。
var _light: ShaderMaterial
## 从触地关键帧起经过的游戏秒。
var _age: float = 0.0

## 装配随战场暂停和离场的局部光源。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_light = ShaderMaterial.new()
	_light.shader = IMPACT_SHADER
	var plane := ColorRect.new() # 原点在触地点，不受摄像机或 HUD 布局影响。
	plane.position = LIGHT_BOUNDS.position
	plane.size = LIGHT_BOUNDS.size
	plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plane.z_index = -1
	plane.material = _light
	add_child(plane)

## 在 [param battle] 内的 [param contact] 世界坐标同步播放本次触地的视听表现。
func play(battle: MainGameManager, contact: Vector2) -> void:
	global_position = contact
	var snow: SnowEnvironmentController = battle.background_manager.snow_environment # 雪山使用本局天气风场。
	if is_instance_valid(snow):
		snow.play_wind_burst(WIND_VELOCITY, WIND_DURATION)
	var flash := Whiteout.new() # 整屏处理在雪与 HUD 已经绘制之后。
	flash.configure(get_global_transform_with_canvas().origin, 0.58, 0.97)
	battle.add_child(flash)
	battle.camera_2d.shake_once(Vector2(10.0, 16.0), 0.34, 17.0)
	var stream: AudioStream = load(SOUND_PATH) as AudioStream # 只有实战触地才读取此短音。
	if stream != null:
		var player := AudioStreamPlayer.new() # 战场持有音效，倍速下仍保留完整共振尾声。
		player.stream = stream
		player.bus = SoundManager.spatial_sfx_bus(SoundManagerClass.SFXSpace.COMBAT)
		player.volume_db = -3.0
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.finished.connect(player.queue_free)
		battle.add_child(player)
		player.play()
	queue_redraw()

## [param delta] 为引擎游戏秒；同步推进贴地光与飞散碎冰。
func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	_light.set_shader_parameter(&"age_seconds", _age)
	queue_redraw()

## 用确定性的散射方向画出碎冰，先从脚边炸起，再被横风带走。
func _draw() -> void:
	for index: int in range(28): # 单次杖击的有限碎片预算。
		var seed: float = fposmod(float(index) * 0.61803399, 1.0) # 交错的存活时长和碎片长度。
		var angle: float = float(index) * 2.3999632 # 均匀分散初始角度，无需占用玩法随机数。
		var progress: float = clampf(_age / lerpf(0.47, 1.13, seed), 0.0, 1.0) # 单片从离地到隐去的进度。
		if progress >= 1.0:
			continue
		var direction := Vector2(cos(angle), sin(angle) * 0.32) # 初始爆散贴近地平面。
		var spread: float = (1.0 - exp(-5.0 * progress)) * (48.0 + seed * 113.0) # 地面散射半径。
		var lift: float = sin(PI * progress) * (18.0 + seed * 69.0) # 离地的小弧线。
		var point: Vector2 = direction * spread + Vector2(-114.0 * progress * progress, -lift) # 风将高处碎屑带向左。
		var trail: Vector2 = Vector2(5.0 + seed * 18.0, lift * 0.10 - direction.y * 5.0) # 横风下保留细亮拖尾。
		var alpha: float = smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(0.40, 1.0, progress)) # 退场不跳变。
		draw_line(point, point + trail, Color(0.54, 0.83, 1.0, alpha * 0.53), 1.0 + seed, true)
		draw_circle(point, 1.35 + seed * 1.82, Color(0.88, 0.965, 1.0, alpha), true, -1.0, true)
