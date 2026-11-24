## 花园飞艇定位瞬态的固定预算、邻近合并和短淡出抢占。
extends RefCounted

## 定位瞬态的总上限，包含关键事件专用槽位。
const CAPACITY: int = 32
## 普通战斗允许占用的槽数，留出四个槽给正优先级。
const REGULAR_CAPACITY: int = 28
## 同类近邻瞬态的合并窗口，单位微秒。
const MERGE_USEC: int = 68000
## 合并半径的平方，与战斗世界单位相同；两端发声互不影响。
const MERGE_RADIUS_SQUARED: float = 54.0 * 54.0
## 被更重要事件替换前的淡出时间，单位秒。
const RELEASE_SECONDS: float = 0.035
## 虚拟空间与播放器标定。
const Space := preload("res://scripts/adventure/garden_airship/garden_airship_audio_space.gd")

## 一个可排入淡出槽的瞬态，保留事件发生时的位置。
class Shot:
	## 所用音频素材，排队期间保持存活。
	var stream: AudioStream
	## 用于邻近合并的事件真实世界位置。
	var world_position: Vector2
	## 发声当帧测得的虚拟位置。
	var audio_position: Vector3
	## 调用方要求的源音量，单位 dB。
	var volume_db: float
	## 调用方要求的基础音高倍数。
	var pitch: float
	## 用于判定重复触发的声音类别。
	var family: StringName
	## 事件重要性，正数可以使用保留槽。
	var priority: int
	## 实时时钟中的发声时间，单位微秒。
	var started_usec: int

	## 返回按事件重要性、听者距离及源音量综合排序的分数。
	func score() -> float:
		return 35.0 * priority - audio_position.length() + 0.25 * volume_db


## 固定的瞬态播放器和最多一个候补事件。
class Slot:
	## 此槽的原生位置播放器。
	var player: AudioStreamPlayer3D
	## 当前已提交的事件，用于同类合并和优先级比较。
	var current: Shot
	## 当前声音淡出后播放的事件；为空时没有抢占进行。
	var pending: Shot
	## 抢占淡出还需的时间，单位秒。
	var release_left: float = 0.0


## 关卡进入时创建一次，退出随场景释放的瞬态槽。
var _slots: Array[Slot] = []


## 在纯音频 [param audio_viewport] 下建立固定数量的播放器。
func setup(audio_viewport: Viewport) -> void:
	for index: int in CAPACITY: # 普通事件限制在前二十八槽。
		var slot := Slot.new() # 创建后在本关内复用。
		slot.player = Space.make_player()
		slot.player.name = "Transient%d" % index
		audio_viewport.add_child(slot.player)
		_slots.append(slot)


## 提交 [param stream] 的固定短音，使用 [param world_position] 合并近邻，使用 [param audio_position] 定位。
## [param volume_db] 和 [param pitch] 为源参数，[param family] 区分音效类型，[param priority] 影响抢占。
## 返回是否接纳请求；当预算用尽时优先保留听起来更明显的请求。
func play(stream: AudioStream, world_position: Vector2, audio_position: Vector3,
		volume_db: float, pitch: float, family: StringName, priority: int) -> bool:
	var now := Time.get_ticks_usec() # 实时节流窗口不随关卡倍速加长。
	var limit := CAPACITY if priority > 0 else REGULAR_CAPACITY # 关键瞬态预留容量。
	var free_slot: Slot # 遍历先找空位，再考虑淡出替换。
	var weakest: Slot # 听者最难辨认的可替换声音。
	var weakest_score := INF # 本次遍历中的最低排序分。
	for offset: int in limit: # 关键声音优先从保留区开始找。
		var slot := _slots[(offset + REGULAR_CAPACITY) % CAPACITY if priority > 0 else offset] # 候选槽。
		if _merge_with(slot.current, world_position, family, priority, now) \
				or _merge_with(slot.pending, world_position, family, priority, now):
			return false
		if slot.pending != null:
			continue
		if not slot.player.playing:
			if free_slot == null:
				free_slot = slot
		elif slot.current != null and slot.current.priority <= priority:
			var score := slot.current.score() # 只有较弱的现有事件可被抢占。
			if score < weakest_score:
				weakest = slot
				weakest_score = score
	if free_slot == null and weakest == null:
		return false
	var shot := Shot.new() # 只有通过合并及初始预算后才分配事件。
	shot.stream = stream
	shot.world_position = world_position
	shot.audio_position = audio_position
	shot.volume_db = volume_db
	shot.pitch = pitch
	shot.family = family
	shot.priority = priority
	shot.started_usec = now
	if free_slot != null:
		_start(free_slot, shot)
		return true
	if shot.score() <= weakest_score + 3.0:
		return false
	weakest.pending = shot
	weakest.release_left = RELEASE_SECONDS
	return true


## 推进所有槽的淡出，按 [param delta] 秒释放旧声或启动候补，并返回仍在播放的数量。
func advance(delta: float) -> int:
	var count := 0 # 在执行自然回收的遍历中统计播放量。
	var now := Time.get_ticks_usec() # 同一次回收共享真实时钟的采样。
	for slot: Slot in _slots: # 硬上限内扫描，闲置槽无需设置空间参数。
		if slot.pending == null:
			if slot.player.playing:
				count += 1
			elif slot.current != null:
				slot.player.stream = null
				if now - slot.current.started_usec >= MERGE_USEC:
					slot.current = null
			continue
		slot.release_left -= delta
		if slot.release_left > 0.0 and slot.player.playing:
			slot.player.volume_db = slot.current.volume_db + linear_to_db(slot.release_left / RELEASE_SECONDS)
		else:
			var next := slot.pending # 候补事件仍使用其最初发生的位置。
			slot.pending = null
			_start(slot, next)
		count += 1
	return count


## 返回已启动的瞬态声源数，尚未接管的候补不增加活动声源。
func active_count() -> int:
	var count := 0 # 仅统计正在使用的物理播放器。
	for slot: Slot in _slots: # 所有玩家可听的瞬态槽，包括淡出中的。
		if slot.player.playing:
			count += 1
	return count


## 离场时停止固定声音并清除尚未接管的候补事件。
func clear() -> void:
	for slot: Slot in _slots: # 播放器的节点生命周期由场景承担。
		slot.player.stop()
		slot.player.stream = null
		slot.current = null
		slot.pending = null


## 判断 [param shot] 是否覆盖 [param family] 在 [param world_position]、[param now] 的新事件。
## [param priority] 比既有事件高时允许通过，优先级大于一的提示与冲击独立触发。
func _merge_with(shot: Shot, world_position: Vector2, family: StringName, priority: int, now: int) -> bool:
	return shot != null and priority <= 1 and priority <= shot.priority and shot.family == family \
		and now - shot.started_usec < MERGE_USEC \
		and shot.world_position.distance_squared_to(world_position) < MERGE_RADIUS_SQUARED


## 清除 [param slot] 的旧状态，设置 [param shot] 全部源参数后再启动。
func _start(slot: Slot, shot: Shot) -> void:
	var player := slot.player # 播放器在事件间重复使用。
	player.stop()
	player.position = shot.audio_position
	player.volume_db = shot.volume_db
	player.pitch_scale = shot.pitch
	player.attenuation_filter_cutoff_hz = Space.filter_frequency(shot.audio_position.length())
	player.stream = shot.stream
	slot.current = shot
	player.play()
