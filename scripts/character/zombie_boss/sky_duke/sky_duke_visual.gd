## 苍穹公爵蓝、红两阶段共用的精灵播放器。图集换页只影响表现，动作时钟连续推进。
extends Sprite2D

## [param action] 起手帧已就绪并开始播放，可据此同步战斗表现。
signal action_started(action: StringName)
## [param action] 跨过发令或人物消失时点时发送一次。
signal action_cue(action: StringName)
## [param action] 播完单次时间轴后发送。待机循环不发送。
signal action_finished(action: StringName)

## 时间轴和帧几何的资源类型，不引用页纹理。
const Clip = preload("res://scripts/character/zombie_boss/sky_duke/sky_duke_clip.gd")
## 播放期间的图集页读取和释放。
const PageCache = preload("res://scripts/character/zombie_boss/sky_duke/sky_duke_page_cache.gd")
## 唯一循环姿态。两个命令动作完成后都回到这个姿态。
const IDLE := &"idle"
## 传送离场放完后保持透明，等待上层显式恢复待机。
const TELEPORT_OUT := &"teleport_out"
## 任一阶段只从这四份轻量资源读取动作时序和裁边位置。
const CLIPS := {
	IDLE: preload("res://resources/adventure/animations/sky_duke/idle.tres"),
	&"command": preload("res://resources/adventure/animations/sky_duke/command.tres"),
	&"sky_order": preload("res://resources/adventure/animations/sky_duke/sky_order.tres"),
	TELEPORT_OUT: preload("res://resources/adventure/animations/sky_duke/teleport_out.tres"),
}
## 背景加载按实际使用的颜色、动作和页号构造页路径。
const PAGE_PATH := "res://assets/adventure/zombies/sky_duke/%s_%s_%02d.webp"
## 浮点累计允许的秒数误差，避免恰好落在关键帧时多等一个渲染帧。
const TIME_EPSILON := 0.00000001

## 本实例的页缓存。同一帧只请求当前动作和一个待切入的窗口。
var _pages := PageCache.new()
## 正在播放的动作，尚未入场或已离场时为空。
var _action: StringName = &""
## 等候前两页就绪的动作。首次入树自动启动待机。
var _queued_action: StringName = IDLE
## 战斗提交的目标颜色，供当前时间轴和后续动作读取。
var _phase_art := "blue"
## 正在绘制的颜色，目标颜色准备好后才切换。
var _drawn_art := "blue"
## 本轮动作已经推进的有效秒数，待机循环将其取模到周期内。
var _elapsed := 0.0
## 本体行动倍率。全局暂停和倍速由 Godot 帧时间处理。
var _rate := 1.0


## 排队播放 [param action]，接纳时返回 true。非待机动作从待机起手，传送后可显式请求待机。
func request_action(action: StringName) -> bool:
	if not CLIPS.has(action) or _queued_action != &"":
		return false
	var required_action: StringName = &"" if action == IDLE else IDLE # 只有离场后的空状态可以显式恢复待机。
	if _action != required_action:
		return false
	_queued_action = action
	set_process(true)
	return true


## 为 [param phase] 指定资源颜色，保留当前时间轴与离场状态。
func set_phase(phase: int) -> void:
	_phase_art = "red" if phase >= 2 else "blue"


## 将当前动作速率更新为 [param rate]，0 表示暂停本体的动画时钟。
func set_action_rate(rate: float) -> void:
	_rate = maxf(rate, 0.0)


## 返回当前演出已播放的动作秒数，供场景将传送余波和原画定势对齐。
func action_elapsed() -> float:
	return _elapsed


## 冻结现有画面并放弃尚未播放的图集页，供击败淡出或资源故障时使用。
func stop_playback() -> void:
	set_process(false)
	_queued_action = &""
	_pages.clear()


## [param delta] 为受全局倍速影响的帧间秒数。资源换页不重置时钟或补发旧事件。
func _process(delta: float) -> void:
	var clip: Clip = CLIPS.get(_action) # 未入场时仅准备首个待机窗口。
	var next_time: float = _elapsed + delta * _rate # 先算目标帧，给跳帧后的正确页最高优先级。
	var frame_index := 0 # 未开播时，只需要即将切入动作的头两页。
	var wanted: Array[String] = [] # 当前页与后续一页，其后最多追加一个切换窗口。
	var next_action: StringName = _queued_action # 已排队动作优先于命令收势时的待机预取。
	if clip != null:
		next_time = _limit_time(next_time, clip.duration())
		frame_index = clip.frame_at(next_time)
		wanted = _page_window(_drawn_art, _action, clip, frame_index)
		if next_action == &"" and _action != IDLE and _action != TELEPORT_OUT \
				and clip.duration() - next_time <= float(Clip.FRAMES_PER_PAGE) / Clip.FPS:
			next_action = IDLE
	var incoming: Array[String] = [] # 新颜色同帧窗口，或新动作起手的头两页。
	if next_action != &"":
		incoming = _page_window(_phase_art, next_action, CLIPS[next_action], 0)
	elif clip != null and _phase_art != _drawn_art:
		incoming = _page_window(_phase_art, _action, clip, frame_index)
	wanted.append_array(incoming)
	_pages.update(wanted)
	if _queued_action != &"":
		if _pages.is_ready(incoming):
			_begin_action(_queued_action)
			return
		if _pages.has_failed(incoming):
			_queued_action = &""
			if _action != IDLE:
				stop_playback()
				return
	if clip == null:
		return
	if next_action == &"" and _pages.is_ready(incoming):
		_drawn_art = _phase_art
	_draw_frame(clip, frame_index)
	_advance_time(clip, next_time)


## 将 [param next_time] 限制到以 [param duration] 为周期或终点的动作秒数。
func _limit_time(next_time: float, duration: float) -> float:
	if next_time < duration - TIME_EPSILON:
		return next_time
	return fposmod(maxf(duration, next_time), duration) if _action == IDLE else duration


## 使用已就绪的窗口启动 [param action]，从素材的第零帧开始。
func _begin_action(action: StringName) -> void:
	_action = action
	_queued_action = &""
	_elapsed = 0.0
	_drawn_art = _phase_art
	_draw_frame(CLIPS[action], 0)
	action_started.emit(action)


## 提交 [param clip] 在 [param next_time] 的动作秒数并处理跨越的时间点。
func _advance_time(clip: Clip, next_time: float) -> void:
	var previous: float = _elapsed # 跨越检测允许单帧跳过事件帧，且同一动作只触发一次。
	_elapsed = next_time
	if previous + TIME_EPSILON < clip.cue_seconds and _elapsed + TIME_EPSILON >= clip.cue_seconds:
		action_cue.emit(_action)
	if not is_processing() or is_queued_for_deletion() or previous >= clip.duration() or _elapsed < clip.duration():
		return
	var finished: StringName = _action # 保留已完成动作的身份，供离场后通知外部。
	if finished == TELEPORT_OUT:
		texture = null
		_action = &""
		_pages.clear()
		set_process(false)
	else:
		_queued_action = IDLE
	action_finished.emit(finished)


## 返回 [param art]、[param action] 的 [param clip] 可见帧 [param frame_index] 所需页，再追加下一页。
func _page_window(art: String, action: StringName, clip: Clip, frame_index: int) -> Array[String]:
	var result: Array[String] = [] # 末尾透明帧不对应任何图片页。
	if frame_index >= clip.visible_frame_count:
		return result
	var page: int = clip.page_at(frame_index) # 当前采样页，优先确保其驻留。
	result.append(PAGE_PATH % [art, action, page])
	if (page + 1) * Clip.FRAMES_PER_PAGE < clip.visible_frame_count:
		result.append(PAGE_PATH % [art, action, page + 1])
	elif action == IDLE:
		result.append(PAGE_PATH % [art, action, 0])
	return result


## 绘制 [param clip] 的 [param frame_index]。临时缺页保留上一帧，透明尾帧明确清空。
func _draw_frame(clip: Clip, frame_index: int) -> void:
	if frame_index >= clip.visible_frame_count:
		texture = null
		return
	var path: String = PAGE_PATH % [_drawn_art, _action, clip.page_at(frame_index)] # 使用相同锚点下当前颜色的帧。
	var page: Texture2D = _pages.texture(path) # 仅从已完成的页读取，不在这里同步导入。
	if page == null:
		return
	if texture != page:
		texture = page
	offset = clip.draw_offset
	region_rect = clip.region_at(frame_index)


## 随所属场景卸载图集，迟到的加载结果不会挂回已离树的精灵。
func _exit_tree() -> void:
	_pages.clear()
