## 花园飞艇关卡独占的公爵效果池。只向现有画布、风场和声场提交演出。
extends RefCounted

## 世界层的指令、阶段波和传送余波。
const Pressure := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_pressure.gd")
## 发令前后的背景照度，不经过屏幕采样。
const Exposure := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_exposure.gd")
## 近景战斗机编队及与机身分离的尾流。
const Flyby := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_flyby.gd")
## 云层之间的远处导弹齐射。
const Salvo := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_salvo.gd")
## 飞艇已用的短促气压冲击，非导弹预警音。
const IMPACT := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/burst_impact_r7.ogg")
## 随飞行已经载入的单声道掠风，用于蓄势吸气。
const SHEAR := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/flyby_r5.ogg")
## 局内的风、甲板及后景接口。
const Flight := preload("res://scripts/adventure/garden_airship/garden_airship_flight.gd")

## 本局背景、风压与破风入口，作用仅限表现。
var _flight: Flight
## 和实际飞机共用的定位声音池。
var _audio: GardenAirshipSpatialAudio
## 各层的表现对象，在公爵实际登场时创建。
var pressure: Pressure
## 短时背景曝光对象。
var exposure: Exposure
## 近景飞机共享五槽，非战斗实体。
var flyby: Flyby
## 远景发射共享七槽，非战斗弹体。
var salvo: Salvo
## 最后一次局部爆压的时间及位置，离场后用相同风场继续取样。
var _last_origin := Vector2(700, 0)


## 将各层安装到 [param world] 的默认画布、[param background] 低层、[param air] 近层和 [param sky] 远景。
## [param flight] 提供天然风和局部事件，[param audio] 提供已有声部限额。
func install(world: Node2D, background: CanvasLayer, air: CanvasLayer, sky: Node2D,
		flight: Flight, audio: GardenAirshipSpatialAudio) -> void:
	_flight = flight
	_audio = audio
	pressure = Pressure.new()
	pressure.name = &"SkyDukePressure"
	world.add_child(pressure)
	exposure = Exposure.new()
	exposure.name = &"SkyDukeExposure"
	background.add_child(exposure)
	flyby = Flyby.new()
	flyby.name = &"SkyDukeFlyby"
	air.add_child(flyby)
	flyby.setup(audio, world)
	flyby.passed.connect(flight.register_flyby)
	salvo = Salvo.new()
	salvo.name = &"SkyDukeSalvo"
	sky.add_child(salvo)
	sky.move_child(salvo, sky.get_node("Skybox").get_index() + 1)
	salvo.setup(audio)


## [param kind] 决定方向、层级和音色，[param phase] 沿用触发时的公爵阶段。
## [param origin]、[param heading] 为世界坐标，[param born] 和 [param now] 为战斗秒。
## [param seed_value] 稳定每次编队，[param reduced] 使用兼容画质的密度和声音。
func release(kind: StringName, phase: int, origin: Vector2, heading: Vector2,
		born: float, now: float, seed_value: int, reduced: bool) -> void:
	_last_origin = origin
	var strong: bool = phase >= 2 # 二阶段除密度外还有独立的声场和爆压包络。
	var power: float = 0.96 if strong else 0.64 # 本次压力波的归一亮度及半径。
	if kind == &"pressure" or kind == &"teleport_out":
		power *= 0.66
	if reduced:
		power *= 0.86
	if kind == &"command":
		flyby.start(born, phase, seed_value, reduced)
	elif kind == &"sky_order":
		salvo.start(born, phase, seed_value, reduced)
	if not pressure.start(kind, phase, origin, heading, born, seed_value, power, reduced):
		return
	if now - born > 0.14:
		return
	_flight.register_pressure_wave(origin, 0.48 * power)
	if kind != &"pressure":
		exposure.pulse(born, phase, power)
	var gain: float = (-12.5 if strong else -18.5) - (9.0 if kind == &"pressure" else 0.0) # 压缩在现有武器瞬态音量以下。
	var pitch: float = 1.42 if kind == &"sky_order" else (0.86 if strong else 1.08) # 纵向号令更尖锐，二阶段正面爆压更厚。
	_audio.play_at(IMPACT, origin, gain, pitch, &"sky_duke_pressure", 0.22, 0)


## [param origin] 附近的 [param phase] 传送吸气。余光和爆压由原画和世界层接力。
func inhale(origin: Vector2, phase: int) -> void:
	_audio.play_at(SHEAR, origin, -20.0, 0.74 if phase >= 2 else 0.96, &"sky_duke_inhale", 0.46, 0)


## 在 [param seconds] 推进所有已产生的世界表现，并合并各动作的背景 [param charge]。
func update_frame(seconds: float, charge: float) -> void:
	var wind: Vector2 = _flight.wind_for_visual(_last_origin) # 脱离后也能在当局空气里继续衰减。
	pressure.update_frame(seconds, wind)
	exposure.update_frame(seconds, charge)
	if flyby.active_count() > 0:
		flyby.update_frame(seconds, wind)
	if salvo.active_count() > 0:
		salvo.update_frame(seconds, wind)


## 返回尚在调度、显示或衰减的独立效果槽数。
func active_count() -> int:
	return pressure.active_count() + flyby.active_count() + salvo.active_count()


## 交还各层及移动声音，所属战场树仍在时也不会留有曝光或飞掠。
func release_layers() -> void:
	for effect: Node in [pressure, exposure, flyby, salvo]: # 每层只释放自身分配的缓存和声音。
		if is_instance_valid(effect) and not effect.is_queued_for_deletion():
			effect.clear()
			effect.hide()
			effect.queue_free()
