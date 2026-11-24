## 运输舰从上方进入指定格，在低空定点悬停，并通过货舱逐架放出战斗机。
extends Zombie000Base
class_name Zombie040TransportAirship

## 从屏幕上方降至停稳的动作秒数。
const ENTRY_SECONDS: float = 2.6
## 入场动作中响起制动受力声的进度，略早于机体的最大回弹。
const ENTRY_BRAKE_PROGRESS: float = 0.52
## 机体横向参考宽度，单位为实际棋盘格距。
const HULL_WIDTH_CELLS: float = 4.0
## 224 像素画幅中，悬停和开舱机体可见像素的横向并集宽度。
const HULL_ART_WIDTH: float = 200.0
## 以脚点为原点的素材包围盒，包含开舱、俯仰和几像素的避让余量。
const HULL_BOUNDS := Rect2(-106.0, -181.0, 212.0, 199.0)
## 完整机体在画面上方额外预留的世界像素。
const ENTRY_MARGIN: float = 16.0
## 入场回弹超过终点约 3.7%，预留包围盒向下取整到 4%。
const REBOUND_MARGIN: float = 0.04
## 一次开舱、放飞、关舱动作的秒数，也是组内正常放飞间隔。
const CARGO_SECONDS: float = 3.0
## 舱门第一次离开闭合姿态的动作秒数。
const HATCH_OPEN_SECONDS: float = 0.18
## 在舱门完全打开后放飞的时间，单位为该动作开始后的秒数。
const RELEASE_SECONDS: float = 1.0
## 舱门结束全开停留、开始收回的动作秒数。
const HATCH_CLOSE_SECONDS: float = 2.16
## 一组实际登记的战斗机数量，满员导致的失败不占名额。
const FIGHTERS_PER_BATCH: int = 3
## 第三架到下一架放飞之间的动作秒数，含关舱和下一次开舱。
const BATCH_BREAK_SECONDS: float = 5.0
## 放飞时使用正常战斗机物种及生成规则。
const FIGHTER_KIND := CharacterRegistry.ZombieType.Z034Fighter

## 附件的下落速度与停稳回弹，横轴为归一化入场时间。
@export var entry_travel: Curve
## 机体入场时的附加俯仰角，单位为度。
@export var entry_pitch: Curve
## 击毁后以当前机体帧组装碎块的表现，随运输舰场景按需加载。
@export var breakup_scene: PackedScene

## 悬停和舱门逐帧素材共用同一机体锚点，另叠加入场位移与俯仰。
@onready var _hull: AnimatedSprite2D = $Body/Hull
## 舱门全开时的舱内中心，战斗机从此处开始滑出。
@onready var _cargo_mouth: Marker2D = $Body/CargoMouth
## 舱门张开后的下沿，决定战斗机最先沿斜坡滑下的方向。
@onready var _cargo_ramp_lip: Marker2D = $Body/CargoRampLip
## 跟随机体从远处逼近并持续悬停的同一条旋翼声。
@onready var _rotor_audio: AudioStreamPlayer2D = $Body/Hull/RotorAudio
## 下降制动使机体回弹时的短促受力声。
@onready var _settle_audio: AudioStreamPlayer2D = $Body/Hull/SettleAudio
## 舱门开始展开时，从舱口传出的机械动作声。
@onready var _hatch_open_audio: AudioStreamPlayer2D = $Body/CargoMouth/HatchOpenAudio
## 舱门开始回收时的机械动作与锁舌声。
@onready var _hatch_close_audio: AudioStreamPlayer2D = $Body/CargoMouth/HatchCloseAudio

## 入场时跟踪的真实格子。抵达后保持世界脚点，释放格子引用。
var _landing_cell: PlantCell
## 入场已经占用的世界通道，覆盖甲板移动和停稳回弹。停稳后只占机体范围。
var _descent_reservation: Rect2
## 本次垂直入场的起始世界 Y。
var _entry_start_y: float = 0.0
## 原生屋顶初始化应用的高度，平整棋盘为零。
var _slope_offset: float = 0.0
## 已推进的入场秒数，停稳后固定为 [constant ENTRY_SECONDS]。
var _entry_elapsed: float = 0.0
## 当前放飞周期已推进的动作秒数。
var _cargo_elapsed: float = 0.0
## 周期的总动作秒数。第三架放飞时延长至五秒。
var _cargo_period: float = CARGO_SECONDS
## 当前组已经成功放飞的架数。
var _fighters_launched: int = 0
## 每次真实死亡只转交一次爆炸演出。
var _death_processed: bool = false


## 入树前绑定 [param cell] 和获准的世界通道 [param approach]，同时按该处格距定标。
func configure_landing(cell: PlantCell, approach: Rect2) -> void:
	_landing_cell = cell
	_descent_reservation = approach
	scale = Vector2.ONE * _hull_scale_at(cell)


## 返回落在 [param cell] 的机体从 [param view_top] 进入时所需的世界通道。
## [param slope] 是可选的屋顶坡高，稀疏棋盘沿用平台轨迹和种植脚点。
static func landing_corridor(cell: PlantCell, view_top: float, slope: MainGameSlope) -> Rect2:
	var foot: Vector2 = cell.get_spawn_global_position() # 使用落位格的真实横向中心及纵向脚点。
	if is_instance_valid(slope):
		foot.y += slope.get_all_slope_y(foot.x)
	var hull_scale: float = _hull_scale_at(cell) # 横向可见区域等于当地四格的总宽。
	var bottom_y: float = foot.y # 取动态甲板当前轨迹能到达的最低脚点。
	if cell.board.definition != null:
		var surface: BoardSurface = cell.board.surfaces.get(cell.board_definition.surface_id) # 格子和地形共用所属平台。
		if is_instance_valid(surface):
			bottom_y += surface.downward_travel_room()
	bottom_y += (bottom_y - _entry_y(view_top, foot.y, hull_scale)) * REBOUND_MARGIN
	var box_pos := Vector2(foot.x, bottom_y) + HULL_BOUNDS.position * hull_scale # 回弹时机体的最下范围。
	var box_size: Vector2 = HULL_BOUNDS.size * hull_scale # 与场上的机体使用相同美术裁边。
	var top: float = minf(view_top, box_pos.y) # 通道包含画面上缘至终点机体底部。
	return Rect2(Vector2(box_pos.x, top), Vector2(box_size.x, box_pos.y + box_size.y - top))


## 返回当前机体的世界占用，下降时也保护已锁定的路线，供同帧和后续出怪避让。
func occupied_airspace() -> Rect2:
	var silhouette: Rect2 = get_global_transform() * HULL_BOUNDS # 保留根节点方向和实际缩放。
	return silhouette.merge(_descent_reservation) if is_native_airborne() else silhouette


## 按 [param cell] 的真实格距，将机体等比缩放到四格宽。
static func _hull_scale_at(cell: PlantCell) -> float:
	return cell.board.local_pitch(cell).x * HULL_WIDTH_CELLS / HULL_ART_WIDTH


## [param view_top] 与 [param foot_y] 为世界坐标，[param hull_scale] 为美术到世界的比例。
## 返回完整机体位于画面上缘之外时的起始脚点。
static func _entry_y(view_top: float, foot_y: float, hull_scale: float) -> float:
	return minf(view_top, foot_y) - HULL_BOUNDS.end.y * hull_scale - ENTRY_MARGIN


## 展示实例仅悬停。战斗实例把脚点抬到当前镜头上方，沿选定格的横坐标入场。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()
	_hull.play(&"hover")
	if character_init_type != E_CharacterInitType.IsNorm or not is_instance_valid(_landing_cell):
		set_physics_process(false)
		return
	if is_mini_zombie:
		scale *= _hull_scale_at(_landing_cell) # 小僵尸模式把根缩放设为半身，仍沿用本舰的格距定标。
	_slope_offset = global_position.y - _landing_cell.get_spawn_global_position().y
	var view_top: Vector2 = get_canvas_transform().affine_inverse() * get_viewport_rect().position # 屏幕上边界换算到战场坐标。
	_entry_start_y = _entry_y(view_top.y, global_position.y, global_transform.x.length())
	global_position.y = _entry_start_y
	shadow.hide()


## 定点载具沿用原有重型载具的击退限制，保留地面受击层与生命组件。
func is_vehicle() -> bool:
	return true


## 垂直入场占用原生飞行状态，停稳随后按低空载具参与地面交互。
func is_native_airborne() -> bool:
	return is_instance_valid(_landing_cell) and not is_death


## [param _cells] 为共有风推的格数，[param _flying] 为风力分类。
## 消费三叶草的请求，保持运输舰的脚点、生命和放飞周期。
func handle_blover_wind(_cells: int, _flying: bool) -> bool:
	return true


## 本舰使用自己的垂直入场，不启用横向场外行走加速。
func judge_battlefield_update_speed() -> void:
	pass


## [param delta] 为战斗物理秒。只在本舰所属的正式战斗中推进。
func _physics_process(delta: float) -> void:
	var game: MainGameManager = Global.main_game # 当前活动关卡必须仍持有本舰。
	var spatial: Node = SoundManager.world_audio_for(self) # 有关卡空间池时只使用一个持续旋翼声。
	if is_death or is_queued_for_deletion() or not is_instance_valid(game) \
			or not game.is_ancestor_of(self) or not game.zombie_manager.is_game_running():
		if _rotor_audio.playing:
			_rotor_audio.stop()
		if spatial != null:
			spatial.end_loop(get_instance_id())
		return
	if spatial != null:
		var depth: float = lerpf(7.0, 1.3, clampf(_entry_elapsed / ENTRY_SECONDS, 0.0, 1.0)) # 入场和高度产生不同远近频谱。
		spatial.update_loop(get_instance_id(), _rotor_audio.stream, _rotor_audio.global_position,
			_rotor_audio.volume_db - 4.0, _rotor_audio.pitch_scale, depth, true, 1)
	elif not _rotor_audio.playing:
		_rotor_audio.bus = SoundManager.spatial_sfx_bus()
		_rotor_audio.play()
	if _entry_elapsed < ENTRY_SECONDS:
		_advance_entry(delta, game.zombie_manager)
		return
	if is_hypno:
		_hull.speed_scale = 1.0
		if _hull.animation != &"hover":
			_hull.play(&"hover")
		return
	var rate: float = 0.0 if is_action_suspended() else speed_factor_product() # 冻结及控制停止货舱和召唤进度。
	_hull.speed_scale = rate
	if rate > 0.0:
		_advance_cargo(delta * rate, game.zombie_manager)


## 以 [param delta] 秒推进垂直入场。在移动甲板上，使用 [param manager] 同步最终攻防行。
func _advance_entry(delta: float, manager: ZombieManager) -> void:
	if not is_instance_valid(_landing_cell) or _landing_cell.is_queued_for_deletion():
		retire_from_battle()
		return
	var previous_progress: float = _entry_elapsed / ENTRY_SECONDS # 跨过制动动作时只发声一次。
	_entry_elapsed = minf(_entry_elapsed + delta, ENTRY_SECONDS)
	var progress: float = _entry_elapsed / ENTRY_SECONDS # 供布局关卡共用同一套回弹曲线。
	var foot_y: float = _landing_cell.get_spawn_global_position().y + _slope_offset # 对齐落地瞬间的甲板高度。
	global_position.y = lerpf(_entry_start_y, foot_y, entry_travel.sample(progress))
	_hull.rotation_degrees = entry_pitch.sample(progress)
	# 桨声随下降逼近而渐强，回弹后降低油门，并保留同一循环的播放位置。
	_rotor_audio.volume_db = lerpf(-30.0, 1.5, smoothstep(0.02, 0.46, progress)) \
		- 5.0 * smoothstep(0.55, 1.0, progress)
	_rotor_audio.pitch_scale = lerpf(1.085, 0.985, smoothstep(0.42, 0.96, progress))
	if previous_progress < ENTRY_BRAKE_PROGRESS and progress >= ENTRY_BRAKE_PROGRESS:
		_play_cue(_settle_audio)
	if _entry_elapsed < ENTRY_SECONDS:
		return
	var landing_lane: int = _landing_cell.combat_lane # 移动甲板可能在下降期间已经跨过进攻线。
	if not manager.is_lane_open(landing_lane):
		retire_from_battle()
		return
	curr_zombie_row_type = _landing_cell.get_spawn_terrain_type()
	if landing_lane != lane:
		lane = landing_lane
		signal_lane_update.emit()
		_reparent_with_action_timers(manager.all_zombie_rows[lane])
	_landing_cell = null
	shadow.show()


## 用 [param seconds] 推进同一条货舱和放飞时间轴，经 [param manager] 注册成功才计入组数。
func _advance_cargo(seconds: float, manager: ZombieManager) -> void:
	var previous_elapsed: float = _cargo_elapsed # 货舱声音和放飞共用动作时钟，回绕前判定跨过的动作。
	_cargo_elapsed += seconds
	if previous_elapsed < HATCH_OPEN_SECONDS and _cargo_elapsed >= HATCH_OPEN_SECONDS:
		_play_cue(_hatch_open_audio)
	if previous_elapsed < RELEASE_SECONDS and _cargo_elapsed >= RELEASE_SECONDS and _launch_fighter(manager):
		_fighters_launched += 1
		if _fighters_launched == FIGHTERS_PER_BATCH:
			_fighters_launched = 0
			_cargo_period = BATCH_BREAK_SECONDS
	if previous_elapsed < HATCH_CLOSE_SECONDS and _cargo_elapsed >= HATCH_CLOSE_SECONDS:
		_play_cue(_hatch_close_audio)
	if _cargo_elapsed >= _cargo_period:
		_cargo_elapsed -= _cargo_period
		_cargo_period = CARGO_SECONDS
	if _cargo_elapsed >= CARGO_SECONDS:
		_hull.play(&"hover")
		return
	if _hull.animation != &"cargo":
		_hull.pause()
		_hull.animation = &"cargo"
	var frames: SpriteFrames = _hull.sprite_frames # 货舱帧跟随真实放飞时钟，暂停时停在当前舱门位置。
	_hull.frame = mini(int(_cargo_elapsed * frames.get_animation_speed(&"cargo")),
		frames.get_frame_count(&"cargo") - 1)


## 从 [param cue] 所在的机身位置发声，沿用当前关卡的战斗音效总线。
func _play_cue(cue: AudioStreamPlayer2D) -> void:
	SoundManager.play_attached_sfx(cue, cue.name, 1)


## 优先同行，在水路改走最近的可用陆行。返回是否由 [param manager] 真正登记一架敌机。
func _launch_fighter(manager: ZombieManager) -> bool:
	if manager.available_zombie_slots(1) == 0:
		return false
	var launch_lane: int = lane # 尽量在运输舰所在行接入巡航，水路改用最近陆行。
	if not manager.can_spawn_zombie_in_lane(FIGHTER_KIND, launch_lane):
		launch_lane = -1
		var closest: int = manager.all_zombie_rows.size() # 实际行数是所有相邻行距离的上界。
		for candidate: int in manager.all_zombie_rows.size(): # 只找战斗机原有生成规则支持的行。
			var distance: int = absi(candidate - lane) # 同距保留从上到下遇到的首个合法行。
			if distance < closest and manager.can_spawn_zombie_in_lane(FIGHTER_KIND, candidate):
				launch_lane = candidate
				closest = distance
	if launch_lane < 0:
		return false
	var silhouette: Rect2 = get_global_transform() * HULL_BOUNDS # 大小不同的运输舰沿各自的机头前缘放飞。
	var exit_x: float = silhouette.position.x - Zombie034Fighter.TAIL_CLEARANCE # 巡航开始时尾部已经脱离运输舰。
	var source_row := get_parent() as ZombieRow # 运输舰所在行同时决定穿过货舱时的遮挡层。
	var target_row: ZombieRow = manager.all_zombie_rows[launch_lane] # 新机最终挂在实际巡航行。
	var source_z: int = source_row.z_index + z_index - target_row.z_index - 1 # 刚出舱的机身画在运输舰下方。
	var mouth: Vector2 = _cargo_mouth.global_position # 冻结释放瞬间的舱口坐标，母舰死亡也能完成放飞。
	var ramp_lip: Vector2 = _cargo_ramp_lip.global_position # 同时保留舱门下沿提供的初始滑行方向。
	var initialize := func(zombie: Zombie000Base) -> void: # 通过原生成接口在入树前带上本次出舱姿态。
		(zombie as Zombie034Fighter).configure_cargo_launch(mouth, ramp_lip, source_z)
	return is_instance_valid(manager.create_skill_zombie(FIGHTER_KIND, launch_lane, exit_x, &"", null, initialize))


## 即使被灰烬伤害击毁，也交由机体碎片动画完成演出。
func _preserves_blast_death_animation() -> bool:
	return true


## 立即停止放飞和受击、注销僵尸登记，正常击毁时将爆炸留在当前战斗行。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	set_physics_process(false)
	var spatial: Node = SoundManager.world_audio_for(self) # 在原动力终止时交还声源。
	if spatial != null:
		spatial.end_loop(get_instance_id())
	if not retiring_from_battle:
		_play_breakup()
	super()
	queue_free()


## 冻结当前实际画帧和染色，再把机身与碎块演出交给战斗行独立完成。
func _play_breakup() -> void:
	var row: Node = get_parent() # 特效随当前行和关卡回收，独立于已经死亡的机体。
	if not is_instance_valid(row) or row.is_queued_for_deletion():
		return
	var frame := _hull.sprite_frames.get_frame_texture(_hull.animation, _hull.frame) as AtlasTexture # 保留舱门开合与旋翼姿态。
	var breakup := breakup_scene.instantiate() as TransportAirshipBreakup # 仅保留表现，无受击和战场登记。
	breakup.z_index = z_index + 1
	row.add_child(breakup)
	breakup.global_transform = _hull.global_transform
	var death_visuals: Node = airship_death_presentation() # 仅花园飞艇将原解体外观交给风场。
	var velocity: Vector2 = death_visuals.source_velocity(self) if death_visuals != null else Vector2.ZERO # 沿用击毁前的惯性。
	breakup.begin(frame, modulate * body.modulate * _hull.modulate * _hull.self_modulate, death_visuals, velocity)
