## 同一战场的施法轨道登记。首轨可以重新借用，分身从同一份初始场景独立创建。
extends RefCounted

## 引用干净的场景定义；实际生成第二名施法者时才取出。
const TRACK_SCENE := "res://scenes/fx/savior_spell_track.tscn"
## 每位演员自己的表现通道。
const Tracks = preload("res://scripts/fx/savior_spell_track.gd")
## 战场共享的临时灯和投影。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")

## 随战场保留的第一条轨道。
var _base: Tracks
## 施法者实例编号与各自独立的通道。
var _tracks: Dictionary[int, Tracks] = {}
## 提供棋盘、镜头和真实地面坐标。
var _battle: MainGameManager
## 可空的关卡光场。
var _field: LightField
## 同一战场所有裂隙的绘制层。
var _floor: CanvasLayer

## [param battle]、[param field]、[param floor_layer] 为本局提供战场、光场和地表，[param base] 来自同一轨道场景。
func configure(battle: MainGameManager, field: LightField, floor_layer: CanvasLayer, base: Tracks) -> void:
	_battle = battle
	_field = field
	_floor = floor_layer
	_base = base
	_base.configure(battle, field, floor_layer, true)

## [param id] 重入时取原轨道；额外施法者只复制静态场景资源，互不复用可写状态。
func acquire(id: int) -> Tracks:
	if _tracks.has(id):
		return _tracks[id]
	var tracks: Tracks = _base # 首轨空闲时直接复用。
	if _tracks.values().has(_base):
		var scene := load(TRACK_SCENE) as PackedScene # 同一份场景提供首轨和分身。
		tracks = scene.instantiate() as Tracks
		_base.get_parent().add_child(tracks)
		tracks.configure(_battle, _field, _floor, false)
	_tracks[id] = tracks
	return tracks

## [param id] 退场时归还首轨或销毁对应分身的整条轨道。
func release(id: int) -> void:
	var tracks: Tracks = _tracks.get(id) # 离场与重复清理都可进入。
	_tracks.erase(id)
	if not is_instance_valid(tracks):
		return
	tracks.clear()
	if tracks != _base:
		tracks.queue_free()

## 在 [param delta] 个战斗秒内冷却每位救主的地表余热。
func advance_ground(delta: float) -> void:
	for tracks: Tracks in _tracks.values(): # 同一玩家能同时看见不同分身留下的轨迹。
		tracks.madness.ground.advance(delta)

## [param delta] 为战斗时钟步长，特写时用零步长重投影已冻结的尾迹。
func present(delta: float) -> void:
	for tracks: Tracks in _tracks.values(): # 全部通道依旧使用同一正式镜头。
		tracks.madness.present_frame(delta)
		tracks.despair.present()

## 返回全部活跃裂隙的并集，供现有世界合成作范围裁剪。
func heat_bounds() -> Rect2:
	var combined := Rect2() # 还没有余热时保持关闭。
	for tracks: Tracks in _tracks.values(): # 只合并有内容的网格。
		var hot: Rect2 = tracks.madness.ground.heat_bounds() # 当前施法留下的实际边界。
		if hot.has_area():
			combined = combined.merge(hot) if combined.has_area() else hot
	return combined

## 结束整场时同步清除每个轨道上的短灯和音效。
func clear() -> void:
	for tracks: Tracks in _tracks.values(): # 仍由各施法者负责自己的节点生命周期。
		tracks.clear()
