## 只消费当前雪山实战角色的位移和落地事件；离场即释放观测，积雪由雪面独立保存。
extends Node
class_name SnowContacts

## 本场角色表现和脚尖批绘，复用本登记器的角色实例。
const Presentation = preload("res://scripts/weather/snow/snow_actor_presentation.gd")
## 明确核实的僵尸 Rig 路径，不扫描未适配的物种。
const ZombieProfiles = preload("res://scripts/weather/snow/snow_zombie_profiles.gd")
## 仅为活跃普通僵尸保留历史；极端密集战斗时优先保留已登记的角色。
const MAX_TRACKS: int = 384
## 每次天气推进允许的步行、落地扬雪与扫掠片段总数。
const MAX_CONTACTS: int = 48

## 所属雪山战斗；准备选卡、结算与阶段切换期间停止写入。
var _game: MainGameManager
## 本关专属地表坐标和压痕接收器。
var _surface: SnowSurface
## 只用实例 ID 记录活跃演员；地表和待提交片段均不持有僵尸对象。
var _tracks: Dictionary[int, SnowContactTrack] = {}
## 轮流选首个采样对象，拥挤时不会总是跳过后进场的僵尸。
var _sampling_start: int = 0
## 脚下细雪集中绘制，出场时随桥接器清理。
var _puffs: SnowContactPuffs

## 绑定 [param game] 的出战管理器与 [param surface]；由所属天气控制器在入树后调用一次。
func configure(game: MainGameManager, surface: SnowSurface) -> void:
	_game = game
	_surface = surface
	_puffs = SnowContactPuffs.new()
	add_child(_puffs)
	_game.zombie_manager.signal_zombie_created.connect(_register)
	for zombie: Zombie000Base in _game.zombie_manager.all_zombies_1d: # 接管装配前已经正式出战的存量。
		_register(zombie)

## [param delta] 为可暂停的战斗秒数，[param presentation] 提供共用色温、风和绘制预算。
func advance(delta: float, presentation: Presentation) -> void:
	if not _is_active():
		for track: SnowContactTrack in _tracks.values(): # 预览与续战不连接上一阶段的步段。
			track.suspend()
		_puffs.advance(delta, presentation.wind)
		return
	var ids: Array = _tracks.keys() # 信号可在相邻帧移除实例，遍历本次的快照。
	var budget: int = MAX_CONTACTS # 超额输入丢弃，本帧历史依旧更新。
	for offset: int in range(ids.size()): # 每个存活角色最多访问一次。
		var id: int = int(ids[(_sampling_start + offset) % ids.size()]) # 轮换消费顺序。
		var zombie: Zombie000Base = instance_from_id(id) as Zombie000Base # 仅本次查询临时获取角色。
		if not _is_live(zombie):
			_forget(id)
			continue
		var track: SnowContactTrack = _tracks[id] # 沿用同一登记提供环境色、扬雪和足缘。
		track.cover.advance(presentation, 0.92)
		var ground: Vector2 = _surface.ground_point(zombie.global_position.x, zombie.lane) # 同一真实坡点供路径和足缘共用。
		budget -= track.sample(zombie, _surface, _puffs, budget, delta, ground)
		track.add_footing(zombie, _surface, presentation.footing, ground)
	if not ids.is_empty():
		_sampling_start = (_sampling_start + 1) % ids.size()
	_puffs.advance(delta, presentation.wind)

## 仅登记管理器确认的 [param zombie]，展示单位和死亡演出均不建立接触历史。
func _register(zombie: Zombie000Base) -> void:
	if not _is_live(zombie) or _tracks.size() >= MAX_TRACKS:
		return
	var id: int = zombie.get_instance_id() # 用值绑定，避免在回调中延长角色寿命。
	if _tracks.has(id):
		return
	var track: SnowContactTrack = SnowContactTrack.new(zombie) # 视觉与路径共用原登记寿命。
	_tracks[id] = track
	ZombieProfiles.bind_shed_sources(zombie, track.cover)
	track.observe(zombie.signal_character_death, _forget.bind(id))
	track.observe(zombie.tree_exiting, _on_exit.bind(id))
	track.observe(zombie.move_component.signal_ground_slide, _capture_slide.bind(id))
	track.observe(zombie.move_component.signal_forced_landed, _capture_landing.bind(id))
	var jump: JumpComponent = zombie.get_node_or_null(^"JumpComponent") as JumpComponent # 撑杆、海豚等原生起跳的共用组件。
	if jump != null:
		# 高坚果拦截可在本次落地协程结束后同步调整最终脚点。
		track.observe(jump.signal_jump_end_end, _capture_landing.bind(id), CONNECT_DEFERRED)
	if zombie is Zombie029LargeFusion:
		track.observe((zombie as Zombie029LargeFusion).rolling_attack.rebound_landed, _capture_landing.bind(id))
	elif zombie is Zombie017Balloon:
		track.observe((zombie as Zombie017Balloon).balloon_landed, _capture_landing.bind(id))
	elif zombie is Zombie021Bungi:
		track.observe((zombie as Zombie021Bungi).signal_bungee_landed, _capture_landing.bind(id))
	elif zombie is Zombie019Pogo:
		track.observe((zombie as Zombie019Pogo).pogo_landed, _capture_landing.bind(id))
	elif zombie is Zombie025Imp:
		track.observe((zombie as Zombie025Imp).throw_landed, _capture_landing.bind(id))

## 保存 [param id] 的真实落地点，统一在下一次天气推进应用预算。
func _capture_landing(id: int) -> void:
	if not _is_active() or not _tracks.has(id):
		return
	var zombie: Zombie000Base = instance_from_id(id) as Zombie000Base # 事件按发生瞬间的坐标投影。
	if _is_live(zombie):
		_tracks[id].capture_landing(zombie, _surface)

## 保存 [param id] 确实发生的水平推移；[param from_x] 和 [param to_x] 均为世界坐标。
func _capture_slide(from_x: float, to_x: float, id: int) -> void:
	if not _is_active() or not _tracks.has(id):
		return
	var zombie: Zombie000Base = instance_from_id(id) as Zombie000Base # 在移动组件完成坡面求解后取脚点。
	if _is_live(zombie):
		_tracks[id].capture_slide(zombie, _surface, from_x, to_x)

## 仅真正离树才释放 [param id]；大蒜换行的临时离树由下一帧观察新行重置。
func _on_exit(id: int) -> void:
	var zombie: Zombie000Base = instance_from_id(id) as Zombie000Base # 换行标记只在重挂时同步设置。
	if is_instance_valid(zombie) and zombie.is_changing_lane:
		return
	_forget(id)

## 删除 [param id] 的路径、天气表现和连接。已提交的连续雪槽继续自然回填。
func _forget(id: int) -> void:
	var track: SnowContactTrack = _tracks.get(id) # 离树和死亡可以同时触发。
	if track == null:
		return
	_tracks.erase(id)
	track.release()

## 当前正在战斗且场景允许推进；暂停期间即使收到外部信号也不会暂存接触。
func _is_active() -> bool:
	return is_instance_valid(_game) and can_process() \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME

## [param zombie] 必须是同一战局的存活实体，退出、预览或仅演出实例不得影响地面。
func _is_live(zombie: Zombie000Base) -> bool:
	return is_instance_valid(zombie) and zombie.is_inside_tree() and not zombie.is_queued_for_deletion() \
		and not zombie.is_death and not zombie.retiring_from_battle and _game.is_ancestor_of(zombie) \
		and zombie.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and not zombie.is_show and is_instance_valid(zombie.move_component) and is_instance_valid(zombie.body)

## 天气单独卸载时还原仍活跃的角色，并解除登记器信号。
func _exit_tree() -> void:
	if is_instance_valid(_game) and is_instance_valid(_game.zombie_manager):
		_game.zombie_manager.signal_zombie_created.disconnect(_register)
	for id: int in _tracks.keys(): # 使用快照，允许释放时删除记录。
		_forget(id)
