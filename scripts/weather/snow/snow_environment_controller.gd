## 单个雪山战场的雪表现。阶段目标由 BattleWeatherDirector 传入。
extends Node
class_name SnowEnvironmentController

## 地形恢复与显现使用同一份雪山行距。
const MountainBoard = preload("res://scripts/adventure/snow_mountain_board.gd")
## 本地视觉风场类型，只随雪山战场装配。
const GustState = preload("res://scripts/weather/snow/snow_gust_state.gd")
## 本场独占的视口雪层，使用独立材质和 HUD 显隐门禁。
const LensOverlay = preload("res://scripts/weather/snow/snow_lens_overlay.gd")
## 植物和正式出战僵尸共用的本场低频气候及脚边画布。
const ActorPresentation = preload("res://scripts/weather/snow/snow_actor_presentation.gd")
## 雪墙横向回绕长度，单位世界像素，与 snow_storm_fields.gdshaderinc 一致。
const WALL_PERIOD: float = 2048.0
## 凯莱赫死亡风雪由现有风场逐步加速至此，单位为世界像素每秒。
const DEPARTURE_PEAK_WIND := Vector2(-2100.0, -56.0)

## 当前雪山静态外观；材质与天气状态均由本局独占。
@export var profile: SnowVisualProfile
## 0 按设备取初始档，1 低档，2 高档。可在本场切换。
@export_enum("自动", "低", "高") var quality_mode: int = 0
## 最后下发的落雪、风、云目标；时间线结束后持续使用。
var _channels := Vector3.ZERO
## 空中可见雪在停止输入后平滑退场，地面积雪直接使用阶段目标。
var _air_channels := Vector3.ZERO
## 首次推进前直接对齐当前阶段，重开噩梦不会短暂呈现普通雪。
var _has_advanced: bool = false
## 当前场景的棋盘与战斗状态，供局部热量事件校验。
var _game: MainGameManager
## 雪面状态及印迹。
var _surface: SnowSurface
## 战斗角色的雪地接触输入。
var _contacts: SnowContacts
## 根据实际植株和精灵更新的覆盖。
var _plants: SnowPlantCover
## 将现有天气样本送到两个登记器，统一颜色、雪屑和接触预算。
var _actors: ActorPresentation
## 当前相机看到的远、中、近雪画面。
var _air: SnowStormRenderer
## 仅在独立极光素材可用时装配，高云是可选层。
var _sky: SnowSkyRenderer
## 仅屏幕空间的雪掠与冷白，和世界雪层使用不同画布。
var _lens: LensOverlay
## 当前预算档位，不参与阶段采样、沉积速度和风场。
var _high_quality: bool = false
## 由当前雪时钟采样的唯一视觉阵风，含各层响应滞后。
var _gust := GustState.new()
## 天幕和世界雪墙共用的归一化平移相位。
var _wall_phase: float = 0.0
## 本场的普通雪底声，进入暴雪时逐渐退去。
var _light_wind: AudioStreamPlayer
## 强风雪底声跟随与视觉共用的阵风前导。
var _blizzard_wind: AudioStreamPlayer
## 死亡落星和消隐期间传入的加剧强度，归一化至 0..1。
var _departure_strength: float = 0.0
## 消隐后收势需要的游戏秒数，零表示还在增强。
var _departure_clear_seconds: float = 0.0
## 已经过的收势游戏秒数，停雪后停在演出终点。
var _departure_age: float = 0.0
## 死亡前的实际雪、风和云强度，由当前天气直接接续。
var _departure_from := Vector3.ZERO
## 死亡前的实际世界风矢量，合流时不会先退到常态风。
var _departure_wind_from := Vector2.ZERO
## 死亡前仍在使用的突发风权重，避免增强时短暂减弱远近雪纹。
var _departure_burst_from: float = 0.0
## 死亡演出所属轮次，负数表示未开始。下一轮会重新跟随天气导演。
var _departure_round: int = -1
## 死亡演出所属冒险阶段配置，同场普通续战也会解除停雪。
var _departure_phase: StagePhaseDefinition

## 以 [param game] 的棋盘和 [param ground] 美术配置一次，可选的 [param sky] 缺失时保留其他雪效果。
func configure(game: MainGameManager, ground: Sprite2D, sky: Sprite2D) -> void:
	if is_instance_valid(_air):
		return
	if profile == null or ground == null or game.board == null or not game.board.configured:
		push_warning("雪山天气缺少外观、地板或已装配棋盘。")
		return
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_game = game
	_high_quality = _wants_high_quality()
	apply_weather_sample(profile.initial_channels)
	_gust.advance(0.0, _air_channels, true)
	_surface = SnowSurface.new()
	add_child(_surface)
	_surface.configure(game, ground, _high_quality)
	_actors = ActorPresentation.new()
	add_child(_actors)
	_actors.configure(profile, _surface, game)
	_contacts = SnowContacts.new()
	add_child(_contacts)
	_contacts.configure(game, _surface)
	_plants = SnowPlantCover.new()
	add_child(_plants)
	_plants.configure(game)
	_air = SnowStormRenderer.new()
	add_child(_air)
	_air.configure(game, ground, profile)
	if profile.has_aurora_layers() and sky != null:
		_sky = SnowSkyRenderer.new()
		add_child(_sky)
		_sky.configure(sky, profile, _surface)
		_surface.set_environment_tint(_sky.advance(0.0, _air_channels, 0.0, _gust.visibility_loss, _wall_phase, _high_quality))
	_lens = LensOverlay.new()
	add_child(_lens)
	_lens.configure(game, profile)
	_light_wind = _create_wind_player(profile.wind_loop, &"LightSnowWind")
	_blizzard_wind = _create_wind_player(profile.blizzard_wind_loop, &"BlizzardWind")
	# 从首帧开始使用当前风向及画质，仍等引擎提供游戏时间后再移动。
	var initial_wind: Vector2 = get_visual_wind() # 与首帧及正常推进共用相同的风场。
	var initial_fall: float = lerpf(profile.fall_speed.x, profile.fall_speed.y, _channels.x) # 常态落雪速度。
	_air.advance(0.0, _air_channels, initial_wind, initial_fall, _world_weather(), _high_quality)
	EventBus.subscribe("jalapeno_bomb_effect", _on_visual_heat)
	var mountain := game.board.definition as MountainBoard # 轮间恢复直接使用已经沉降的布局。
	if mountain != null and mountain.sunk_rows > 0:
		set_board_descent(MountainBoard.descent(mountain.sunk_rows), MountainBoard.rim_height(game.board.lanes.size()))
		game.main_game_slope.limit_collision_rows(game.board.lanes.size())

## 将雪面、天空雪线和实景坡面同时按 [param descent] 降低，[param rim] 为当前近端断面。
func set_board_descent(descent: float, rim: float) -> void:
	if not is_instance_valid(_surface):
		return
	_surface.set_board_descent(descent, rim)
	if is_instance_valid(_sky):
		_sky.set_board_descent(descent)
	if is_instance_valid(_game.main_game_slope):
		_game.main_game_slope.position.y = descent
	var ridge_row: Array[PlantCell] = _game.board.row_cells(0) # 远雾的低层锚点也随真实棋盘移动。
	if not ridge_row.is_empty():
		_air.set_ridge_height(ridge_row.back().get_global_rect().position.y)

## 为 [param target] 绑定远景人物共用的真实雪线与山体轮廓。
func bind_sky_subject(target: ShaderMaterial) -> void:
	if not is_instance_valid(_surface):
		return
	_surface.bind_ground_ridge(target)
	if is_instance_valid(_game.main_game_slope):
		target.set_shader_parameter(&"snow_ridge_descent", _game.main_game_slope.position.y)
	var sky: Sprite2D = _game.background_manager.environment_sky # 山体遮挡贴图与天幕使用同一坐标。
	if not is_instance_valid(sky):
		return
	var sky_bounds: Rect2 = sky.get_global_transform() * sky.get_rect() # 天幕的世界画幅。
	target.set_shader_parameter(&"sky_bounds", Vector4(sky_bounds.position.x, sky_bounds.position.y,
		sky_bounds.size.x, sky_bounds.size.y))
	target.set_shader_parameter(&"mountains", profile.mountains)
	target.set_shader_parameter(&"has_mountains", profile.mountains != null)

## 返回远景当前风雪的能见度、世界雪墙位移和极光亮度，供中间画布的材质取样。
func sky_subject_weather() -> Vector3:
	return Vector3(_world_weather().x, _wall_phase, _sky.light_level() if is_instance_valid(_sky) else 0.0)

## 应用 [param channels] 的落雪、风和云量，非法输入沿用此前目标。
func apply_weather_sample(channels: Vector3) -> void:
	if channels.is_finite():
		_channels = channels.clamp(Vector3.ZERO, Vector3.ONE)
		if not _has_advanced:
			_air_channels = _channels

## 触发本场的视觉狂风；[param velocity] 为世界像素/秒，[param duration] 为游戏秒。
## 远近雪、地吹雪和风声共用包络，停止后自然回到当前天气。
## [param build_seconds] 为渐强的游戏秒数，零值让狂风立即进入峰值。
func play_wind_burst(velocity: Vector2, duration: float, build_seconds: float = 0.0) -> void:
	# 此轮雪尾独占最后的阵风，下一阶段由原风场重新采样。
	if _departure_is_current():
		return
	_gust.play_burst(velocity, duration, build_seconds)

## 在死亡首帧接管当前轮次和冒险阶段的雪势，由落星演出驱动增强。
## 原时间轴采样及已经形成的积雪继续保留。
func begin_departure_storm() -> void:
	if not is_instance_valid(_game) or _game.is_queued_for_deletion():
		return
	_departure_from = _air_channels
	_departure_wind_from = get_visual_wind()
	_departure_burst_from = _gust.burst_strength
	_departure_round = _game.curr_game_round
	_departure_phase = AdventureSession.get_active_phase(_game.game_para)
	_departure_strength = 0.0
	_departure_clear_seconds = 0.0
	_departure_age = 0.0

## 以 [param strength] 提升实际世界风和雪墙，收势开始后不再增强。
func set_departure_storm_strength(strength: float) -> void:
	if not _departure_is_current() or _departure_clear_seconds > 0.0 or not is_finite(strength):
		return
	_departure_strength = maxf(_departure_strength, clampf(strength, 0.0, 1.0))
	_air_channels = _departure_from.lerp(Vector3.ONE, _departure_strength)
	_gust.burst_strength = _departure_burst_strength()

## 从当前风雪强度起，在 [param clear_seconds] 个游戏秒内停雪。
func clear_departure_storm(clear_seconds: float) -> void:
	if _departure_clear_seconds == 0.0 and _departure_is_current() and is_finite(clear_seconds) and clear_seconds > 0.0:
		_departure_clear_seconds = clear_seconds

## 返回本轮死亡暴雪已清场且自然降雪被压至零，下一阶段恢复原天气输入。
func is_snow_cleared() -> bool:
	return (_departure_clear_seconds > 0.0 and _departure_age >= _departure_clear_seconds
		and _departure_is_current())

## 确认死亡暴雪仍属于实际阶段，只在启用演出后查询冒险阶段。
func _departure_is_current() -> bool:
	return _departure_round >= 0 and is_instance_valid(_game) and not _game.is_queued_for_deletion() \
		and _game.curr_game_round == _departure_round \
		and AdventureSession.get_active_phase(_game.game_para) == _departure_phase

## 返回收势段的剩余风雪比例，落星和消隐期间保持 1。
func _departure_remainder() -> float:
	if _departure_clear_seconds == 0.0:
		return 1.0
	return 1.0 - smoothstep(0.0, _departure_clear_seconds, _departure_age)

## 返回死亡演出统一驱动的雪墙、镜头雪和风声的阵风权重。
func _departure_burst_strength() -> float:
	return lerpf(_departure_burst_from, 1.0, _departure_strength) * _departure_remainder()

## [param delta] 为限制过的战斗秒数。演出中直接驱动空中通道，跨阶段时交还平滑控制。
func _advance_departure(delta: float) -> bool:
	if _departure_round < 0:
		return false
	if not _departure_is_current():
		_departure_round = -1
		_departure_clear_seconds = 0.0
		_departure_phase = null
		_gust = GustState.new()
		return false
	_departure_age = minf(_departure_clear_seconds, _departure_age + delta)
	_air_channels = _departure_from.lerp(Vector3.ONE, _departure_strength) * _departure_remainder()
	return true

## 用 [param delta] 推进局部表现，限制单帧步长避免断点或切后台后追赶。
func _process(delta: float) -> void:
	if not is_instance_valid(_air):
		return
	var step: float = clampf(delta, 0.0, 0.15) # 不读取角色局部速度或现实时间。
	var high_quality: bool = _wants_high_quality() # 可运行中切档，保留此前积雪与印迹。
	if high_quality != _high_quality:
		_high_quality = high_quality
		_surface.set_quality(_high_quality)
	var departure: bool = _advance_departure(step) # 落星、消隐与停雪使用同一次天气接管。
	if not departure:
		_air_channels = _air_channels.lerp(_channels, 1.0 - exp(-3.2 * step))
	_gust.advance(step, _air_channels, not _has_advanced)
	if departure:
		_gust.burst_strength = _departure_burst_strength()
	_has_advanced = true
	var wind: Vector2 = get_visual_wind() # 所有雪层与相邻表现共用实际世界方向与风速。
	var fall: float = lerpf(profile.fall_speed.x, profile.fall_speed.y, _air_channels.x) # 落速单独随降雪过渡。
	fall *= lerpf(1.0, 0.12, _gust.burst_strength)
	_update_wind_audio()
	_wall_phase = fposmod(_wall_phase + wind.x * step * 0.55 / WALL_PERIOD, 1.0)
	var world_weather: Vector4 = _world_weather() # 角色与前后雪层消费同一个天气样本。
	_air.advance(step, _air_channels, wind, fall, world_weather, _high_quality, _gust.burst_strength)
	_lens.advance(step, wind, maxf(_gust.lens_whiteout, _gust.burst_strength * 0.85), _gust.hud_frost, _high_quality)
	var aurora: Color = Color.TRANSPARENT # 缺独立极光层时使用零环境响应。
	if is_instance_valid(_sky):
		# 天空共享先到的远景遮挡，极光保持自己的慢速相位。
		aurora = _sky.advance(step, _air_channels, wind.x, world_weather.x, _wall_phase, _high_quality)
		_surface.set_environment_tint(aurora)
	var surface_channels: Vector3 = _air_channels if departure else _channels # 停雪后不再补入新雪，现有地面采样继续。
	var surface_wind: float = lerpf(surface_channels.y, 1.0, _gust.gust_pulse) # 强暴雪仍保留阵风余量。
	_surface.advance(step, surface_channels, surface_wind, Vector2(world_weather.x, _wall_phase))
	_actors.begin_step(step, surface_channels.x, wind, world_weather, aurora, _high_quality)
	_surface.begin_contact_step()
	_plants.advance(step, _actors)
	_contacts.advance(step, _actors)
	_surface.end_contact_step()
	_actors.finish_step(step)

## 用 [param stream] 创建使用现有 SFX 总线的风声播放器，[param player_name] 便于在场景树识别。
## 空素材返回 null。首个天气采样后按实际阶段启动，播放器继承本场暂停。
func _create_wind_player(stream: AudioStream, player_name: StringName) -> AudioStreamPlayer:
	if stream == null:
		return null
	var player := AudioStreamPlayer.new() # 本局独占的循环播放状态。
	player.name = player_name
	player.stream = stream
	player.bus = AudioServer.get_bus_name(SoundManagerClass.Bus.SFX)
	add_child(player)
	return player

## 在极光和雪墙更新前用同一场阵风调整风声。稳定阶段只播放有增益的音轨。
func _update_wind_audio() -> void:
	var blend: float = maxf(_gust.storm_strength, _gust.burst_strength) if _blizzard_wind != null else 0.0 # 暴雪音轨的等功率权重。
	var wind_level: float = maxf(_air_channels.y, _gust.burst_strength) # 演出可以在环境弱风时掀起短促的风声。
	var pulse: float = maxf(_gust.gust_pulse, _gust.burst_strength) # 自然阵风和外部狂风共用音量上限。
	var light_gain: float = smoothstep(0.0, 0.19, wind_level) * sqrt(1.0 - blend) \
		* (0.37 + pulse * 0.17) # 小雪保持轻声，弱风退去时渐静。
	var blizzard_gain: float = wind_level * sqrt(blend) \
		* (0.54 + pulse * 0.30) # 阵风会把狂风声先推高，峰值仍留混音余量。
	_mix_wind_player(_light_wind, light_gain)
	_mix_wind_player(_blizzard_wind, blizzard_gain)

## 把 [param gain] 线性音量写入 [param player]。先设增益再播放，静音侧不持续解码。
func _mix_wind_player(player: AudioStreamPlayer, gain: float) -> void:
	if player == null:
		return
	if gain <= 0.001:
		if player.playing:
			player.stop()
		return
	player.volume_db = linear_to_db(gain)
	if not player.playing:
		player.play()

## 返回世界像素每秒的表现风，供雪层及同场演出采样。未配置时为零。
## 自然阵风放大配置风速，短时狂风可改变风向。查询不推进天气。
func get_visual_wind() -> Vector2:
	if profile == null:
		return Vector2.ZERO
	if _departure_is_current():
		return _departure_wind_from.lerp(DEPARTURE_PEAK_WIND, _departure_strength) * _departure_remainder()
	var speed: float = lerpf(profile.wind_speed.x, profile.wind_speed.y, _air_channels.y) # 阶段基础速度。
	var ambient: Vector2 = profile.wind_direction.normalized() * (speed * (1.0 + _gust.gust_pulse * 0.52)) # 常态方向与速度。
	return ambient.lerp(_gust.burst_velocity, _gust.burst_strength)

## 按能见度损失、阵风、地吹雪、雪墙位移打包世界层的归一化输入。
func _world_weather() -> Vector4:
	var tail: float = 1.0 # 停雪最后一拍同时退掉环境弹簧尚未消尽的雾和地吹雪。
	if _departure_clear_seconds > 0.0:
		tail -= smoothstep(maxf(0.0, _departure_clear_seconds - 1.45), _departure_clear_seconds, _departure_age)
	return Vector4(_gust.visibility_loss * tail, maxf(_gust.gust_pulse, _gust.burst_strength) * tail,
		maxf(_gust.ground_drift, _gust.burst_strength * 0.84) * tail, _wall_phase)

## 自动档以移动端低预算为起点，不把平台作为设备性能结论。
func _wants_high_quality() -> bool:
	return quality_mode == 2 or (quality_mode == 0 and not OS.has_feature("mobile"))

## 原生火爆辣椒的表现事件提供 [param lane]；至多更新实际行上的格子雪量。
func _on_visual_heat(lane: int) -> void:
	if not is_instance_valid(_game) or _game != get_tree().current_scene or get_tree().paused \
			or _game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return
	for cell: PlantCell in _game.board.row_cells(lane): # 一次点火只处理这个攻击行。
		var bounds: Rect2 = cell.get_global_rect() # 当前下方地块的世界范围。
		var point: Vector2 = _surface.ground_point(bounds.get_center().x, lane) # 使用真实坡面，凉却由雪面状态推进。
		if point.is_finite():
			_surface.apply_visual_heat(point, bounds.size * Vector2(1.04, 0.42), 0.70)

## 卸载时解除本场声音、天空和雪面之外唯一全局事件连接。
func _exit_tree() -> void:
	if _game != null:
		EventBus.unsubscribe("jalapeno_bomb_effect", _on_visual_heat)
