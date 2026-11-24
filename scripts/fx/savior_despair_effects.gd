## 没入绝望的光束和散晕。战斗结算提供时间和落点，实景光场负责受光。
extends Node2D

## 光束的移动、触地和吸收均由现有局部红光表现。
const RedLights = preload("res://scripts/fx/savior_despair_lights.gd")
## 四束连续光带的合批部件。
const Ribbon = preload("res://scripts/fx/savior_despair_meteor_mesh.gd")
## 教堂世界光场。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 随祷告抬掌开始的下沉气流。
const DESCENT_SOUND: AudioStream = preload("res://assets/adventure/zombies/savior/savior_despair_descent.wav")
## 在真实触地帧触发的石面撞击和退光残响。
const IMPACT_SOUND: AudioStream = preload("res://assets/adventure/zombies/savior/savior_despair_impact.wav")

## 拥有实际摄像机变换的战场。
var _world: Node2D
## 已出手而尚未触地的束数。零表示回收或已经进入散晕。
var _fall_count := 0
## 仅把成功命中的光束延续到触地收尾。
var _landed_heads := Vector4.ZERO
## 既有结算提交的坠落总战斗秒。
var _fall_seconds: float
## 随光束前沿下移的实际红灯。
var _lights := RedLights.new()
## 共用单一网格表面的四束光。
@onready var _ribbon: Ribbon = $Ribbon
## 单次施法只有一组声像，离开战斗时和画面一起回收。
@onready var _cue: AudioStreamPlayer = $Cue

## [param world] 与 [param field] 同属现有教堂战场。
func configure(world: Node2D, field: LightField) -> void:
	_world = world
	_lights.configure(world, field)

## 从 [param points]、平均格距 [param span] 和 [param seconds] 开始坠落。[param sound] 为全场下坠声。
func begin(points: PackedVector2Array, span: float, seconds: float, sound: bool = true) -> void:
	clear()
	_fall_count = points.size()
	_fall_seconds = seconds
	_ribbon.begin(points, span)
	_lights.begin(points, span)
	advance_fall(0.0)
	if _fall_count > 0 and sound:
		_play_cue(DESCENT_SOUND)

## 用实际下落的 [param elapsed] 推进光束前沿和现场受光。
func advance_fall(elapsed: float) -> void:
	if _fall_count == 0:
		return
	_ribbon.present(elapsed, _fall_seconds)
	_lights.update_fall(_ribbon, clampf(elapsed / _fall_seconds, 0.0, 1.0))

## 同步命中的原光源编号 [param hits]、[param areas] 和每束保护的 [param lamps]、[param glass]。
## [param remainder] 为跨过落地后尚需推进的战斗秒，[param sound] 为本批的全场落地声。
func impact(hits: PackedInt32Array, areas: Array[Rect2], lamps: PackedVector2Array,
		glass: PackedVector2Array, remainder: float, sound: bool = true) -> void:
	if _fall_count == 0:
		return # 结算中的亡语或关卡结束可能已取消呈现。
	if hits.is_empty():
		clear()
		return
	_fall_count = 0
	for hit: int in hits: # 保留有效的同一束光，失效的束在收招时隐藏。
		_landed_heads[hit] = 1.0
	_lights.impact(hits, areas, lamps, glass)
	advance_impact(remainder)
	if sound:
		_play_cue(IMPACT_SOUND)

## [param delta] 从触地后的游戏物理步传入。受暂停和倍速控制。
func advance_impact(delta: float) -> void:
	if _lights.age < 0.0:
		return
	_lights.advance(delta)
	if _lights.age >= 0.0:
		_ribbon.release(_lights.age, _fall_seconds, _landed_heads)
	else:
		_ribbon.clear()

## 用震屏之后的实际画布变换放置光束。所有照明本身已经是世界坐标。
func present() -> void:
	if _ribbon.visible:
		_ribbon.transform = get_global_transform_with_canvas().affine_inverse() * _world.get_canvas_transform()
	if _cue.playing:
		var speed: float = maxf(0.01, Engine.time_scale) # 战斗中切换倍速时让气流和余响继续跟随。
		if not is_equal_approx(_cue.pitch_scale, speed):
			_cue.pitch_scale = speed

## 播放同一施法的 [param stream]。共享战斗音量，触地时接到同一播放器。
func _play_cue(stream: AudioStream) -> void:
	_cue.stop()
	_cue.bus = SoundManager.spatial_sfx_bus()
	_cue.stream = stream
	_cue.pitch_scale = maxf(0.01, Engine.time_scale)
	_cue.play()

## 立即撤销临时光源、光束及其音效。
func clear() -> void:
	_fall_count = 0
	_landed_heads = Vector4.ZERO
	_ribbon.clear()
	_lights.clear()
	_cue.stop()


## 与本轨邻接的战场灯池可能挂在世界根，节点离树时一并释放。
func _exit_tree() -> void:
	_lights.dispose()
