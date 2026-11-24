## 复用本场战斗的闪电芦苇表现，动画、图集和绘制顺序沿用源场景。
extends Node

## 电弧及命中特效的源场景。
const SOURCE: PackedScene = preload("res://scenes/character/plant/lightning_reed_effects.tscn")
## 同一转职的特效材质仍由统一外观入口共享。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_lightning_reed_promotion_art.gd")
## 共享姿态和原生图集矩形绘制的特效实例。
const Playback = preload("res://scripts/character/plant/lightning_reed_effect_playback.gd")
## 依次保留首段、折射和命中片段，空闲实例按片段编号和转职等阶配对。
const CLIPS: Array[StringName] = [&"bolt_default", &"bolt", &"hit"]
## 战斗容器下的唯一池名。
const POOL_NAME: StringName = &"LightningReedEffectPool"
## 各片段跨等阶的空闲上限。先结束的电弧为较长的命中特效留有独立缓存。
const IDLE_LIMITS: Array[int] = [16, 48, 32]
## 原特效的世界绘制层级。
const EFFECT_Z: int = 350

## 源动画采样得到的只读姿态和时间线，可跨战场复用。
static var _templates: Dictionary[StringName, Playback.Clip] = {}
## 同片段、同转职的闲置节点，保持在原容器内以保留动画寻址缓存。
var _idle: Dictionary[Vector2i, Array] = {}
## 按片段统计的空闲数，只限制缓存，所有已触发的效果均完整播放。
var _idle_counts := PackedInt32Array([0, 0, 0])


## 在世界坐标 [param at] 播放 [param clip]，使用 [param rank] 转外观。
## 返回生效的节点，供电弧按实际落点旋转并调整长度。
func play(clip: StringName, at: Vector2, rank: int) -> Node2D:
	var host: Node2D = get_parent() as Node2D # 活动实例仍直接绘制在战场特效容器。
	var key := Vector2i(CLIPS.find(clip), rank) # 同一空闲实例只播放一个片段和色阶。
	var available: Array = _idle.get(key, []) # 缓存可能在阶段清空时被提前摘除。
	var effect: Playback # 本次复用或新建的效果节点。
	while not available.is_empty(): # 跳过已经排队删除的缓存项。
		var candidate: Variant = available.pop_back() # 先摘除登记，避免被同帧再次取出。
		_idle_counts[key.x] -= 1
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			effect = candidate as Playback
			break
	var reused: bool = effect != null # 决定是否需要复位播放器和图层。
	if not reused:
		effect = Playback.new()
		effect.setup(_template(clip), PromotionArt.effect_material(rank))
		effect.z_index = EFFECT_Z
		host.add_child(effect)
	else:
		# 保持与新建实例一致的同层叠绘顺序，包括其他植物后来生成的同层特效。
		host.move_child(effect, -1)
		effect.transform = Transform2D.IDENTITY
		effect.pose = -1
	effect.global_position = at
	var player: AnimationPlayer = effect.player # 原播放器接管关键帧和结束时间。
	if reused:
		# 只重置播放位置。首帧由下次动画更新赋值，与新建实例同一时机显示。
		player.assigned_animation = clip
	else:
		player.animation_finished.connect(_recycle.bind(key, effect))
	player.play(clip)
	effect.show()
	return effect


## [param _clip] 播放结束后，将 [param effect] 缓存到 [param key] 的空闲列表。
func _recycle(_clip: StringName, key: Vector2i, effect: Node2D) -> void:
	if effect.is_queued_for_deletion():
		return
	if _idle_counts[key.x] >= IDLE_LIMITS[key.x]:
		effect.queue_free()
		return
	effect.hide()
	if not _idle.has(key):
		_idle[key] = []
	_idle[key].append(effect)
	_idle_counts[key.x] += 1


## 按 [param clip] 的实际关键帧采样原场景。每次命中只播放姿态编号。
func _template(clip: StringName) -> Playback.Clip:
	if _templates.has(clip):
		return _templates[clip]
	var root: Node2D = SOURCE.instantiate() as Node2D # 仅首次读取一个片段时实例化原场景。
	var source_player: AnimationPlayer = root.get_node(^"AnimationPlayer") as AnimationPlayer # 由原生播放器解析离散键。
	var source: Animation = source_player.get_animation(clip) # 原资源保持只读。
	var rig: Node2D = root.get_node(^"Rig") as Node2D # 与源场景保持相同的矩阵层级和图层顺序。
	var layers: Array[Node] = rig.get_children() # 源精灵在每个采样时点提供姿态。
	var times: Array = _key_times(source) # 只在实际姿态改变时写入动画键。
	var timeline := Animation.new() # 原生播放结束时间及离散姿态驱动轨道。
	timeline.length = source.length
	timeline.step = source.step
	var track: int = timeline.add_track(Animation.TYPE_VALUE) # 单条离散轨道代替每个实例上的全套属性动画。
	timeline.track_set_path(track, ^".:pose")
	timeline.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	var template := Playback.Clip.new() # 只读结果由各个出战实例共用。
	template.rig_transform = rig.transform
	template.library = AnimationLibrary.new()
	template.library.add_animation(clip, timeline)
	root.hide()
	source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	add_child(root)
	source_player.play(clip)
	var previous_time: float = 0.0 # 原生采样器已经走过的游戏秒数。
	var previous: Array = [] # 上一个姿态用于复用没有变化的图层数据。
	for time: float in times: # 源轨道联合时间轴，所有关键帧时间原样进入回放。
		var sample_time: float = minf(time + 0.00001, source.length) # 取刚越过离散键的值，回放仍使用原时间。
		source_player.advance(sample_time - previous_time)
		previous_time = sample_time
		var frame: Array = _sample_layers(layers, previous) # 复制源播放器此时实际得到的绘制数据。
		for index: int in frame.size(): # 尾部从未显示的源图层无需占用实例位置。
			if frame[index] != null:
				template.layer_count = maxi(template.layer_count, index + 1)
		timeline.track_insert_key(track, time, template.poses.size())
		template.poses.append(frame)
		previous = frame
	for frame: Array in template.poses: # 所有帧使用相同的图层下标。
		frame.resize(template.layer_count)
	root.free()
	_templates[clip] = template
	return template


## 返回 [param source] 各离散值轨道的原始时间并集。0 秒包含未显现图层的初始姿态。
static func _key_times(source: Animation) -> Array:
	var keys: Dictionary[float, bool] = {0.0: true} # 每个时间点只采样一次。
	for track: int in source.get_track_count(): # 三种原片段的显隐、图集、位置和颜色轨道均为离散值。
		for key: int in source.track_get_key_count(track): # 保留资源中的精确帧时间。
			var time: float = source.track_get_key_time(track, key) # 片段结束后不再有可见帧。
			if time < source.length:
				keys[time] = true
	var times: Array = keys.keys() # 按实际出现顺序驱动原动画采样。
	times.sort()
	return times


## 按源顺序采样 [param layers]，与 [param previous] 相同的图层复用同一姿态。
static func _sample_layers(layers: Array[Node], previous: Array) -> Array:
	var frame: Array = [] # 当下可见的图层按原 Sprite2D 顺序排列。
	for index: int in layers.size(): # 隐藏图层用 null 保留编号。
		var layer: Sprite2D = layers[index] as Sprite2D # 源播放器已经处理到当前离散键。
		var pose: Playback.LayerPose = null # 未显现的图层不提交矩形。
		if layer.visible and layer.texture != null:
			var last: Playback.LayerPose = previous[index] if not previous.is_empty() else null # 相邻姿态可能重复。
			if last != null and last.texture == layer.texture and last.transform == layer.transform and last.tint == layer.self_modulate:
				pose = last
			else:
				pose = Playback.LayerPose.new()
				pose.texture = layer.texture
				pose.transform = layer.transform
				pose.tint = layer.self_modulate
		frame.append(pose)
	return frame
