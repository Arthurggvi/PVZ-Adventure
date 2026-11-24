## 固定移动声源池，选择可闻的跟随对象并回收过期的生命周期。
extends RefCounted

## 单局允许的持续位置声部上限，含移动战斗、拖离和飞艇结构。
const CAPACITY: int = 8
## 竞争槽位时的新老声源分差，避免相邻编队反复替换并重播起音。
const REPLACE_MARGIN: float = 1.5
## 完全离场前停止续约的源音量，单位 dB。
const QUIET_DB: float = -66.0
## 续约返回当前租约，调用方可区分未接纳、沿用和开始。
enum Lease { REJECTED, MAINTAINED, STARTED }
## 同一战场使用的虚拟听者坐标。
const Space := preload("res://scripts/adventure/garden_airship/garden_airship_audio_space.gd")
## 每个可复用移动声部的状态和连续更新。
const Voice := preload("res://scripts/adventure/garden_airship/garden_airship_moving_audio_voice.gd")

## 固定移动槽，一律与局内音频视口一同释放。
var _voices: Array[Voice] = []


## 在 [param audio_viewport] 预创建独立于场上单位数量的移动播放器。
func setup(audio_viewport: Viewport) -> void:
	for index: int in CAPACITY: # 场上动态对象共用八个槽。
		var voice := Voice.new() # 空闲时没有音频解码和跟随更新。
		voice.player = Space.make_player()
		voice.player.name = "Moving%d" % index
		audio_viewport.add_child(voice.player)
		_voices.append(voice)


## 续约 [param key] 的 [param stream]，用 [param space] 把 [param world_position] 和 [param depth] 映射到听者。
## [param volume_db]、[param pitch]、[param doppler] 与 [param priority] 表达声源当前动力和重要性。
## 取得新声部时，[param start_offset] 秒用于错开同一素材的起点。[param one_shot] 禁止在原租期内重新起播。
## [param allow_new] 为否时只续约当前存在的身份，已经播放过的瞬态可据此防止抢占后重播。
func update(key: int, stream: AudioStream, space: Space, world_position: Vector2, volume_db: float,
		pitch: float, depth: float, doppler: bool, priority: int, start_offset: float,
		one_shot: bool = false, allow_new: bool = true) -> Lease:
	var audio_position := space.project(world_position, depth) # 当前实际位置，不沿用上次的声像。
	var distance := audio_position.length() # 用于低成本听感排序和听觉范围判断。
	var selected: Voice # 同生命周期对应的当前播放器。
	var free_voice: Voice # 本次可立即取得的空槽。
	var weakest: Voice # 听感最弱的可替换槽。
	var weakest_score := INF # 本次遍历中当前最弱的排序分。
	var fading := false # 存在待归还的槽时避免为同一批请求连续淘汰多路声音。
	for voice: Voice in _voices: # 只遍历八个播放器，不搜索单位树。
		if voice.player.stream == null:
			if free_voice == null:
				free_voice = voice
		elif voice.key == key:
			selected = voice
			break
		elif voice.releasing:
			fading = true
		else:
			var score := voice.score() # 优先保留当前听起来最明确的声源。
			if score < weakest_score:
				weakest = voice
				weakest_score = score
	var new_voice := selected == null # 已在播放的声部只更新，不重复计入新声部峰值。
	if not new_voice:
		if distance >= Space.HEARING_RANGE or volume_db <= QUIET_DB or selected.player.stream != stream:
			selected.releasing = true
		if selected.releasing:
			return Lease.REJECTED
	else:
		if not allow_new or distance >= Space.HEARING_RANGE - 0.8 or volume_db <= QUIET_DB:
			return Lease.REJECTED
		if free_voice == null:
			if weakest != null and not fading and 8.0 * priority - distance + 0.33 * volume_db > weakest_score + REPLACE_MARGIN:
				weakest.releasing = true
			return Lease.REJECTED
		selected = free_voice
		selected.reserve(key, stream, start_offset, one_shot)
	selected.update(space, world_position, audio_position, depth, volume_db, pitch, doppler, priority)
	return Lease.STARTED if new_voice else Lease.MAINTAINED


## 结束与 [param key] 绑定的真实音频生命周期，残余声音短淡出。
func end(key: int) -> void:
	for voice: Voice in _voices: # 已释放的 ID 不会匹配空槽。
		if voice.player.stream != null and voice.key == key:
			voice.releasing = true
			return


## 用 [param delta] 秒推进有效声部的包络和回收，并返回仍占用的数量。
func advance(delta: float) -> int:
	var count := 0 # 推进包络的遍历同时统计声部，避免每帧重复检查池。
	for voice: Voice in _voices: # 闲置槽不做任何音效参数更新。
		if voice.player.stream != null:
			voice.advance(delta)
			if voice.player.stream != null:
				count += 1
	return count


## 返回已占用的移动槽数，包括淡入或淡出的播放器。
func active_count() -> int:
	var count := 0 # 每个真实生命周期最多占一个播放器。
	for voice: Voice in _voices: # 硬上限，不依赖战斗单位数。
		if voice.player.stream != null:
			count += 1
	return count


## 离场时同步停止仍占用的所有移动声音。
func clear() -> void:
	for voice: Voice in _voices: # 播放器由场景持有，只清理已借出的素材和播放状态。
		if voice.player.stream != null:
			voice.clear()
