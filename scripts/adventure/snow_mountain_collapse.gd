## 边境雪山的三次沉降。裂离的地块与实际占用一起落下，落出视口才退去行索引。
extends Node2D

## 一拍已经提交，[param remaining] 是仍可交互和出怪的实际行数。
signal row_sunk(remaining: int)
## 最后一拍稳住现场后，交给凯莱赫继续显现。
signal finished

## 地块与坡面使用同一份实测行距。
const Mountain = preload("res://scripts/adventure/snow_mountain_board.gd")
## 每拍沿格带开裂的演出秒数。
const CRACK: float = 0.36
## 每拍地块坠出视口的演出秒数。
const FALL: float = 0.87
## 相邻两次沉降之间留给玩家观察的演出秒数。
const REST: float = 0.61
## 冰层破裂、岩层撞击和低频余震在每一拍断开时同帧起音。
const QUAKE_PATH: String = "res://resources/adventure/audio/cailleach_terrain_quake.ogg"

## 本次实际所属战斗。
var _game: MainGameManager
## 发动沉降的僵王，由演出把它移入仍存在的行。
var _actor: ZB000Base
## 所属雪场的原有风雪与雪线控制。
var _weather: SnowEnvironmentController
## 本局的实际棋盘，提交后移去下沉的地址。
var _board: BoardRuntime
## 本局独占的雪山定义，记录已经移去的行数。
var _layout: Mountain
## 保存原有占用的实体种植平台。
var _surface: BoardSurface
## 独立深度的地板精灵，裂离板块取自同一纹理和材质。
var _ground: Sprite2D
## 实际僵尸行的共同父节点，随平台整体移动。
var _zombies: Node2D
## 持有实际清洁车和补车位置的管理器。
var _mowers: GIM_LawnMover
## 当前已开始地块沉降。
var _playing: bool = false
## 当前一拍已用的演出秒。
var _age: float = 0.0
## 本拍开始时种植平台在战场中的位置。
var _surface_from: Vector2
## 本拍开始时僵尸行容器在战场中的位置。
var _zombies_from: Vector2
## 本拍开始时清洁车容器在战场中的位置。
var _mowers_from: Vector2
## 裂口相对原始地面的纵深，单位为世界像素。
var _rim: float
## 让裂离地块落到视口下所需的额外世界像素距离。
var _fall_distance: float
## 当前要消失的行号，尚未开始时为 -1。
var _lane: int = -1
## 随本拍地块落下的实景格子。
var _cells: Array[PlantCell] = []
## 本行格子原来的局部纵坐标，与 [member _cells] 对齐。
var _cell_ys := PackedFloat32Array()
## 随地块落下的实际僵尸行节点。
var _falling_row: Node2D
## 本拍僵尸行开裂前相对容器的纵坐标。
var _row_y: float
## 陪同退去的清洁车及其坠落前坐标。
var _falling_mowers: Dictionary[Node2D, float] = {}
## 脱离原地板的取样精灵，落出屏幕后释放。
var _slab: Sprite2D
## 本拍脱落精灵开裂前在战场中的位置。
var _slab_from: Vector2
## 本拍地鸣由演出持有，退出会停止残余音轨。
var _quake: AudioStreamPlayer
## 在震动期间保持远处天幕的构图。
var _sky: CanvasLayer
## 远处天幕未锁定时的变换。
var _sky_transform: Transform2D
## 远处天幕未锁定时是否跟随视口。
var _sky_follows: bool
## 裂线的世界点，用于原有雪雾和冰屑。
var _lip: Array[Vector2] = []

## 普通雪山只保留节点入口。收到妇人退场完成通知后才开始处理。
func _ready() -> void:
	z_index = 330
	set_process(false)

## [param actor] 为发动沉降的僵王。返回 true 表示随后会发出 [signal finished]。
func begin(actor: ZB000Base) -> bool:
	if _playing:
		return false
	_game = get_parent() as MainGameManager
	_board = _game.board
	_layout = _board.definition as Mountain
	_weather = _game.background_manager.snow_environment
	_ground = _game.background_manager.background
	if (_layout == null or _layout.sunk_rows >= Mountain.COLLAPSE_ROWS
			or not is_instance_valid(_weather) or not _ground.material is ShaderMaterial
			or _board.surfaces.size() != 1 or not _board.allows_mutation()):
		return false
	_actor = actor
	_surface = _board.surfaces.values()[0]
	_zombies = _game.zombie_manager.zombies_root
	_mowers = _game.game_item_manager.gim_lawn_mover
	_playing = true
	_quake = AudioStreamPlayer.new()
	_quake.stream = load(QUAKE_PATH) as AudioStream
	_quake.bus = SoundManager.spatial_sfx_bus(SoundManagerClass.SFXSpace.COMBAT)
	add_child(_quake)
	var sky_sprite: Sprite2D = _game.background_manager.environment_sky # 天幕比场地远，不与雪坡一同剧烈位移。
	if is_instance_valid(sky_sprite):
		_sky = sky_sprite.get_parent() as CanvasLayer
		if is_instance_valid(_sky):
			_sky_transform = _sky.transform
			_sky_follows = _sky.follow_viewport_enabled
			var projected: Transform2D = _sky.get_final_transform() # 保持原来的屏幕构图，也给震动留出天空覆盖。
			_sky.follow_viewport_enabled = false
			_sky.transform = projected
	set_process(true)
	_prepare_row()
	return true

## 读取仍在场的最后一行，在裂开之前留出完整的格带。
func _prepare_row() -> void:
	_age = 0.0
	_lane = _board.lanes.size() - 1
	_rim = Mountain.rim_height(_lane)
	_cells = _board.row_cells(_lane)
	_surface_from = _surface.position
	_zombies_from = _zombies.position
	_mowers_from = _mowers.lawn_movers.position
	var row_node: Node = _game.zombie_manager.all_zombie_rows[_lane] # 雪山装配器的攻击行是 Node2D。
	_falling_row = row_node as Node2D
	_row_y = _falling_row.position.y
	_falling_mowers.clear()
	_cell_ys.clear()
	_lip.clear()
	for cell: PlantCell in _cells: # 使用真正的格子横坐标来布置一排断裂雪屑。
		_cell_ys.append(cell.position.y)
		var x: float = cell.get_global_rect().get_center().x # 坡面脚点的实际横坐标。
		var y: float = _rim + Mountain.descent(_layout.sunk_rows) + _game.main_game_slope.get_all_slope_y(x) # 亲近侧雪带的上沿。
		_lip.append(Vector2(x, y))
	var to_world: Transform2D = _game.get_canvas_transform().affine_inverse() # 下缘随真实视口分辨率而变。
	var screen_floor: float = (to_world * get_viewport_rect().end).y # 屏幕最底端对应的世界 Y。
	_fall_distance = maxf(180.0, screen_floor + 125.0 - _rim - Mountain.descent(_layout.sunk_rows + 1))
	queue_redraw()

## [param delta] 推进正常速度的演出秒。落下、停顿和交接采用分开的时间点。
func _process(delta: float) -> void:
	var previous: float = _age # 用穿过关键帧判定，避免同一次震动重复触发。
	_age += minf(delta / maxf(0.01, Engine.time_scale), 0.10)
	if previous < CRACK and _age >= CRACK:
		_break_floor()
	if is_instance_valid(_slab):
		var depth: float = clampf((_age - CRACK) / FALL, 0.0, 1.0) # 先松动，板块分离后加速落下。
		_lower_floor(smoothstep(0.0, 0.89, depth), pow(depth, 1.76))
		if depth >= 1.0 and not _commit_row():
			_finish_presentation()
			finished.emit()
			return
	queue_redraw()
	if _age < CRACK + FALL + REST:
		return
	if _layout.sunk_rows < Mountain.COLLAPSE_ROWS:
		_prepare_row()
	else:
		_finish_presentation()
		finished.emit()

## 从当前雪地复制一个共享纹理的裂离板块，地震与画面冲击同时发生。
func _break_floor() -> void:
	_isolate_falling_row()
	_slab = Sprite2D.new()
	_slab.texture = _ground.texture
	_slab.centered = _ground.centered
	_slab.transform = _ground.transform
	_slab.z_index = _ground.z_index + 1
	_slab.material = _ground.material.duplicate()
	(_slab.material as ShaderMaterial).set_shader_parameter(&"snow_slab_top", _rim)
	_ground.get_parent().add_child(_slab)
	_slab_from = _slab.position
	var force: float = 1.0 + _layout.sunk_rows * 0.09 # 三次沉降的峰值逐步增大。
	_game.camera_2d.shake_once(Vector2(19.0, 29.0) * force, 0.58, 13.4)
	_quake.pitch_scale = 1.04 - _layout.sunk_rows * 0.07
	_quake.volume_db = -2.0 + _layout.sunk_rows * 0.8
	_quake.play()
	_weather.play_wind_burst(Vector2(-640.0, 148.0), 1.0, 0.15)

## 仅将脱落行移出战斗交互，节点保留原画直到越过下边界。
func _isolate_falling_row() -> void:
	_game.zombie_manager.close_falling_lane(_lane)
	for cell: PlantCell in _cells: # 该行只作为可见的坠落地块保留。
		cell.set_planting_block(&"terrain_collapse", true)
		cell.can_common_zombie = false
		cell.process_mode = Node.PROCESS_MODE_DISABLED
		for plant: Plant000Base in cell.living_plants(): # 逻辑索敌也同步失去受击资格。
			plant.is_can_death_language = false
			plant.hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	for child: Node in _mowers.lawn_movers.get_children(): # 已经启动的车一起退出当前行的交互。
		var mower := child as LawnMover # 视觉残影没有真实行号。
		if mower != null and mower.lane == _lane:
			_falling_mowers[mower] = mower.position.y
			mower.process_mode = Node.PROCESS_MODE_DISABLED

## 把保留行当前的普通弹道平移 [param shift]，其他类型的实景效果继续自行推进。
func _shift_bullets(shift: float) -> void:
	for transient: Node in _game.bullets.get_children(): # 普通弹道是空中效果层的直接子节点。
		var shot := transient as Bullet000NormBase # 绝对坐标的抛物线用其专属平移实现。
		if shot == null or shot.is_queued_for_deletion():
			continue
		if shot.lane == _lane and (shot.is_activate_lane or shot is Bullet000ParabolaBase):
			shot.queue_free()
		elif shot.lane >= 0 and shot.lane < _lane:
			shot.translate_with_board(Vector2(0.0, shift))

## [param slide] 是保留雪坡的位移比例，[param drop] 是脱离板块的额外落差。
func _lower_floor(slide: float, drop: float) -> void:
	var shift: float = Mountain.row_stride() * slide # 其余格子与真实出怪标记同幅下降。
	var falling: float = _fall_distance * drop # 前排离开原平台后的额外位移。
	var offset: float = Mountain.descent(_layout.sunk_rows) + shift # 天空和雪地使用同一绝对值。
	var live_shift: float = _surface_from.y + shift - _surface.position.y # 已发射弹只补本帧实际下沉量。
	_shift_bullets(live_shift)
	_surface.move_to(_surface_from + Vector2(0.0, shift), 0.0)
	_zombies.position = _zombies_from + Vector2(0.0, shift)
	_mowers.lawn_movers.position = _mowers_from + Vector2(0.0, shift)
	_mowers.lower_spawn_positions(live_shift)
	_weather.set_board_descent(offset, _rim)
	var fall_step: float = _row_y + falling - _falling_row.position.y # 脱落行本帧在整个平台下降之外的额外落差。
	_falling_row.position.y = _row_y + falling
	for road: IceRoad in _game.zombie_manager.all_ice_roads[_lane]: # 冰道先随背景下降，再跟上脱落板块。
		if is_instance_valid(road) and not road.is_queued_for_deletion():
			road.global_position.y += fall_step
			road.z_index = _slab.z_index - _ground.z_index + 1 # 地面下沉时冰道仍画在脱落板块上方。
	for index: int in range(_cells.size()): # 植株、承托物及冰壳仍挂在各自真实格子上。
		_cells[index].position.y = _cell_ys[index] + falling
	for mower: Node2D in _falling_mowers: # 保留现有清洁车原画直到越过屏幕。
		if is_instance_valid(mower):
			mower.position.y = _falling_mowers[mower] + falling
	_slab.position = _slab_from + Vector2(0.0, shift + falling)
	(_slab.material as ShaderMaterial).set_shader_parameter(&"snow_ridge_descent", offset + falling)

## 所有属于旧行的实体先完成死亡和清理，再把行号上限推进到新断面。
func _commit_row() -> bool:
	# 取下处决后不会再继续查询的旧板块。
	_slab.hide()
	_slab.queue_free()
	_slab = null
	if not _board.retire_last_lane():
		return false
	_game.zombie_manager.retire_last_battle_row(_actor)
	_mowers.retire_last_lane(_lane)
	_layout.set_sunk_rows(_layout.sunk_rows + 1)
	for lane: BoardLaneDefinition in _board.lanes: # 让新的存档和补车点仍能重建当前实景位置。
		lane.spawn_position.y += Mountain.row_stride()
		lane.mower_position.y += Mountain.row_stride()
	_game.main_game_slope.limit_collision_rows(_board.lanes.size())
	if is_instance_valid(_actor) and not _actor.is_death:
		_actor.lane = clampi(_actor.lane, 0, _board.lanes.size() - 1)
		var marker: Marker2D = _game.zombie_manager.all_zombie_rows[_actor.lane].zombie_create_position # 更新二阶段实际可受击行。
		_actor.global_position.y = marker.global_position.y + _game.main_game_slope.get_all_slope_y(_actor.global_position.x)
		_actor.set_boss_depth(_actor.lane)
	_game.plant_cell_manager.rebuild_plant_counts()
	_board.plant_relocated.emit()
	EventBus.push_event("update_card_purple_sun_cost")
	_cells.clear()
	row_sunk.emit(_board.lanes.size())
	return true

## 为实际断面的格带画开裂提示和轻量雪屑。落点轮廓来自原地块多边形。
func _draw() -> void:
	if not _playing or _lane < 0:
		return
	var t: float = clampf((_age - CRACK) / FALL, 0.0, 1.0) # 坠落仅在原格带上绘制轮廓。
	var energy: float = 1.0 - smoothstep(0.60, 0.99, t) # 裂纹随原格带落出画面。
	for index: int in range(_cells.size()): # 裂纹从右向左过格，每格仍按原坡面显示。
		var cell: PlantCell = _cells[index] # 实际将要掉落的地块。
		var local_age: float = _age - float(_cells.size() - index - 1) * 0.017 # 依次打开相邻格的短裂纹。
		var charge: float = energy * smoothstep(0.016, 0.17, local_age) # 第一帧维持现场原来的可读性。
		if charge <= 0.0:
			continue
		var outline := PackedVector2Array() # 闭合实际四边，不画矩形幻影。
		var transform_to_local: Transform2D = global_transform.affine_inverse() * cell.get_global_transform() # 地块到演出世界坐标。
		for point: Vector2 in cell.board_definition.hit_polygon: # 与点击格位一致的原始顶点。
			outline.append(transform_to_local * point)
		if outline.size() < 3:
			continue
		draw_colored_polygon(outline, Color(0.74, 0.87, 0.96, charge * 0.085))
		outline.append(outline[0])
		draw_polyline(outline, Color(0.78, 0.93, 1.0, charge * 0.62), 1.55, true)
		draw_line(outline[0], outline[1], Color(0.28, 0.44, 0.59, charge * 0.51), 4.2, true)
		draw_line(outline[0], outline[1], Color(0.92, 0.97, 1.0, charge), 2.1, true)
	if _age < CRACK:
		return
	var age: float = _age - CRACK # 断雪从真实裂口向镜头抛起。
	var dust: float = 1.0 - smoothstep(0.23, 1.18, age) # 停顿末端回到正常能见度。
	if dust <= 0.0:
		return
	var puff: Texture2D = SnowPeaFrostVisual.mist_texture() # 沿用原霜雾笔刷。
	for index: int in range(_lip.size()): # 每格一团碎雪和一枚近距离雪晶。
		var edge: Vector2 = to_local(_lip[index]) # 断面在板块后缘，尘团不会跟着下方消失。
		var swell: Vector2 = Vector2(116.0, 32.0) * (0.63 + age * 1.03) # 冲击后先贴地再散开。
		var center: Vector2 = edge + Vector2(-age * (44.0 + float(index % 3) * 9.0), Mountain.row_stride() * t - age * 28.0) # 延续场景风向。
		draw_texture_rect(puff, Rect2(center - swell * 0.5, swell), false, Color(0.80, 0.91, 0.99, dust * 0.68))
		var chip: Vector2 = edge + Vector2(-age * (62.0 + index * 5.0), -88.0 * age + 114.0 * age * age) # 可见的小雪屑从断口抛离。
		SnowPeaFrostVisual.draw_shard(self, chip, 3.0 + float(index % 3), 2.33 + age * 4.0, dust * 0.87)

## 最后一拍结束或场景退出时归还天空的机位。
func _finish_presentation() -> void:
	if not _playing:
		return
	_playing = false
	set_process(false)
	if is_instance_valid(_sky):
		_sky.transform = _sky_transform
		_sky.follow_viewport_enabled = _sky_follows
	if is_instance_valid(_quake):
		_quake.queue_free()
	queue_redraw()

## 离开当前战斗时释放画布内创建的裂离板块。
func _exit_tree() -> void:
	if is_instance_valid(_slab):
		_slab.queue_free()
	_finish_presentation()
