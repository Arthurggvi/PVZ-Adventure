## 凯莱赫死亡即起风雪与白光，落星结束后接消隐和停雪。
extends Node

## 人物已经消隐，场景自然降雪也已退去。
signal finished

## 愠怒的近景和镜头雪共用原有的两批限额粒子。
const NearSnow = preload("res://scripts/character/zombie_boss/cailleach/cailleach_anger_snow.gd")
## 最后一枚落星后，留给雪墙吞没原画的游戏秒数。
const BURST_HOLD: float = 1.80
## 暴雪衰减、远近雪层陆续停下所用的游戏秒数。
const CLEAR_SECONDS: float = 4.00
## 给不同树顺序下的天气控制器留出一帧更新时间，单位为游戏秒。
const WEATHER_TAIL: float = 0.16

## 本场原有雪、风、云和风声。
var _weather: SnowEnvironmentController
## 天空与地形之间的原画；尾声始终保留在原画布。
var _pose: AnimatedSprite2D
## 原画的白影与顺风消隐参数由本次暴雪暂时驱动。
var _portrait: ShaderMaterial
## 人物旁的雪脊卷雾随世界雪一起平息。
var _ridge: ShaderMaterial
## 镜头前两种尺寸的追加近雪。
var _near_snow: NearSnow
## 从死亡起已经经过的游戏秒数。
var _age: float = 0.0
## 最后一枚落星后的游戏秒数，负值表示仍在落星。
var _aftermath: float = -1.0
## 原画初始透明度，供无远景材质的其他战场及中断恢复使用。
var _pose_alpha: float = 1.0
## 收势时只发出一次完成通知。
var _completed: bool = false

## [param weather] 为本场雪控制器，[param pose] 为角色原画。
## [param portrait] 与 [param ridge] 是独立可空的原画和雪脊材质。
func _init(weather: SnowEnvironmentController, pose: AnimatedSprite2D, portrait: ShaderMaterial,
		ridge: ShaderMaterial) -> void:
	_weather = weather
	_pose = pose
	_portrait = portrait
	_ridge = ridge
	name = "CailleachDeathDeparture"

## 死亡同帧启动原有天气和两层近雪，并点亮原画。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if is_instance_valid(_pose):
		_pose_alpha = _pose.modulate.a
	if is_instance_valid(_weather):
		_weather.begin_departure_storm()
	_near_snow = NearSnow.new(_weather)
	add_child(_near_snow)
	_present()

## 最后一枚极光实际结算后合拢雪墙，从当前已经累积的风雪继续。
func begin_dissolve() -> void:
	if _aftermath < 0.0:
		_aftermath = 0.0

## 以 [param delta] 同步推进起雪、白光和停雪。暂停时保留时序。
func _process(delta: float) -> void:
	var step: float = clampf(delta, 0.0, 0.15) # 与原天气每帧能够消费的游戏秒一致。
	_age += step
	if _aftermath >= 0.0:
		var previous: float = _aftermath # 确保达到峰值后只通知一次停雪。
		_aftermath += step
		if previous < BURST_HOLD and _aftermath >= BURST_HOLD and is_instance_valid(_weather):
			_weather.clear_departure_storm(CLEAR_SECONDS)
	_present()
	if _aftermath < BURST_HOLD + CLEAR_SECONDS + WEATHER_TAIL:
		return
	_completed = true
	set_process(false)
	if is_instance_valid(_pose):
		_pose.hide()
	finished.emit()
	queue_free()

## 落星期间持续加厚雪墙，白光沿原画轮廓呼吸，落星之后随风消隐。
func _present() -> void:
	var tail: float = maxf(0.0, _aftermath) # 在最后一枚落地前，所有收势项都为零。
	var buildup: float = 1.0 - 0.76 * exp(-0.36 * _age) # 死亡当帧已加雪，之后按持续时间逐步逼近峰值。
	var surge: float = lerpf(buildup, 1.0, smoothstep(0.0, 0.42, tail)) # 最后一发之后从当前强度连续合拢。
	var clearing: float = smoothstep(BURST_HOLD, BURST_HOLD + CLEAR_SECONDS, tail) # 停雪前留一段零星飞雪。
	var dissolve: float = smoothstep(0.33, BURST_HOLD, tail) # 只在最后一枚结算后让雪墙吞没人影。
	if _aftermath < BURST_HOLD and is_instance_valid(_weather):
		_weather.set_departure_storm_strength(surge)
	_near_snow.present(surge * (1.0 - clearing))
	if _portrait != null:
		_portrait.set_shader_parameter(&"anger_veil", smoothstep(0.0, 0.66, tail))
		_portrait.set_shader_parameter(&"departure_dissolve", dissolve)
		_portrait.set_shader_parameter(&"death_glow", _body_glow(tail, dissolve))
	elif is_instance_valid(_pose):
		_pose.modulate.a = _pose_alpha * (1.0 - dissolve)
	if _ridge != null:
		_ridge.set_shader_parameter(&"anger_veil", surge * (1.0 - clearing))
		_ridge.set_shader_parameter(&"departure_dissolve", clearing)

## [param tail] 是落星结束后的秒数，[param dissolve] 为已消隐的比例。
## 用短而柔的脉冲表现发光，亮后的轮廓自然暗下再蓄亮。
func _body_glow(tail: float, dissolve: float) -> float:
	var initial: float = 1.0 - smoothstep(0.04, 0.33, _age) # 致死帧先亮一次，随后退回原画受光。
	var beat: float = _age * 0.92 + sin(_age * 1.63) * 0.08 # 每次明灭间隔略有不同。
	var pulse: float = pow(0.5 + 0.5 * cos(TAU * beat), 4.0) * 0.88 # 明亮半拍，轮廓余光比亮芯更宽。
	var final_flare: float = smoothstep(0.0, 0.10, tail) * (1.0 - smoothstep(0.14, 0.61, tail)) # 最后一落亮到雪里。
	return maxf(maxf(initial, pulse), final_flare) * (1.0 - dissolve)

## 半途离场时归还材质；完成后保留原画与雪脊都已消隐的末帧，等待本体移除。
func _exit_tree() -> void:
	if _completed:
		return
	if is_instance_valid(_weather):
		_weather.clear_departure_storm(CLEAR_SECONDS)
	if is_instance_valid(_pose):
		_pose.modulate.a = _pose_alpha
	if _portrait != null:
		_portrait.set_shader_parameter(&"anger_veil", 0.0)
		_portrait.set_shader_parameter(&"departure_dissolve", 0.0)
		_portrait.set_shader_parameter(&"death_glow", 0.0)
	if _ridge != null:
		_ridge.set_shader_parameter(&"anger_veil", 0.0)
		_ridge.set_shader_parameter(&"departure_dissolve", 0.0)
