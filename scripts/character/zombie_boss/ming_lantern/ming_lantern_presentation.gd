## 明灯的可点播时间轴；同一舞台供正式战斗和 Boss 图鉴使用。
extends Node2D
class_name MingLanternPresentation

## 一条指定的演出时间轴结束，场地上的灯条仍各自计时。
signal action_finished(action: StringName)

## 调用方可点播的动作。过半血的滔天使用同一时间轴的换形参数。
const ACTIONS: Array[StringName] = [&"entrance", &"guide", &"anchor", &"tide", &"shock", &"tidal", &"death"]
## 灯条是可被本格植物索敌的独立设施。
const ROD: PackedScene = preload("res://scenes/character/zombie_boss/ming_lantern_rod.tscn")
## 整批灯条共享一次声纳提示，立体声湿尾已烘入素材。
const SONAR: AudioStream = preload("res://resources/audio/sfx/ming_lantern_sonar.ogg")
## 单根灯条俯冲穿过深水。
const ROD_FLIGHT: AudioStream = preload("res://resources/audio/sfx/ming_lantern_rod_flight.ogg")
## 灯条刺入地面时近距离的闷响和小水花。
const ROD_INSERT: AudioStream = preload("res://resources/audio/sfx/ming_lantern_rod_insert.ogg")
## 水下爆炸的压力瞬态和气穴尾音。
const BLAST_SOUND: AudioStream = preload("res://resources/audio/sfx/ming_lantern_blast.ogg")
## 本体靠近时一路增长的低频船身共振。
const ENTRY: AudioStream = preload("res://resources/audio/sfx/ming_lantern_entry.ogg")
## 巨锚接触地面时的低沉撞击。
const IMPACT: AudioStream = preload("res://resources/audio/sfx/ming_lantern_anchor.ogg")
## 本体完全退到视野外所需的世界像素数。
const OFFSCREEN := 362.0
## 预览棋盘的行列固定为终末场地对应的 6×9。
const PREVIEW_DIMENSIONS := Vector2i(6, 9)

## 当前 Boss 本体及光纹。场景层级高于技能容器，也盖过灯条继承的血条层级。
@onready var visual: MingLanternVisual = $Visual
## 当震颤出现时，在技能和本体绘制前复制一次棋盘与植物。
@onready var _shock_capture: BackBufferCopy = $ShockCapture
## 子效果与角色同生命周期，统一收尾。
@onready var _effects: Node2D = $Effects
## 震屏后的短促全屏亮光，仅在所属视口合成。
@onready var _flash: ColorRect = $ScreenFlash/Light

## 有效的实际棋盘；图鉴使用下方的无碰撞格网。
var _board: BoardRuntime
## 实战结算入口；为空时仅播放画面和声音。
var _combat: MingLanternCombat
## 实战与图鉴各自使用本视口的照明层。
var _lighting: MingLanternLighting
## 无实体预览场地的世界矩形。
var _preview_grid := Rect2()
## 只为显式动作抽取落点及错序，不与全局出怪或掉落共用随机源。
var _rng := RandomNumberGenerator.new()
## 当前动作的时间轴；停播时可取消所有未执行的关键帧。
var _timeline: Tween
## 本体和仍在执行的落点演出共享的动作倍率，图鉴始终为 1。
var _action_rate := 1.0
## 屏幕脉冲和本体余晖的独立短时间轴。
var _flashes: Tween
## 动作尾声需通知调用方的当前动作名。
var _action: StringName = &""
## 本明灯实例尚未释放的灯条。
var _rods: Array[MingLanternRod] = []
## 正在使用折射快照的震颤数量。最后一道余纹退出后关闭复制。
var _shock_rings := 0

## [param board] 为实战棋盘，[param combat] 为其结算器，[param preview_grid] 为无棋盘时的世界区间。
func configure(board: BoardRuntime, combat: MingLanternCombat, preview_grid: Rect2 = Rect2()) -> void:
	_board = board
	_combat = combat
	_preview_grid = preview_grid
	_rng.randomize()
	var host: Node = combat.game if combat != null else get_viewport() # 本战场及图鉴分别拥有光场。
	_lighting = MingLanternLighting.for_host(host)
	_lighting.watch(visual, visual.draw_scene_light)

## 返回当前是否有正在进行本体演出的动作。
func is_busy() -> bool:
	return not _action.is_empty()

## 改变 [param rate] 后继续当前关键帧，已开始的水上动作与本体使用同一倍率。
func set_action_rate(rate: float) -> void:
	_action_rate = rate
	visual.action_rate = rate
	if _timeline != null and _timeline.is_valid():
		_timeline.set_speed_scale(rate)

## 落物读取实时倍率，入场时保存的倍率不会把它们锁在旧速度。
func _get_action_rate() -> float:
	return _action_rate

## 停止所有演出后，回到 [param phase] 对应的待机形态。
func reset(phase: int) -> void:
	_clear_timeline()
	_clear_effects()
	if _board == null:
		_rng.seed = 731947 # 图鉴重播使用固定落点以便逐帧观察。
	visual.position.x = 0.0
	visual.set_phase(phase)
	visual.show()

## 播放 [param action] 的时间轴。[param transform_on_return] 让强化滔天回场时才换星空原画。
## 已存在的灯条保留至自己的期限；死亡或主动重置会清除场上残余演出。
## 未知动作返回 false；战斗角色负责决定何时调用，图鉴可直接点播。
func play_action(action: StringName, transform_on_return: bool = false) -> bool:
	if not ACTIONS.has(action):
		return false
	_clear_timeline()
	_action = action
	_timeline = create_tween().set_speed_scale(_action_rate)
	var powered: bool = visual.displayed_phase == 2 or transform_on_return # 过半触发的滔天先强化招式，归位时才换图。
	match action:
		&"entrance":
			visual.position.x = OFFSCREEN
			visual.show()
			_queue_rods(5)
			_timeline.tween_interval(0.18)
			_queue_waves(PREVIEW_DIMENSIONS.x, false, powered, false)
			_timeline.tween_interval(0.40)
			_timeline.tween_callback(_pulse.bind(Vector2(10, 13), 0.60, 0.71, true))
			_enter()
		&"guide":
			_cast(true)
			_queue_rods(6 if powered else 5)
			_timeline.tween_interval(MingLanternRod.FALL_TIME)
		&"anchor":
			_cast(false)
			var targets: Array[Vector2i] = _targets(1) # 战场随机落格，图鉴将锚落在画面中心。
			var address: Vector2i = targets[0] if _board != null and not targets.is_empty() else _center_target() # 无格时跳过坠落。
			_timeline.tween_callback(_spawn_anchor.bind(address, false, false))
			_timeline.tween_interval(MingLanternAnchor.IMPACT_TIME + 0.25)
		&"tide":
			_cast(true)
			_queue_waves(PREVIEW_DIMENSIONS.x, false, powered, false)
			_timeline.tween_interval(_wave_crossing_time())
		&"shock":
			_cast(false)
			for address: Vector2i in _targets(2): # 震荡由两个不同落点的光圈组成。
				_timeline.tween_callback(_spawn_ring_pair.bind(address, false))
				_timeline.tween_interval(0.28)
			_timeline.tween_interval(0.55)
		&"tidal":
			_depart(true)
			_queue_rods(7 if powered else 5)
			_timeline.tween_interval(MingLanternRod.FALL_TIME + 0.20)
			_queue_waves(5, true, powered, powered)
			_timeline.tween_interval(maxf(1.02, _wave_crossing_time() - MingLanternAnchor.IMPACT_TIME)) # 算上巨锚的下坠，触地拍接在浪扫完之后。
			_timeline.tween_callback(_spawn_anchor.bind(_center_target(), true, powered))
			_timeline.tween_interval(MingLanternAnchor.IMPACT_TIME + 0.58)
			if transform_on_return:
				_timeline.tween_callback(visual.set_phase.bind(2))
			_enter()
		&"death":
			_clear_effects()
			_timeline.tween_callback(_pulse.bind(Vector2(20, 23), 0.85, 0.63, true))
			_timeline.tween_interval(0.36)
			_depart(false)
	_timeline.tween_callback(_finish_action)
	return true

## 取消未执行的关键帧，恢复屏幕和本体的瞬间亮度。
func _clear_timeline() -> void:
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	if _flashes != null and _flashes.is_valid():
		_flashes.kill()
	_action = &""
	_flash.color.a = 0.0
	visual.flare = 0.0

## 删除上一段演出的临时节点与待引爆灯条。
func _clear_effects() -> void:
	for effect: Node in _effects.get_children(): # 移出父节点同帧停止渲染和后续回调。
		_effects.remove_child(effect)
		effect.queue_free()
	_rods.clear()

## 以顿步方式入场；最后几步才逐渐显出完整露在屏内的眼睛。
func _enter() -> void:
	_timeline.tween_callback(visual.show)
	_timeline.tween_callback(_play_sound.bind(ENTRY, -1.5))
	for step: int in range(4): # 每推进一段先停顿，再继续挤入视窗。
		var x: float = [256.0, 177.0, 91.0, 0.0][step] # 右侧隐藏区起步，最终归位。
		_timeline.tween_property(visual, "position:x", x, 0.48 + 0.06 * step).set_trans(Tween.TRANS_SINE)
		_timeline.tween_callback(_footfall.bind(step))
		_timeline.tween_interval(0.19 + 0.075 * step)

## [param slow] 为滔天的缓退；死亡时更重、更快地沉入右侧。
func _depart(slow: bool) -> void:
	_timeline.tween_callback(_play_sound.bind(MingLanternWave.SURF, -6.0, 0.64))
	for step: int in range(3): # 退出也有明显的分段停顿。
		var x: float = [95.0, 212.0, OFFSCREEN][step] # 同一右侧裁切线。
		_timeline.tween_property(visual, "position:x", x,
			(0.57 if slow else 0.30) + float(step) * 0.06).set_trans(Tween.TRANS_SINE)
		_timeline.tween_interval(0.21 if slow else 0.09)
	_timeline.tween_callback(visual.hide)

## [param step] 为入场顿步编号，靠近时加重抖动与本体光脉冲。
func _footfall(step: int) -> void:
	_pulse(Vector2(9, 13) + Vector2(2, 2) * float(step), 0.42, 0.16 + 0.06 * step)

## 施法眨眼中段是释放点；[param heavy] 让引路、海啸有同拍镜头冲击。
func _cast(heavy: bool) -> void:
	_timeline.tween_callback(visual.blink)
	_timeline.tween_interval(0.37)
	if heavy:
		_timeline.tween_callback(_pulse.bind(Vector2(13, 18), 0.53, 0.32))

## 释放 [param count] 根灯条，每根的坐标与坠落时点都错开。
func _queue_rods(count: int) -> void:
	_timeline.tween_callback(_play_sound.bind(SONAR, -2.0)) # 声纳只随召唤的释放帧播放一次。
	var index := 0 # 控制各灯条的偏转方向与错峰间距。
	for address: Vector2i in _targets(count, true): # 同批次只用未有灯条的落点。
		_timeline.tween_callback(_spawn_rod.bind(address, index))
		_timeline.tween_interval(0.115 + float(index % 3) * 0.032)
		index += 1

## [param count] 是本次浪数；[param tidal] 会击爆灯后生成震颤。
## [param powered] 启用二阶段的推移和连锁爆炸，[param aftershocks] 给连锁加余波。
func _queue_waves(count: int, tidal: bool, powered: bool, aftershocks: bool) -> void:
	var lanes: Array[int] = [] # 各路只创建一道浪。
	for lane: int in range(_board.rows().size() if _board != null else PREVIEW_DIMENSIONS.x): # 实战跟随棋盘行数。
		if _board == null or not _board.row_cells(lane).is_empty():
			lanes.append(lane)
	_shuffle(lanes)
	_timeline.tween_callback(_play_sound.bind(MingLanternWave.SURF, -8.0 if tidal else -11.0, 0.78 if powered else 0.98))
	for index: int in range(mini(count, lanes.size())): # 以随机行序和不等间隔出现。
		_timeline.tween_callback(_spawn_wave.bind(lanes[index], tidal, powered, aftershocks))
		_timeline.tween_interval(0.142 + float(index % 3) * 0.033)

## 返回最宽场地从起浪到离场的战斗秒数，供海啸收招及滔天的巨锚衔接。
func _wave_crossing_time() -> float:
	var width: float = BoardQueries.bounds(_board.cells()).size.x if _board != null else _preview_grid.size.x # 实战取棋盘跨度，图鉴取预览宽度。
	return MingLanternWave.travel_duration(width + MingLanternWave.START_MARGIN + MingLanternWave.END_MARGIN)

## [param address] 为落格，[param index] 仅用于轨迹变化。
func _spawn_rod(address: Vector2i, index: int) -> void:
	var rect: Rect2 = _cell_rect(address) # 已消失的格不再接收灯条。
	if not rect.has_area() or _has_rod(address):
		return
	var rod := ROD.instantiate() as MingLanternRod # 实战和图鉴复用同一落物。
	rod.fall_rate = _get_action_rate
	rod.character_init_type = Character000Base.E_CharacterInitType.IsShow if _combat == null else Character000Base.E_CharacterInitType.IsNorm
	rod.address = address
	rod.lane = address.x
	var tilt_degrees: float = [-26.0, 26.0, 15.0, -19.0][index % 4] # 相对竖直方向的入场倾角，正值从落点右上方进入。
	rod.flight_axis = Vector2.UP.rotated(deg_to_rad(tilt_degrees))
	rod.position = _effects.to_local(Vector2(rect.get_center().x, rect.end.y - 10.0))
	rod.landed.connect(_on_rod_landed)
	rod.burst.connect(_on_rod_burst)
	rod.tree_exiting.connect(_rods.erase.bind(rod))
	_rods.append(rod)
	_effects.add_child(rod) # 同一帧先推进灯身姿态，再采样尾迹接点。
	var trail := MingLanternRodTrail.new() # 被击破的灯条也留下已经写入水中的轨迹，直到自然消散。
	trail.rod = rod
	trail.fall_rate = _get_action_rate
	trail.position = rod.position
	trail.z_index = -1
	_effects.add_child(trail)
	if _lighting != null:
		_lighting.watch(rod, rod.draw_scene_light)
		_lighting.watch(trail, trail.draw_scene_light)
	var pitch: float = [1.04, 0.96, 1.09, 0.91][index % 4] # 相邻落物有细微音高差，不掩盖批次提示。
	_play_sound(ROD_FLIGHT, -9.0, pitch)

## [param rod] 的下端插入地面；音效与真实伤害使用同一帧。
func _on_rod_landed(rod: MingLanternRod) -> void:
	_play_sound(ROD_INSERT, -6.0, 1.0 + rod.flight_axis.x * 0.106)
	if _combat != null:
		_combat.rod_impact(rod.address)

## [param rod] 的引信到期或被浪触发，在有效落点播放爆炸、破水声和短震。
func _on_rod_burst(rod: MingLanternRod) -> void:
	var cell: Rect2 = _cell_rect(rod.address) # 只在灯条仍有实际落点时爆炸。
	if not cell.has_area():
		return
	var blast := MingLanternUnderwaterBlast.new() # 爆心、受阻气泡和短暂光雾由同一时钟控制。
	blast.position = _effects.to_local(rod.to_global(MingLanternRod.CONTACT))
	blast.extent = cell.size * 1.5
	_effects.add_child(blast)
	if _lighting != null:
		_lighting.watch(blast, blast.draw_scene_light)
	var gain := -3.5 # 头一次爆响有足够的低频冲击，后续叠在尾音上的爆响稍低。
	for effect: Node in _effects.get_children(): # 只对尚在发声的同类爆炸留出合成余量。
		if effect is AudioStreamPlayer and effect.stream == BLAST_SOUND and effect.playing:
			gain = -8.5
			break
	_play_sound(BLAST_SOUND, gain, 1.0 + rod.flight_axis.x * 0.12)
	_shake_camera(Vector2(3.0, 4.0), 0.14)
	if _combat != null:
		_combat.underwater_blast(rod.address)

## [param lane] 的浪从棋盘右边缘外开始；[param tidal]、[param powered]、[param aftershocks] 传给碰撞关键帧。
func _spawn_wave(lane: int, tidal: bool, powered: bool, aftershocks: bool) -> void:
	var cells: Array[Rect2] = [] # 余光按真实格子铺设，跳过棋盘缺口。
	if _board != null:
		for cell: PlantCell in _board.row_cells(lane): # 实战使用权威棋盘的格子位置。
			var rect: Rect2 = cell.get_global_rect() # 行内各格可以有不同世界尺寸。
			if rect.has_area():
				cells.append(rect)
	else:
		for column: int in range(PREVIEW_DIMENSIONS.y): # 图鉴按既有预览格网写入水路。
			var rect: Rect2 = _cell_rect(Vector2i(lane, column)) # 本列对应的预览世界范围。
			if rect.has_area():
				cells.append(rect)
	if cells.is_empty():
		return
	var field: Rect2 = cells.front() # 只用整行包围框定位浪身，光路仍按实格裁切。
	for rect: Rect2 in cells: # 行跨度决定从哪里推进、退到哪里结束。
		field = field.merge(rect)
	var lane_count: int = _board.extent.x if _board != null else PREVIEW_DIMENSIONS.x # 按当前棋盘错开浪冠相位。
	var wave := MingLanternWave.for_lane(_effects, field, cells, false, lane, lane_count) # 实战与图鉴共用向左的翻卷与尾迹。
	wave.sweep_rate = _get_action_rate
	wave.wave_advanced.connect(_on_wave_advanced.bind(wave, lane, tidal, powered, aftershocks))
	_effects.add_child(wave)
	if _lighting != null:
		_lighting.watch(wave, wave.draw_scene_light)

## [param previous] 至 [param current] 是 [param wave] 的扫掠，[param lane]、[param tidal]、
## [param powered]、[param aftershocks] 分别为攻击行、连锁类型、阶段力度和余波开关。
func _on_wave_advanced(previous: float, current: float, wave: MingLanternWave,
		lane: int, tidal: bool, powered: bool, aftershocks: bool) -> void:
	var hit: float = _combat.wave_contact(lane, current, previous, 2 if powered else 1) if _combat != null else NAN # 有阻挡时只计算推进至命中位置。
	if tidal or powered:
		for rod: MingLanternRod in _rods.duplicate(): # 引爆可能触发设施销毁，使用快照。
			if not is_instance_valid(rod) or rod.is_death or not rod.is_planted or rod.lane != lane:
				continue
			var x: float = rod.global_position.x # 灯条与格中心同轴，让同格阻挡也能引爆。
			if x > previous or x < (hit if is_finite(hit) else current):
				continue
			rod.detonate()
			if tidal:
				_spawn_ring_pair(rod.address, aftershocks)
	if is_finite(hit):
		wave.break_wave(hit)

## [param address] 的阵地上出现白色震颤；[param repeat] 加一层有延迟的同源余震。
func _spawn_ring_pair(address: Vector2i, repeat: bool) -> void:
	var touched: Dictionary[int, bool] = {} # 同一组光圈共享接触记录，余震不刷新减速。
	var ring: MingLanternShockRing = _spawn_ring(address, touched, false) # 余波绑在主环上随其取消。
	if repeat and ring != null:
		var delay: Tween = ring.create_tween() # 主环存在期间只排入一次余波。
		delay.tween_interval(0.21)
		delay.tween_callback(_spawn_ring.bind(address, touched, true))

## [param address] 为五格中心，[param touched] 为同组已命中角色，[param aftershock] 调暗第二层。
func _spawn_ring(address: Vector2i, touched: Dictionary[int, bool], aftershock: bool) -> MingLanternShockRing:
	var cell: Rect2 = _cell_rect(address) # 以实际长宽决定水圈的透视。
	if not cell.has_area():
		return null
	var center: Vector2 = cell.get_center() # 投光、声音和接触结算共享中心。
	var ring := MingLanternShockRing.at_contact(_effects, center, cell.size, _shock_cells(address), aftershock) # 水圈持有自己的折射和余光。
	if _combat != null:
		ring.ring_advanced.connect(_on_ring_advanced.bind(address, center, ring.extent, touched))
	_shock_rings += 1
	_shock_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	ring.tree_exiting.connect(_on_shock_exiting, CONNECT_ONE_SHOT)
	_effects.add_child(ring)
	if _lighting != null:
		_lighting.watch(ring, ring.draw_scene_light)
	MingLanternShockRing.play_voice(_effects, center, aftershock)
	return ring

## 返回 [param address] 附近 5×5 的实际格子世界矩形，图鉴使用本身的预览格网。
func _shock_cells(address: Vector2i) -> Array[Rect2]:
	var rectangles: Array[Rect2] = [] # 只在有效地块上生成随波前推进的余光。
	if _board != null:
		for cell: PlantCell in _board.neighbors(_board.cell_at(address), MingLanternShockRing.GRID_RADIUS): # 复用震颤的格子半径。
			rectangles.append(cell.get_global_rect())
		return rectangles
	var reach: int = MingLanternShockRing.GRID_RADIUS # 图鉴按相同的五行半径从预览格网取样。
	for lane: int in range(address.x - reach, address.x + reach + 1): # 略过超出预览格网的行。
		for column: int in range(address.y - reach, address.y + reach + 1): # 场地边沿之外不留余光。
			var rect: Rect2 = _cell_rect(Vector2i(lane, column)) # 这里已经处理无效的预览地址。
			if rect.has_area():
				rectangles.append(rect)
	return rectangles

## 最后一道震颤离树时停用读屏，重播与死亡也经过同一个清理入口。
func _on_shock_exiting() -> void:
	_shock_rings -= 1
	if _shock_rings == 0 and is_instance_valid(_shock_capture):
		_shock_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED

## 把 [param progress] 转成实际世界半径，[param address]、[param center]、[param extent]、[param touched] 来自本组震颤。
func _on_ring_advanced(progress: float, address: Vector2i, center: Vector2, extent: Vector2, touched: Dictionary[int, bool]) -> void:
	_combat.ring_progress(address, center, extent * progress, touched)

## [param address] 为锚的攻击中心；滔天以 [param add_shock] 生震荡，[param repeat] 控制余波。
func _spawn_anchor(address: Vector2i, add_shock: bool, repeat: bool) -> void:
	var cell: Rect2 = _cell_rect(address) # 在落点的地面绘制预兆。
	if not cell.has_area():
		return
	var anchor := MingLanternAnchor.new() # 下坠、冲击和缓沉以同一落点计时。
	anchor.fall_rate = _get_action_rate
	anchor.position = _effects.to_local(cell.get_center())
	anchor.extent = cell.size * 1.5
	anchor.water_area = BoardQueries.bounds(_board.cells()) if _board != null else _preview_grid
	anchor.anchor_landed.connect(_on_anchor_landed.bind(address, add_shock, repeat))
	_effects.add_child(anchor)
	if _lighting != null:
		_lighting.watch(anchor, anchor.draw_scene_light)

## [param address] 的巨锚着地；[param add_shock] 开启滔天震荡，[param repeat] 附加余波。
func _on_anchor_landed(address: Vector2i, add_shock: bool, repeat: bool) -> void:
	_play_sound(IMPACT, -1.0)
	_pulse(Vector2(24, 32), 0.56, 0.23)
	if _combat != null:
		_combat.anchor_impact(address)
	if add_shock:
		_spawn_ring_pair(address, repeat)
		for nearby: Vector2i in _targets(2): # 向爆心之外释放另一次震颤。
			if nearby != address:
				_spawn_ring_pair(nearby, repeat)
				break

## 仅震动当前舞台的相机。[param amplitude] 为像素偏移上限，[param duration] 为战斗秒数。
func _shake_camera(amplitude: Vector2, duration: float) -> void:
	var camera := get_viewport().get_camera_2d() as MainGameCamera # 图鉴和战斗各自只震自己的视口。
	if camera != null:
		camera.shake_once(amplitude, duration, 15.0)

## [param amplitude]、[param duration] 控制震屏。[param strength] 控制全屏亮光，[param double] 加一帧回闪。
func _pulse(amplitude: Vector2, duration: float, strength: float, double: bool = false) -> void:
	_shake_camera(amplitude, duration)
	if _flashes != null and _flashes.is_valid():
		_flashes.kill()
	_flash.color.a = strength
	visual.flare = strength
	_flashes = create_tween()
	_flashes.tween_property(_flash, "color:a", 0.0, 0.20 if double else 0.15)
	if double:
		_flashes.tween_property(_flash, "color:a", strength * 0.57, 0.055)
		_flashes.tween_property(_flash, "color:a", 0.0, 0.22)
	_flashes.parallel().tween_property(visual, "flare", 0.0, 0.29)

## 播放 [param stream] 的烘焙水下音色，用 [param gain]、[param pitch] 处理叠音。
## 重播或退出时播放器随演出一起回收。
func _play_sound(stream: AudioStream, gain: float, pitch: float = 1.0) -> void:
	var player := AudioStreamPlayer.new() # 每根飞行或入水都播一次，时间轴可重叠。
	var motion_speed: float = maxf(Engine.time_scale, 0.01) if stream == ROD_FLIGHT or stream == ENTRY else 1.0 # 连续运动声随触发时的战斗速度调整时长。
	player.bus = &"SFX" # 音色已烘焙。场景更换临时声场时，仍持续服从音效音量。
	player.stream = stream
	player.volume_db = gain
	player.pitch_scale = pitch * motion_speed
	player.finished.connect(player.queue_free)
	_effects.add_child(player)
	player.play()

## 收起本次动作的队列并通知战斗层解除入场保护。
func _finish_action() -> void:
	var finished: StringName = _action # 通知前解除本体占用，便于调用方立即点播下一段。
	_action = &""
	_timeline = null # 已在最后一个关键帧，连招可以接管时间轴。
	action_finished.emit(finished)

## 抽取至多 [param count] 个不同格子；[param unused_only] 要求避开已有灯条。
func _targets(count: int, unused_only: bool = false) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [] # 当前可选的实际攻击位置。
	if _board != null:
		for cell: PlantCell in _board.cells(): # 允许棋盘缩列或非矩形布局。
			cells.append(cell.row_col)
	else:
		for lane: int in range(PREVIEW_DIMENSIONS.x): # 图鉴只使用六路的等分网格。
			for column: int in range(PREVIEW_DIMENSIONS.y): # 同样从全场选格。
				cells.append(Vector2i(lane, column))
	_shuffle(cells)
	var result: Array[Vector2i] = [] # 按本次时间轴需要收集落点。
	for address: Vector2i in cells: # 无可选目标时允许生成更少的灯条。
		if result.size() >= count:
			break
		if not unused_only or not _has_rod(address):
			result.append(address)
	return result

## [param address] 仍有灯条在空中或立在地面时返回 true。
func _has_rod(address: Vector2i) -> bool:
	for rod: MingLanternRod in _rods: # 不按场上普通僵尸状态筛选。
		if is_instance_valid(rod) and not rod.is_death and rod.address == address:
			return true
	return false

## 使用私有随机源就地打乱 [param values]，只影响此演出的落点与出浪顺序。
func _shuffle(values: Array) -> void:
	for index: int in range(values.size() - 1, 0, -1): # 倒序交换尚未确定的元素。
		var selected: int = _rng.randi_range(0, index) # 等概率选取剩余候选。
		var previous: Variant = values[index] # 同时兼容行号与地块地址。
		values[index] = values[selected]
		values[selected] = previous

## [param address] 对应的世界矩形；不存在的真实格返回空矩形。
func _cell_rect(address: Vector2i) -> Rect2:
	if _board != null:
		var cell: PlantCell = _board.cell_at(address) # 读实际地块世界坐标。
		return cell.get_global_rect() if cell != null else Rect2()
	if address.x < 0 or address.y < 0 or address.x >= PREVIEW_DIMENSIONS.x or address.y >= PREVIEW_DIMENSIONS.y:
		return Rect2()
	var size: Vector2 = _preview_grid.size / Vector2(PREVIEW_DIMENSIONS.y, PREVIEW_DIMENSIONS.x) # 预览矩形均匀划分。
	return Rect2(_preview_grid.position + size * Vector2(address.y, address.x), size)

## 返回画面中点最近的实际种植格，用于滔天收尾的锚。
func _center_target() -> Vector2i:
	if _board != null:
		var center: Vector2 = get_canvas_transform().affine_inverse() * get_viewport_rect().get_center() # 相机与棋盘都使用世界坐标。
		var cell: PlantCell = _board.nearest_cell(center) # 无棋盘格时返回无效地址。
		return cell.row_col if cell != null else Vector2i(-1, -1)
	return Vector2i(2, 4)
