## 载具击毁音效使用本局 R5 声场，固定冲击和移动尾声各有生命周期。
extends RefCounted

## 原击毁音的短瞬态派生，固定爆心仅保留一次瞬态冲击。
const IMPACT: AudioStream = preload("res://assets/adventure/wonderland/battle/garden_airship/audio/burst_impact_r7.ogg")
## 独立机械断裂及较弱余爆的短音。
const FOLLOWUP: AudioStream = preload("res://assets/adventure/zombies/arbiter_x/audio/impact_followup.ogg")
## 仲裁者第一下机鼻触地的短擦碰。
const SCRAPE: AudioStream = preload("res://assets/adventure/zombies/arbiter_x/audio/touchdown_scrape.ogg")
## 舰体真正断成裁片时的金属开裂。
const FRACTURE: AudioStream = preload("res://assets/adventure/zombies/transport_airship/audio/fracture.ogg")
## 将原掠风和噼啪放在同一短样本，共用移动残骸的真实声像。
const FIRE: AudioStream = preload("res://assets/adventure/wonderland/battle/garden_airship/audio/burst_tail_r7.ogg")
## 早段风切和小鬼喷射失推使用原单声道掠风。
const SHEAR: AudioStream = preload("res://assets/adventure/wonderland/battle/garden_airship/audio/flyby_r5.ogg")
## 真实可见画幅归一化后，移动源可在右缘外继续很短的淡出。
const TAIL_EDGE: float = 1.12
## 避开 R6 背景的负 ID 和 Godot 实例的正 ID。
const TOKEN_BASE: int = -1000000
## 每种机体的主爆音量基准和听觉尺度。
const PRIMARY_MIX := {
	&"fighter": Vector2(-7.5, 1.16),
	&"turret": Vector2(-5.0, 0.93),
	&"arbiter": Vector2(-4.4, 0.91),
	&"transport": Vector2(-5.1, 0.85),
}
## 燃烧源早期的余火强度、音高和声音空间纵深。
const TAIL_MIX := {
	&"fighter": Vector3(-10.8, 1.14, 0.60),
	&"turret": Vector3(-11.0, 0.92, 0.72),
	&"arbiter": Vector3(-9.8, 0.90, 0.45),
	&"transport": Vector3(-10.2, 0.86, 0.58),
	&"rocket": Vector3(-17.0, 1.27, 0.38),
}

## R5 实际播放和位置跟踪由关卡显式注入。
var _spatial: GardenAirshipSpatialAudio


## [param spatial] 持有本局真实听者与兼容的移动及短声部池。
func setup(spatial: GardenAirshipSpatialAudio) -> void:
	_spatial = spatial


## 主爆冲击在 [param origin] 即刻进入瞬态保留槽。[param kind] 与 [param size] 区分体型。
## [param full] 决定省略与主要反馈竞争的结构短声。
func primary(kind: StringName, origin: Vector2, size: float, full: bool) -> void:
	if not is_instance_valid(_spatial):
		return
	if kind == &"rocket":
		_spatial.play_at(FOLLOWUP, origin, -20.6, 1.35, &"rocket_exhaust_cut", 0.35, 1)
		return
	var mix: Vector2 = PRIMARY_MIX[kind] # 强主爆独立于邻近次爆、淡出声和装饰短声。
	var scale_db: float = clampf(linear_to_db(maxf(size, 0.20) / 0.55), -8.0, 3.0) # 小僵尸的源增益有界。
	_spatial.play_at(IMPACT, origin, mix.x + scale_db - (0.0 if full else 3.0),
		mix.y, &"vehicle_burst", 0.18, 3)
	if kind == &"transport" and full:
		_spatial.play_at(FRACTURE, origin, -9.8, 0.90, &"transport_fracture", 0.27, 1)


## 代表机体的次爆在 [param origin] 当帧发声。[param kind] 与 [param index] 区分结构和后段余爆。
func secondary(kind: StringName, origin: Vector2, index: int) -> void:
	if not is_instance_valid(_spatial):
		return
	var pitch: float = 1.12 if kind == &"fighter" else 0.88 # 小载具的金属碎裂短促偏高。
	var stream: AudioStream = FRACTURE if kind == &"arbiter" and index == 0 else FOLLOWUP # 大翼片一次真实撕裂。
	_spatial.play_at(stream, origin, -12.3 - float(index) * 2.8,
		pitch + float(index) * 0.035, &"vehicle_followup", 0.3, 0)


## 首次 [param origin] 接地的固定擦碰声，与后续移动的爆裂清楚错开。
func contact(origin: Vector2) -> void:
	if is_instance_valid(_spatial):
		_spatial.play_at(SCRAPE, origin, -8.2, 0.94, &"arbiter_scrape", 0.12, 2)


## 为 [param token] 的移动尾声续约。[param world] 是残骸实际位置。
## [param age] 为战斗秒，[param screen_x] 为有效画面横向坐标。[param leased] 禁止抢占后的再次起播。
## 返回已获准声部的源增益。没有真实移动槽时返回负无穷。
func tail(token: int, kind: StringName, world: Vector2, age: float, screen_x: float, leased: bool) -> float:
	if not is_instance_valid(_spatial):
		return -INF
	var mix: Vector3 = TAIL_MIX[kind] # 真实距离额外进入 R5 限幅多普勒与距离高频滤波。
	var fade: float = 15.0 * smoothstep(0.17, 0.86, age) + 11.0 * smoothstep(0.76, TAIL_EDGE, absf(screen_x * 2.0 - 1.0)) # 听者远离机体时保留连续响度。
	var pitch: float = mix.y * lerpf(1.06, 0.86, smoothstep(0.07, 0.74, age)) # 燃烧与失推动力本身随时间衰减。
	var stream: AudioStream = SHEAR if kind == &"rocket" else FIRE # 同一身份在该段始终持有同一素材。
	var lease: int = _spatial.update_loop(TOKEN_BASE - token, stream, world, mix.x - fade, pitch,
		mix.z + 2.1 * smoothstep(0.18, 0.88, age), true, 0, clampf(age - 0.055, 0.0, 0.20),
		true, not leased) # 申请被拒不占导演名额，已接纳的身份只续约。
	return mix.x - fade if lease > 0 else -INF


## [param token] 的代表声部回到原移动池，由播放器执行短淡出。
func end_tail(token: int) -> void:
	if is_instance_valid(_spatial):
		_spatial.end_loop(TOKEN_BASE - token)
