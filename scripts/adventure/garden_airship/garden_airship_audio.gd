## 花园飞艇的局内环境混音。立体声风床和真正的左右桨位共用 R4 的风压包络。
extends Node

## 开阔高空的立体声底风，保留两耳间的细微变化。
const AIR_STREAM := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/air.ogg")
## R4 桨声的单声道派生，用于两侧独立的推进器声源。
const ENGINE_STREAM := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/engine_mono_r5.ogg")
## 低中频风压，保持独立于宽声场空气声。
const PRESSURE_STREAM := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/pressure.ogg")
## 木梁与帆布的短受力声，每个合格事件最多触发一次。
const RIGGING_STREAM := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/rigging.ogg")
## 两侧桨轴在原船框拉伸着色器之后的世界位置。
const ENGINE_ANCHORS := [Vector2(152.0, 727.0), Vector2(1107.0, 726.0)]
## 上梁的两处可见承重索起点。
const RIGGING_ANCHORS := [Vector2(523.815, 162.0), Vector2(1138.215, 163.0)]
## 环境声音服从玩家 SFX 总线，音乐由原 BGM 播放器持有。
const SFX_BUS: StringName = &"SFX"
## 本关仅在需要时补已有的短时峰值保护。
const MASTER_BUS: int = 0
## 下降气流和头顶云是可触发索具的一次性事件。
const DOWNDRAFT: int = 2
## 头顶云经过的导演事件编号。
const CLOUD_EDGE: int = 3

## 一条非定位的原立体风床。
var _air: AudioStreamPlayer
## 关卡位置音效池，由正式战斗场景显式提供。
var _spatial: Node
## x、y、z 分别为平滑空气、风压、云缘。
var _flight := Vector3(0.32, 0.0, 0.0)
## 较快的先兆、风切及近云包络。
var _accents := Vector3.ZERO
## 与船体推力及稳态旗尾共用的平滑巡航负载。
var _drive: float = 0.48
## 平滑的近云位置和短促飞越后让出的风床动态。
var _pan: float = 0.0
## 近场飞越对底风的小幅压低，远景或巡航不触发。
var _duck: float = 0.0
## 真实主爆后的短让位包络。同一批爆炸延续最强值，避免连续压低风床。
var _blast_duck: float = 0.0
## 本次爆炸让位的保持时间，单位自然秒。
var _blast_hold: float = 0.0
## 正在合并的源强度，从 0 到 1。
var _blast_target: float = 0.0
## 进关和切幕时的共同 0～1 包络。
var _entrance: float = 0.0
## 当前关卡的宽风床只有一份循环。
var _started: bool = false
## 上一主事件和该事件的一次索具瞬态状态。
var _last_event_kind: int = 0
## 同一事件只播放一次有明显受力的木梁声。
var _rigging_cued: bool = false
## 当前关卡自行创建的可选 Master 限幅器，退出时按身份撤销。
var _peak_guard: AudioEffectHardLimiter

## [param spatial] 同时服务结构与战斗声源，传参发生在节点入树前。
func configure(spatial: Node) -> void:
	_spatial = spatial

## 只创建具有原有双声道宽度的背景风床。
func _ready() -> void:
	_setup_peak_guard()
	_air = AudioStreamPlayer.new()
	_air.name = &"Air"
	_air.stream = AIR_STREAM
	_air.bus = SFX_BUS
	_air.volume_db = -80.0
	add_child(_air)

## [param weight] 为空间可辨认的一次主爆强度。已在让位时不延长保持窗口。
func cue_blast(weight: float) -> void:
	if _blast_hold <= 0.0 and _blast_duck < 0.24:
		_blast_hold = 0.092
		_blast_target = clampf(weight, 0.0, 1.0)
	elif _blast_hold > 0.0:
		_blast_target = maxf(_blast_target, clampf(weight, 0.0, 1.0))


## [param delta_seconds] 为自然秒。[param airflow]、[param pressure]、[param cloud_pass] 来自 R4 风场和云影。
## [param pan] 与 [param accents] 来自可见近云和下降阶段。[param event_kind] 是导演当前主事件。
## [param audible] 随切幕淡入淡出。[param near_pressure] 只在实际近场飞越时压低底风。
## [param cruise_load] 来自统一航迹的稳态近似动压，用于音色和推进器负荷。
func apply_flight(delta_seconds: float, airflow: float, pressure: float, cloud_pass: float,
		pan: float, event_kind: int, audible: bool = true, accents: Vector3 = Vector3.ZERO,
		near_pressure: float = 0.0, cruise_load: float = 0.48) -> void:
	if not is_node_ready() or not can_process() or delta_seconds <= 0.0:
		return
	var step: float = minf(delta_seconds, 0.12) # 大步长下也不产生突兀增益。
	var target := Vector3(clampf(airflow, 0.0, 1.0), clampf(pressure, 0.0, 1.0), clampf(cloud_pass, 0.0, 1.0)) # 原始导演状态。
	_flight = _flight.lerp(target, 1.0 - exp(-6.0 * step))
	_drive = lerpf(_drive, clampf(cruise_load, 0.0, 1.0), 1.0 - exp(-2.5 * step))
	_accents = _accents.lerp(accents.clamp(Vector3.ZERO, Vector3.ONE), 1.0 - exp(-14.0 * step))
	_pan = lerpf(_pan, clampf(pan, -1.0, 1.0), 1.0 - exp(-(6.0 + 10.0 * _accents.z) * step))
	_duck = lerpf(_duck, near_pressure, 1.0 - exp(-(19.0 if near_pressure > _duck else 4.9) * step))
	var blend: float = _blast_target if _blast_hold > 0.0 else 0.0 # 约 0.22 自然秒内把主爆的让位交回环境。
	_blast_duck = lerpf(_blast_duck, blend, 1.0 - exp(-(40.0 if blend > _blast_duck else 13.0) * step))
	_blast_hold = maxf(0.0, _blast_hold - step)
	if not _started:
		if not audible:
			return
		_started = true
		_air.play()
	_entrance = move_toward(_entrance, 1.0 if audible else 0.0, step / (0.90 if audible else 0.14))
	_apply_beds()
	if audible:
		_update_rigging(event_kind)

## 用原有随事件变化的风床作为底层，桨轴与近云交给同一个局内空间池。
func _apply_beds() -> void:
	var entrance_gain: float = smoothstep(0.0, 1.0, _entrance) # 进关和切幕连续监听。
	var wind_db: float = -7.65 + 1.5 * _drive + 1.6 * _flight.x + 4.6 * _flight.y - 8.0 * _flight.z \
		+ 1.2 * _accents.x + 2.7 * _accents.y - maxf(3.0 * _duck, 3.6 * _blast_duck) # 飞越时只降低环境宽风而不压住炮声或用户界面。
	_air.volume_db = _with_gain(wind_db, entrance_gain)
	_air.pitch_scale = 0.942 + 0.18 * _drive + 0.025 * _flight.x + 0.037 * _flight.y - 0.012 * _flight.z + 0.055 * _accents.y
	if not is_instance_valid(_spatial):
		return
	var engine_db: float = -12.92 + 1.27 * _drive + 1.3 * _flight.y - 1.4 * _flight.z - 2.2 * _accents.x # 下坠前机构短暂卸载。
	var engine_pitch: float = 0.922 + 0.145 * _drive + 0.018 * _flight.x + 0.010 * _flight.y - 0.016 * _accents.x # 两轴慢跟同一巡航负载。
	for index: int in ENGINE_ANCHORS.size(): # 两处声源分别固定在其真正桨轴位置。
		var tuning: float = 0.988 if index == 0 else 1.021 # 两边的机械转声不相位锁定。
		_spatial.update_loop(-10 - index, ENGINE_STREAM, ENGINE_ANCHORS[index],
			_with_gain(engine_db, entrance_gain), engine_pitch * tuning, 0.25, false, 2, float(index) * 1.21)
	var gust_mix: float = maxf(maxf(_flight.y, 0.88 * _flight.z), maxf(0.18 * _accents.x, 0.66 * _accents.z)) # 原事件压力声部按需入池，将常态音色给原立体声风床。
	var pressure_db: float = -2.2 + 2.0 * _flight.z + 3.6 * _accents.z - 1.6 * _accents.y # 减轻风切与空气风床重叠。
	var viewport: Viewport = get_viewport() # 战斗实际可听画面。
	var screen: Vector2 = viewport.get_visible_rect().size * Vector2(0.5 + 0.48 * _pan, 0.67) # 与云的实际左右运动一致。
	var screen_to_world: Transform2D = (viewport.get_global_canvas_transform() * viewport.get_canvas_transform()).affine_inverse() # 回到统一位置映射接受的坐标。
	_spatial.update_loop(-12, PRESSURE_STREAM, screen_to_world * screen,
		_with_gain(pressure_db, entrance_gain * gust_mix), 0.982 + 0.038 * _flight.y - 0.021 * _flight.z, 0.75, false, 2)

## [param event_kind] 只在一次主事件达到原阈值后从上梁挂点发声。
func _update_rigging(event_kind: int) -> void:
	if event_kind != _last_event_kind:
		_last_event_kind = event_kind
		_rigging_cued = false
	var enough_strain: bool = (event_kind == DOWNDRAFT and _flight.y >= 0.72) \
		or (event_kind == CLOUD_EDGE and _flight.z >= 0.72) # 原索具受力包络。
	if _rigging_cued or not enough_strain or not is_instance_valid(_spatial):
		return
	_rigging_cued = true
	var anchor: Vector2 = RIGGING_ANCHORS[0] if _pan <= 0.0 else RIGGING_ANCHORS[1] # 声源跟随较近上梁，而不随已远去的云回弹。
	_spatial.play_at(RIGGING_STREAM, anchor, _with_gain(-3.5, _entrance),
		0.97 + 0.035 * maxf(_flight.y, _flight.z), &"rigging", 0.1, 1)

## 把线性 [param gain] 加到分贝 [param reference_db]，允许平滑进入近静音。
func _with_gain(reference_db: float, gain: float) -> float:
	return reference_db + linear_to_db(maxf(gain, 0.0001))

## 保留 R4 的短时峰值保护和全局已有的音频架构。
func _setup_peak_guard() -> void:
	for index: int in AudioServer.get_bus_effect_count(MASTER_BUS): # 已启用工程级限幅时不重复添加。
		if (AudioServer.is_bus_effect_enabled(MASTER_BUS, index)
				and AudioServer.get_bus_effect(MASTER_BUS, index) is AudioEffectHardLimiter):
			return
	_peak_guard = AudioEffectHardLimiter.new()
	_peak_guard.ceiling_db = -1.2
	_peak_guard.release = 0.08
	AudioServer.add_bus_effect(MASTER_BUS, _peak_guard)

## 退出时只移除本局创建的峰值保护，其他总线资源由原工程负责。
func _exit_tree() -> void:
	if _peak_guard == null:
		return
	for index: int in AudioServer.get_bus_effect_count(MASTER_BUS): # 按实际资源身份撤销，索引可因切场而变。
		if AudioServer.get_bus_effect(MASTER_BUS, index) == _peak_guard:
			AudioServer.remove_bus_effect(MASTER_BUS, index)
			break
