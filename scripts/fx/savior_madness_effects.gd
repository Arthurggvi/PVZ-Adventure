## 没入疯狂的柱身、落地音效和六盏移动的红灯，共用战斗提供的地面坐标。
extends Node2D

## 接入教堂已经使用的遮挡图集和世界合成。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 沿用现有投影和余像对实际动画帧的读取。
const SilhouettePart = preload("res://scripts/battle/environment/battle_silhouette_part.gd")
## 与四向十字共用同一套遮挡参数。
const Occlusion = preload("res://scripts/fx/savior_pillar_occlusion.gd")
## 石砖层负责触地点和扫过的裂光余痕。
const MadnessGround = preload("res://scripts/fx/savior_madness_ground.gd")
## 柱底在四边形的局部 Y 坐标。与材质共用，保证光斑和柱尖贴在地面上。
const GROUND_Y := 0.88
## 柱体四边形的半宽和半高，以实际接触半径为单位。
const BEAM_SCALE := Vector2(1.77, 9.5)
## 柱身先收拢，最后一层地面反光和投影消失所需的战斗秒数。
const RELEASE_SECONDS := 0.42

## 战斗根的画布变换，用于同步已经震动的实际相机。
var _world: Node2D
## 本场共享的世界光场。
var _field: LightField
## 临时光的池，节点位置也是投影垂足。
var _anchors: Array[Marker2D] = []
## 玩法给出的六个碰撞中心，退光时保留最后一帧。
var _points := PackedVector2Array()
## 从棋盘测出的实际接触半径，单位为世界像素。
var _radius := 0.0
## 柱体扫出棋盘时沿此空间边界自然收暗。
var _floor := Rect2()
## 以施法者的真实脚点区分柱底的前后深度。
var _owner_foot: Node2D
## 同一动画帧的笔触透明度也决定身后光柱的遮挡。
var _owner_pose: SilhouettePart
## 从顶部到柱底的下落比例。
var _reach := 0.0
## 当前柱身体感亮度，零至一。
var _shaft := 0.0
## 光圈在石砖及角色上产生的真实照明强度。
var _incident := 0.0
## 随战斗推进的时间，避免暂停时光束内部自行流动。
var _age := 0.0
## 首次触地的战斗时刻。下落阶段以无穷大标记，阻止冲击波提前出现。
var _impact_at := INF
## 非负时开始从当前姿态退光。
var _releasing := -1.0

## 石砖层和柱身共用同一批实例。石砖的高反差压痕随世界一起接受遮挡与照明。
var ground: MadnessGround
## 在相机更新后用一个批次提交全部柱身。
@onready var _batch: MultiMeshInstance2D = $Beams
## 本场独占材质，六根柱身共用实时的施法者轮廓。
@onready var _material := _batch.material as ShaderMaterial
## 地鸣走本场音效路由和玩家设置。
@onready var _quake: AudioStreamPlayer = $Quake

## [param world] 提供镜头和真实棋盘，[param field] 提供照明及地面遮挡。
func configure(world: MainGameManager, field: LightField) -> void:
	_world = world
	_field = field
	_material.set_shader_parameter(&"ground_y", GROUND_Y)
	ground.configure(GROUND_Y, BEAM_SCALE, world.board)

## 在 [param points] 开始下落。[param radius] 来自接触形状，[param floor] 是实际棋盘范围。
## [param foot] 和 [param visual] 提供施法者的脚点和实际动画遮挡。
func begin(points: PackedVector2Array, radius: float, floor: Rect2, foot: Node2D, visual: AnimatedSprite2D) -> void:
	_release_lights()
	_radius = radius
	_floor = floor
	_owner_foot = foot
	_owner_pose = SilhouettePart.new(visual)
	_impact_at = INF
	_releasing = -1.0
	ground.begin(points, radius)
	if is_instance_valid(_field):
		while _anchors.size() < points.size():
			var anchor := Marker2D.new() # 发光点和投影垂足共用同一个世界节点。
			_world.add_child(anchor)
			_anchors.append(anchor)
		for index: int in range(points.size()): # 灯在光柱落下之前先以零强度登记。
			var anchor: Marker2D = _anchors[index] # 跟随该道光柱的地面中心。
			anchor.global_position = points[index]
			_field.register_light(anchor, LightField.Tone.RED, radius * 4.45, Vector2(0.0, -radius * 0.46),
				anchor, radius * 4.75, radius * 0.24, 0.0, false, true)
	_batch.multimesh.instance_count = points.size()
	set_frame(points, 0.0, 0.0, 0.0, 0.0)

## 接收本步的 [param points]、下落 [param reach]、柱身 [param shaft] 与地面 [param incident]。
## [param age] 为放手后的战斗秒数，真实光照与柱身将在同一渲染帧读到此状态。
func set_frame(points: PackedVector2Array, reach: float, shaft: float, incident: float, age: float) -> void:
	_points = points
	_reach = reach
	_shaft = shaft
	_incident = incident
	_age = age
	if age >= _impact_at:
		ground.track(points)

## 在 [param age] 首次触地时标记局部冲击；[param quake] 为同帧的全场地鸣。
func play_impact(age: float, quake: bool) -> void:
	_impact_at = age
	if quake:
		_quake.bus = SoundManager.spatial_sfx_bus()
		_quake.play()

## 停止追随接触点，让最后一帧的光柱、照明和投影一起自然退出。
func finish() -> void:
	if is_instance_valid(ground):
		ground.end_trace()
	if not _points.is_empty() and _releasing < 0.0:
		_releasing = 0.0

## 战斗离开活动阶段时立即回收场景光和音效。
func clear() -> void:
	_release_lights()
	ground.clear_fissures()
	if _quake.playing:
		_quake.stop()

## 相机更新后用 [param delta] 秒推进原有退光，合并收到的物理轨迹后再刷新网格。
func present_frame(delta: float) -> void:
	_present_beams(delta)
	ground.flush()

## 用 [param delta] 更新活动或正在收回的柱光；地表生命周期在外层提交。
func _present_beams(delta: float) -> void:
	if _points.is_empty():
		return
	if _releasing >= 0.0:
		_releasing += delta
		if _releasing >= RELEASE_SECONDS:
			_release_lights()
			return
	var clock: float = _age + maxf(0.0, _releasing) # 正常扫掠结束后允许退场余辉继续流动。
	var since_impact: float = maxf(-1.0, clock - _impact_at) # 石砖层与柱身读取同一撞地时间。
	var release: float = maxf(0.0, _releasing / RELEASE_SECONDS) # 整轮结束或中断时的回收进度。
	_batch.transform = get_global_transform_with_canvas().affine_inverse() * _world.get_canvas_transform()
	var mesh: MultiMesh = _batch.multimesh # 共用一张光束材质，运动不创建绘制节点。
	var half_size: Vector2 = _radius * BEAM_SCALE # 窗口下沿留有贴地反光。
	var has_owner: bool = is_instance_valid(_owner_foot) and Occlusion.bind_pose(_owner_pose, _material, get_viewport_rect()) # 先用本帧相机定位对应的动画帧。
	var separation: float = _points[0].distance_to(_points[1]) # 相邻柱底间距从零开始连续增长。
	var split: float = lerpf(0.26, 1.0, smoothstep(_radius * 0.22, _radius * 1.65, separation)) # 初始合为一道，再自然分出六束。
	var has_lights: bool = is_instance_valid(_field) # 光柱和地表可以单独渲染在常亮战场。
	for index: int in range(_points.size()): # 第 i 盏灯与第 i 根柱身逐帧使用相同的地面接触点。
		var point: Vector2 = _points[index] # 连续碰撞也使用此坐标。
		var outside: float = point.distance_to(point.clamp(_floor.position, _floor.end)) # 光柱离开棋盘后仍可在画面内完成收束。
		var edge_release: float = clampf(inverse_lerp(_radius * 1.12, _radius * 4.75, outside), 0.0, 1.0) # 先扫完整个格子，再拉起柱尖。
		var retreat: float = maxf(release, edge_release) # 每根离场的柱体和整轮收尾共用回收姿态。
		var lift: float = smoothstep(0.11, 0.66, retreat) # 先绷紧，随后从石砖快速抽回高处。
		var body: float = _shaft * (1.0 - smoothstep(0.42, 0.80, retreat)) # 柱体先走，地面留有短暂余红。
		var incident: float = _incident * (1.0 - smoothstep(0.29, 1.0, retreat)) # 真光照和柱底余辉共用退场包络。
		if has_lights:
			var anchor: Marker2D = _anchors[index] # 真实投影垂足随柱底移动。
			anchor.global_position = point
			_field.set_light_intensity(anchor.get_instance_id(), LightField.Tone.RED, incident * sqrt(split))
		var center: Vector2 = point - Vector2(0.0, half_size.y * GROUND_Y) # 下沿精确落在真实接触点。
		mesh.set_instance_transform_2d(index, Transform2D(0.0, half_size, 0.0, center))
		var behind: float = 0.0 # 与脚点同深或更远的柱体被本体原画遮挡。
		if has_owner:
			behind = 1.0 - smoothstep(0.0, _radius * 0.40, point.y - _owner_foot.global_position.y)
		mesh.set_instance_color(index, Color(retreat, 1.0, 1.0, behind))
		mesh.set_instance_custom_data(index, Color(_reach * (1.0 - 0.94 * lift), body * split,
			incident * split, float(index) / _points.size()))
	mesh.visible_instance_count = _points.size()
	_material.set_shader_parameter(&"flow_time", clock)
	_material.set_shader_parameter(&"seconds_after_impact", since_impact)
	ground.present(_points[0], since_impact)

## 撤销残留光圈并让显示批次休眠。
func _release_lights() -> void:
	if _points.is_empty():
		return
	if is_instance_valid(_field):
		for index: int in range(_points.size()): # 声音尾部由播放器自己的流完成，不延长灯的生命周期。
			if is_instance_valid(_anchors[index]):
				_field.unregister_light(_anchors[index].get_instance_id())
	if is_instance_valid(_batch):
		_batch.multimesh.visible_instance_count = 0
	_points.clear()
	_owner_foot = null
	_owner_pose = null


## 仅轨道销毁时释放战场上的锚点；普通施法结束继续复用池。
func _exit_tree() -> void:
	_release_lights()
	for anchor: Marker2D in _anchors: # 世界根拥有这些节点，轨道离场时显式交还。
		if is_instance_valid(anchor):
			anchor.queue_free()
	_anchors.clear()
