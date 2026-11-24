## 福音的白柱、猩红湮灭和击破余光。实际目标、血量与倒计时均来自承伤设施。
extends Node2D

## 负责存活血量和 12 秒结算的正式设施。
const Pillar = preload("res://scripts/character/zombie_boss/savior/savior_gospel_pillar.gd")
## 在原植物离场前一次拍下其可见部件。
const Fragments = preload("res://scripts/fx/savior_gospel_fragments.gd")
## 白柱和猩红余光都进入教堂原有灯光和投影。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 活柱随倒计时酝酿，另有白色击碎及猩红成熟两种退场。
enum Stage { LIVE, BROKEN, CRIMSON }
## 与疯狂柱身材质的脚点坐标一致。
const GROUND_Y := 0.88
## 白柱被击碎后的战斗秒数。
const BREAK_SECONDS := 0.42
## 成熟时同时给上卷的原画碎片留出收尾。
const EXPIRE_SECONDS := 0.79

## 一个设施和脱离设施后延续的余光共用同一份状态。
class Column:
	## 尚活跃的真实设施，退场时解除引用。
	var pillar: Pillar
	## 最新的实际世界柱底与格距。
	var point: Vector2
	## 柱宽、光圈和粒子位移共用的世界单位。
	var span: float
	## 现有灯光登记使用的垂足。
	var anchor: Marker2D
	## 活柱或两种余光变体。
	var stage := Stage.LIVE
	## 当前阶段经过的战斗秒数。
	var age: float
	## 施法时确定的缓慢光纹相位。
	var seed: float
	## 活柱最后一帧的照度，击破时从同一照度回落。
	var live_power: float
	## 成熟时的植物微片，只有确实捕获原画才存在。
	var fragments: Fragments

## 实际使用摄像机的世界画布。
var _world: Node2D
## 教堂现有的可见性光场。
var _field: LightField
## 全部柱体和短暂余光按原设施 ID 登记。
var _columns: Dictionary[int, Column] = {}
## 用当前镜头把同一份世界坐标送给柱体和碎片。
var _to_layer := Transform2D.IDENTITY
## 批处理的流动相位，完全使用战斗时钟。
var _clock: float
## 柱身沿用疯狂材质和同样的实例格式。
@onready var _beams: MultiMeshInstance2D = $Beams
## 本场独占的柱身材质参数。
@onready var _material := _beams.material as ShaderMaterial
## 白柱出现时起声，落地时在音轨内接低钟鸣。
@onready var _summon_cue: AudioStreamPlayer = $SummonCue
## 红化和植物破散共用一次冲击声，允许与另一根白柱的余响重叠。
@onready var _annihilation_cue: AudioStreamPlayer = $AnnihilationCue

## 在 [param world] 和它现有的 [param field] 中启用福音演出。
func configure(world: Node2D, field: LightField) -> void:
	_world = world
	_field = field
	_beams.multimesh.visible_instance_count = 0

## 从已实际入场的 [param pillar] 登记白色柱体和局部照明。
func watch(pillar: Pillar) -> void:
	var column := Column.new() # 游戏实体之后可以独立结束。
	column.pillar = pillar
	column.point = pillar.world_foot()
	column.span = pillar.visual_span
	column.seed = fposmod(column.point.dot(Vector2(0.028, 0.073)), 0.98)
	if is_instance_valid(_field):
		column.anchor = Marker2D.new()
		_world.add_child(column.anchor)
		column.anchor.global_position = column.point
		_register_light(column, LightField.Tone.WARM)
	_columns[pillar.get_instance_id()] = column
	_play_cue(_summon_cue)

## [param id] 对应的柱子被击碎或 [param expired] 成熟。若仍锁定 [param plant]，先定格其最后一帧。
func finish(id: int, expired: bool, plant: Plant000Base = null) -> void:
	var column: Column = _columns.get(id) # 双重退场事件只执行一次。
	if column == null or column.stage != Stage.LIVE:
		return
	if is_instance_valid(column.pillar):
		column.point = column.pillar.world_foot()
	column.pillar = null
	column.age = 0.0
	column.stage = Stage.CRIMSON if expired else Stage.BROKEN
	if expired:
		if is_instance_valid(column.anchor) and is_instance_valid(_field):
			_field.unregister_light(column.anchor.get_instance_id())
			_register_light(column, LightField.Tone.RED)
		_play_cue(_annihilation_cue)
		if is_instance_valid(plant):
			var fragments := Fragments.new() # 冻结时仍能读到身体、衣叶和动画帧。
			if fragments.capture(plant, _world, column.point, column.span):
				fragments.z_index = 1
				add_child(fragments)
				fragments.transform = _to_layer
				column.fragments = fragments
			else:
				fragments.free()

## 推进 [param delta] 个战斗秒，在镜头刷新后一批提交白柱和红柱。
func present_frame(delta: float) -> void:
	if _summon_cue.playing or _annihilation_cue.playing:
		_sync_cue_speed()
	if _columns.is_empty():
		return
	_clock += delta
	_to_layer = get_global_transform_with_canvas().affine_inverse() * _world.get_canvas_transform()
	_beams.transform = _to_layer
	var mesh: MultiMesh = _beams.multimesh # 柱光共用一个四边形和材质。
	if mesh.instance_count < _columns.size():
		mesh.instance_count = maxi(_columns.size(), mesh.instance_count * 2)
	var crimson_columns: Array[Column] = [] # 同格连续施法时把成熟红柱绘制在白柱上方。
	var slot := 0 # 毫无间隔地填入仍要绘制的实例。
	for id: int in _columns.keys(): # 拷贝键列表，允许此步内收回到期余光。
		var column: Column = _columns[id] # 保持和设施的真实位置、受击状态对应。
		column.age += delta
		if column.stage == Stage.LIVE:
			if not is_instance_valid(column.pillar):
				_release(id)
				continue
			column.point = column.pillar.world_foot()
		elif column.age >= (EXPIRE_SECONDS if column.stage == Stage.CRIMSON else BREAK_SECONDS):
			_release(id)
			continue
		if column.stage == Stage.CRIMSON:
			crimson_columns.append(column)
			continue
		_submit(column, mesh, slot)
		slot += 1
	for column: Column in crimson_columns: # 同一批次仍然只提交一次。
		_submit(column, mesh, slot)
		slot += 1
	mesh.visible_instance_count = slot
	_material.set_shader_parameter(&"flow_time", _clock)

## 让两次短音效及余响和柱体使用同一个战斗倍速。
func _sync_cue_speed() -> void:
	var speed: float = maxf(0.01, Engine.time_scale) # 避免极慢速下给播放器提交零音高。
	if not is_equal_approx(_summon_cue.pitch_scale, speed):
		_summon_cue.pitch_scale = speed
		_annihilation_cue.pitch_scale = speed

## 在技能事件发生时通过现有战斗音效路由触发 [param cue]。
func _play_cue(cue: AudioStreamPlayer) -> void:
	_sync_cue_speed()
	cue.bus = SoundManager.spatial_sfx_bus()
	cue.play()

## 以 [param slot] 提交 [param column] 的柱身。同步更新其灯光和碎片。
func _submit(column: Column, mesh: MultiMesh, slot: int) -> void:
	var age: float = column.age # 每段只用自己的相对时间。
	var crimson: bool = column.stage == Stage.CRIMSON # 到期立刻切红。
	var retreat := 0.0 # 竖向回收和柱身收窄交给同一材质。
	var reach := 0.0 # 柱底到达格面取一。
	var shaft := 0.0 # 局部光幕的透亮程度。
	var power := 0.0 # 真光照与柱底同时变色或退场。
	if column.stage == Stage.LIVE:
		var opening: float = smoothstep(0.0, 0.32, age) # 上方光芯快速落向植物。
		var urgency: float = smoothstep(0.79, 0.99, column.pillar.progress_ratio) # 白色柱身随到期逐渐凝实。
		var pulse: float = 0.5 + 0.5 * sin(age * 5.0 + column.seed * TAU) # 同一束柱光保持缓慢的相位变化。
		reach = lerpf(0.12, 1.016, opening)
		shaft = opening * (0.44 + 0.13 * pulse + 0.10 * urgency)
		power = smoothstep(0.05, 0.30, age) * (0.69 + 0.15 * urgency)
		column.live_power = power
	elif crimson:
		var strike: float = 1.0 - smoothstep(0.018, 0.19, age) # 猩红第一拍先压满柱芯，再把碎片卷起。
		retreat = smoothstep(0.17, 0.69, age)
		reach = lerpf(1.016, 0.17, retreat)
		shaft = (0.63 + 0.32 * strike) * (1.0 - smoothstep(0.23, 0.72, age))
		power = (0.63 + 0.31 * strike) * (1.0 - smoothstep(0.17, EXPIRE_SECONDS, age))
	else:
		retreat = smoothstep(0.0, BREAK_SECONDS, age)
		reach = lerpf(1.016, 0.08, retreat)
		shaft = (0.58 + 0.20 * (1.0 - smoothstep(0.0, 0.09, age))) * (1.0 - retreat)
		power = column.live_power * (1.0 - retreat)
	var half_size: Vector2 = Vector2(0.80, 2.12) * column.span # 避免柱身完全覆盖同格植物。
	var center: Vector2 = column.point - Vector2(0.0, half_size.y * GROUND_Y) # 柱端与碰撞脚点连续对齐。
	mesh.set_instance_transform_2d(slot, Transform2D(0.0, half_size, 0.0, center))
	mesh.set_instance_color(slot, Color(retreat, float(crimson), 1.0, 0.0))
	mesh.set_instance_custom_data(slot, Color(reach, shaft, power, column.seed))
	if is_instance_valid(column.anchor) and is_instance_valid(_field):
		column.anchor.global_position = column.point
		_field.set_light_intensity(column.anchor.get_instance_id(), LightField.Tone.RED if crimson else LightField.Tone.WARM, power)
	if is_instance_valid(column.fragments):
		column.fragments.transform = _to_layer
		column.fragments.present(age)

## [param column] 的 [param tone] 只负责渲染，环境暖光的保护判断仍使用真路灯花。
func _register_light(column: Column, tone: LightField.Tone) -> void:
	var is_red: bool = tone == LightField.Tone.RED # 红柱在起爆时照出更宽的局部。
	_field.register_light(column.anchor, tone, column.span * (1.98 if is_red else 1.49),
		Vector2(0.0, -column.span * 0.41), column.anchor, column.span * 1.42, column.span * 0.16,
		0.0, false, is_red)

## 注销 [param id] 的临时灯与粒子。
func _release(id: int) -> void:
	var column: Column = _columns[id] # 活跃和结束状态都用同一回收入口。
	if is_instance_valid(column.anchor):
		if is_instance_valid(_field):
			_field.unregister_light(column.anchor.get_instance_id())
		column.anchor.queue_free()
	if is_instance_valid(column.fragments):
		column.fragments.hide()
		column.fragments.queue_free()
	_columns.erase(id)

## 撤销 [param id] 对应的单根福音柱，不播放成熟或击碎效果。
func dismiss(id: int) -> void:
	if _columns.has(id):
		_release(id)
		if _columns.is_empty():
			_beams.multimesh.visible_instance_count = 0

## 退出关卡时立即回收柱体及音效。
func clear() -> void:
	for id: int in _columns.keys(): # 在暂停前撤销世界光场数据。
		_release(id)
	_beams.multimesh.visible_instance_count = 0
	_summon_cue.stop()
	_annihilation_cue.stop()
