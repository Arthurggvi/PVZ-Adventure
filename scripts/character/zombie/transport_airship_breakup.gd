## 冻结击毁瞬间的原画帧，随后按真实分区抛出舰壳。
extends Node2D
class_name TransportAirshipBreakup

## 从真实战斗归属取得花园飞艇爆炸能力。
const VehicleDeathBlast := preload("res://scripts/character/zombie/vehicle_death_blast.gd")
## 花园飞艇火花与舰壳共用的解析阻力积分。
const Motion := preload("res://scripts/adventure/garden_airship/garden_airship_blast_motion.gd")
## 读取舰壳当前的实际画布深度。
const DeathPose := preload("res://scripts/adventure/garden_airship/garden_airship_death_pose.gd")
## 保留落点和舱门的完整姿态，再进入飞散，单位为秒。
const SPLIT_AT: float = 0.13
## 初始加速度过渡的时间常数，避免碎块首帧突然跳离。
const ACCELERATION_RAMP: float = 0.065
## 横向冲量衰减率，单位为每秒。
const AIR_DRAG: float = 1.28
## 素材坐标下的下落加速度，单位为像素每二次秒。
const GRAVITY: float = 365.0
## 零件的表现寿命，单位为秒。
const LIFETIME: float = 2.2
## 开始逐渐隐去的时间，完整保留飞散与下落。
const FADE_AT: float = 1.54
## 断裂爆心相对完整画帧的坐标，单位为素材像素。
const BURST_POINT: Vector2 = Vector2(-9.0, 9.0)
## 花园飞艇舰壳所受的垂直加速度，单位为 1920 参考像素/战斗秒²。
const FRAGMENT_GRAVITY_REF: float = 490.0
## 上层舰壳在 [constant PARTS] 中的索引，供燃烧尾迹和次爆定位。
const UPPER_HULL: int = 5
## 龙骨与活动舱门在 [constant PARTS] 中的索引，供另一处次爆定位。
const CARGO_HULL: int = 11
## 复用原画的旋翼、舱体和装甲分区。位置与抛速用画幅像素；阻力时间常数用战斗秒。
const PARTS: Array[Dictionary] = [
	{"id": 16.0, "area": Rect2(13, 23, 77, 63), "pivot": Vector2(51.4, 54.8), "kick": Vector2(-114, -122), "spin": 176.0, "tau": 0.11}, # 左旋翼
	{"id": 32.0, "area": Rect2(59, 42, 80, 49), "pivot": Vector2(101.1, 69.9), "kick": Vector2(-21, -162), "spin": -119.0, "tau": 0.24}, # 驾驶舱
	{"id": 48.0, "area": Rect2(185, 54, 30, 44), "pivot": Vector2(198.1, 78.1), "kick": Vector2(120, -101), "spin": -260.0, "tau": 0.10}, # 尾翼
	{"id": 64.0, "area": Rect2(150, 54, 62, 93), "pivot": Vector2(176.0, 105.0), "kick": Vector2(133, -79), "spin": 205.0, "tau": 0.14}, # 右旋翼
	{"id": 80.0, "area": Rect2(9, 77, 85, 39), "pivot": Vector2(49.7, 96.3), "kick": Vector2(-138, -57), "spin": -150.0, "tau": 0.19}, # 机头上缘
	{"id": 96.0, "area": Rect2(87, 59, 76, 61), "pivot": Vector2(131.9, 94.3), "kick": Vector2(36, -94), "spin": 122.0, "tau": 0.28}, # 上层舰壳
	{"id": 112.0, "area": Rect2(182, 144, 3, 3), "pivot": Vector2(183.0, 145.0), "kick": Vector2(146, -21), "spin": -230.0, "tau": 0.09}, # 右翼边缘
	{"id": 128.0, "area": Rect2(10, 94, 90, 48), "pivot": Vector2(54.6, 120.1), "kick": Vector2(-120, -27), "spin": 190.0, "tau": 0.18}, # 机头格栅
	{"id": 144.0, "area": Rect2(12, 134, 56, 52), "pivot": Vector2(42.3, 157.2), "kick": Vector2(-88, 13), "spin": -85.0, "tau": 0.26}, # 前装甲
	{"id": 160.0, "area": Rect2(51, 103, 62, 83), "pivot": Vector2(82.6, 148.3), "kick": Vector2(-39, 34), "spin": 112.0, "tau": 0.23}, # 徽章装甲
	{"id": 176.0, "area": Rect2(100, 114, 82, 66), "pivot": Vector2(134.0, 141.0), "kick": Vector2(81, 17), "spin": -147.0, "tau": 0.29}, # 舷窗装甲
	{"id": 192.0, "area": Rect2(65, 150, 102, 65), "pivot": Vector2(122.7, 183.8), "kick": Vector2(21, 61), "spin": 188.0, "tau": 0.34}, # 龙骨与活动舱门
]

## 与活体帧相同画幅的离散分区图，每个标签只归属于一块零件。
@export var fracture_ids: Texture2D
## 零件以真实图集像素取样，分区接缝不混入相邻零件。
@export var fracture_shader: Shader
## 爆芯、火星、烟尘和爆声复用项目的空中爆炸。
@export var impact_scene: PackedScene

## 舰壳真正分开时播一次，金属余音随碎块演出回收。
@onready var _fracture_audio: AudioStreamPlayer2D = $FractureAudio

## 各零件持有同一张图集，仅自己的裁边、枢轴和运动不同。
class Piece:
	## 原画分区裁出的精灵。
	var sprite: Sprite2D
	## 飞散前的枢轴位置，以当前机身画幅中心为原点。
	var rest: Vector2
	## 爆压响应，单位为像素每秒。
	var kick: Vector2
	## 原裁片的局部翻滚速度，单位为度每秒。
	var spin: float
	## 飞艇气流的阻力时间常数，单位为秒；薄板低于重舰壳。
	var drag_time: float
	## 断裂交接后唯一的世界速度，单位为世界像素/战斗秒。
	var world_velocity: Vector2
	## 断裂交接后含舰壳惯性的角速度，单位为弧度/战斗秒。
	var world_spin: float

## 击毁初段仍使用一张连贯的机身画帧。
var _intact: Sprite2D
## 飞散时所有可独立转动的机身零件。
var _pieces: Array[Piece] = []
## 当前画帧经过受击状态与环境照明后的颜色。
var _tint: Color = Color.WHITE
## 从本次击毁开始累积的场景秒数。
var _age: float = 0.0
## 原地的音效节点和随风的舰壳分开挂载；普通战场可继续用本节点作为美术根。
var _visual_root: Node2D
## 由原击毁秒数确保舰壳解体和爆点只启动一次。
var _split_started: bool = false
## 完整舰壳的扫离代理，开始断裂时读其真实世界速度。
var _sweep: Node2D
## 花园飞艇当局爆炸和气流的共享入口。
var _blast_director: Node
## 锁定进入解体时选择的演出路径，避免服务退出后补播原地爆炸。
var _uses_airship_blast: bool = false
## 上一拍的活动舰壳世界姿态，用于估算断裂帧的实际角速度。
var _prior_visual_pose: Transform2D


## 等待角色交接当前画帧。
func _ready() -> void:
	set_process(false)


## 冻结 [param frame] 在岗机体及其当前 [param tint]，并在同一画幅拼出连续的碎块。
## [param death_visuals] 可接管绘制子树，[param velocity] 是当时的世界速度。
func begin(frame: AtlasTexture, tint: Color, death_visuals: Node = null, velocity: Vector2 = Vector2.ZERO) -> void:
	if frame == null:
		queue_free()
		return
	_tint = tint
	_blast_director = VehicleDeathBlast.find_airship(self)
	_uses_airship_blast = is_instance_valid(_blast_director)
	_visual_root = self
	if death_visuals != null or _uses_airship_blast:
		_visual_root = Node2D.new()
		add_child(_visual_root)
	_intact = Sprite2D.new()
	_intact.texture = frame
	_intact.modulate = _tint
	_visual_root.add_child(_intact)
	var atlas_size: Vector2 = frame.atlas.get_size() # Shader 使用大图集坐标反推当前画幅。
	var uv_origin: Vector2 = frame.region.position / atlas_size # 当前画幅的左上 UV。
	var uv_size: Vector2 = frame.region.size / atlas_size # 当前画幅的 UV 跨度。
	var frame_uv := Vector4(uv_origin.x, uv_origin.y, uv_size.x, uv_size.y) # 所有零件使用同一画幅。
	for part: Dictionary in PARTS: # 每个分区只裁切它可能拥有的可见像素范围。
		var area: Rect2 = part["area"] # 包含开舱与悬停时的最大绘制区域。
		var pivot: Vector2 = part["pivot"] # 原画区域的质心，决定翻滚中心。
		var cutout := ShaderMaterial.new() # 各精灵有独立标签，同一 shader 与贴图资源。
		cutout.shader = fracture_shader
		cutout.set_shader_parameter(&"fracture_ids", fracture_ids)
		cutout.set_shader_parameter(&"frame_uv", frame_uv)
		cutout.set_shader_parameter(&"piece_id", part["id"])
		var sprite := Sprite2D.new() # 裁切到局部小矩形，避免每片重新绘制整幅机体。
		sprite.texture = frame.atlas
		sprite.region_enabled = true
		sprite.region_filter_clip_enabled = true
		sprite.region_rect = Rect2(frame.region.position + area.position, area.size)
		sprite.centered = false
		sprite.offset = area.position - pivot
		sprite.position = pivot - frame.region.size * 0.5
		sprite.modulate = _tint
		sprite.material = cutout
		sprite.hide()
		_visual_root.add_child(sprite)
		var piece := Piece.new() # 保存初始位姿，逐帧运动只采样实际经过时间。
		piece.sprite = sprite
		piece.rest = sprite.position
		piece.kick = part["kick"]
		piece.spin = part["spin"]
		piece.drag_time = part["tau"]
		_pieces.append(piece)
	if is_instance_valid(death_visuals):
		_sweep = death_visuals.sweep_visual(_visual_root, 0.86, velocity, &"transport")
	if _uses_airship_blast:
		process_priority = 1 # 在扫离更新实际姿态后交接，先于爆炸系统读取裁片。
		_prior_visual_pose = _visual_root.global_transform
	set_process(true)


## [param delta] 为受战局暂停控制的场景秒数。起爆时所有碎片从完整画帧的原位置起动。
func _process(delta: float) -> void:
	_age += delta
	var drawing: bool = is_instance_valid(_visual_root) # 右端击毁时可见舰壳有可能早于原声场出界。
	if _age >= LIFETIME:
		if drawing and _visual_root != self:
			_visual_root.queue_free()
		queue_free()
		return
	if _uses_airship_blast:
		_process_airship(delta)
		return
	if _age < SPLIT_AT:
		if drawing:
			_pose_intact()
		return
	if not _split_started:
		_split_started = true
		if drawing:
			_intact.hide()
			for piece: Piece in _pieces: # 完整画面无缝切换为同纹理的各零件。
				piece.sprite.show()
		SoundManager.play_attached_sfx(_fracture_audio, &"transport_fracture", 1)
		_start_impact()
	if not drawing:
		return
	var seconds: float = _age - SPLIT_AT # 每块碎片都从组装好的原点开始计算。
	var drift: float = seconds - ACCELERATION_RAMP * (1.0 - exp(-seconds / ACCELERATION_RAMP)) # 渐增的起飞冲量。
	var horizontal: float = (1.0 - exp(-AIR_DRAG * drift)) / AIR_DRAG # 横向受阻力逐渐减速。
	var fall: float = 0.5 * GRAVITY * seconds * seconds # 纵向重力让碎块在抛起后自然下坠。
	var opacity: float = _tint.a * (1.0 - smoothstep(FADE_AT, LIFETIME, _age)) # 尾段再逐渐淡去。
	for piece: Piece in _pieces: # 碎块独立翻滚，枢轴着色和舱门画面保持连续。
		piece.sprite.position = piece.rest + Vector2(piece.kick.x * horizontal, piece.kick.y * drift + fall)
		piece.sprite.rotation_degrees = piece.spin * drift
		piece.sprite.modulate.a = opacity


## 完整画帧在断裂之前短促抬动，临近切换时回到裁片拼接的原位。
func _pose_intact() -> void:
	var tension: float = sin(PI * _age / SPLIT_AT) # 由当前变形进度表现爆压积累。
	_intact.position.y = -2.0 * tension * tension
	_intact.rotation = 0.018 * tension * sin(TAU * _age / SPLIT_AT)
	_intact.modulate = _tint * Color(1.0 + 0.23 * tension, 1.0 + 0.08 * tension, 1.0)


## [param delta] 为场景秒。完整舰壳先由扫离代理推进，断裂后改由本节点独立推进全部原裁片。
func _process_airship(delta: float) -> void:
	if _split_started:
		_advance_world_pieces(delta)
	elif not is_instance_valid(_visual_root) or not _visual_root.is_inside_tree() or _visual_root.is_queued_for_deletion() \
			or (is_instance_valid(_sweep) and _sweep.is_queued_for_deletion()):
		queue_free()
	elif _age < SPLIT_AT:
		_pose_intact()
		_prior_visual_pose = _visual_root.global_transform
	else:
		_split_started = true
		_split_in_world(delta)


## 交接当前世界姿态与上一拍间隔 [param delta]，从真实舰体位置发出主爆及断裂声。
func _split_in_world(delta: float) -> void:
	var pose: Transform2D = _visual_root.global_transform # 扫离刚完成的完整舰壳世界姿态。
	var center: Vector2 = pose * BURST_POINT # 完整画帧的断裂爆点，含原翻转、缩放与旋转。
	var depth: int = DeathPose.absolute_z(_visual_root) # 原战斗画布深度在重新挂载前保存。
	var sample_time: float = maxf(delta, 0.001) # 防止无效的帧长放大角速度。
	var linear: Vector2 = _sweep.get(&"world_velocity") if is_instance_valid(_sweep) \
		else (pose.origin - _prior_visual_pose.origin) / sample_time # 扫离被额度拒绝时使用现有舰壳的实际位移。
	var angular: float = angle_difference(_prior_visual_pose.get_rotation(), pose.get_rotation()) / sample_time # 继承阵风所改变的实际翻滚速度。
	var facing: float = signf(pose.determinant()) # 镜像机体的局部翻滚在世界中反向。
	_intact.hide()
	for piece: Piece in _pieces: # 保留各裁片实际世界位置及其原纹理和遮罩。
		var lever: Vector2 = piece.sprite.global_position - pose.origin # 原枢轴相对舰壳轴心的世界偏移。
		var tangent := Vector2(-lever.y, lever.x) * angular # 把舰壳角速度转为该枢轴的切向速度。
		piece.world_velocity = linear + tangent + pose.basis_xform(piece.kick)
		piece.world_spin = angular + facing * deg_to_rad(piece.spin)
		piece.sprite.reparent(self, true)
		piece.sprite.show()
	_visual_root.queue_free() # 原代理失去可见机体后由扫离池回收。
	if is_instance_valid(_blast_director):
		var lever: Vector2 = center - pose.origin # 按机舱爆点而非空载根继承转动的速度。
		var velocity: Vector2 = linear + Vector2(-lever.y, lever.x) * angular # 机舱实际起爆速度，单位为世界像素/秒。
		var burst_id: int = _blast_director.start_burst(&"transport", center, pose.x.length() * 0.46, velocity, depth) # 唯一主爆。
		if burst_id > 0:
			var hull: Sprite2D = _pieces[UPPER_HULL].sprite # 以实际舰壳作持续燃烧的代表声源。
			var anchors: Array[Node2D] = [hull, _pieces[CARGO_HULL].sprite] # 少量次爆分别随两块真实裁片。
			_blast_director.track_burst(burst_id, hull, PackedVector2Array([Vector2.ZERO, Vector2.ZERO]), anchors)


## [param delta] 推进已交接的裁片。每片只接受一次气流、重力和角速度积分。
func _advance_world_pieces(delta: float) -> void:
	var has_flow: bool = is_instance_valid(_blast_director) # 服务离树时让独立余片自然回收。
	var factor: float = _blast_director.blast_world_factor() if has_flow else 1.0 # 参考速度和加速度只换算一次。
	var gravity: Vector2 = Vector2.DOWN * FRAGMENT_GRAVITY_REF * factor # 重力用世界像素每战斗秒²。
	var opacity: float = _tint.a * (1.0 - smoothstep(FADE_AT, LIFETIME, _age)) # 保留原裁片的尾段淡去。
	var any_visible: bool = false # 全部裁片通过扩展视口后，可提前回收整批。
	for piece: Piece in _pieces: # 轻板与重舰壳在同一气流里使用各自的阻力时间。
		if not is_instance_valid(piece.sprite) or piece.sprite.is_queued_for_deletion():
			continue
		var pose: Transform2D = piece.sprite.global_transform # 保留原裁片的镜像、缩放及全部基向量。
		var airflow: Vector2 = _blast_director.fragment_airflow(pose.origin, factor) if has_flow else Vector2.ZERO # 在这一片的实际世界位置取风。
		var motion: Vector4 = Motion.integrate(piece.world_velocity, airflow, gravity, piece.drag_time, delta) # 世界位移和末速度。
		var roll: float = piece.world_spin * delta # 只旋转裁片基，枢轴由独立位移驱动。
		pose.x = pose.x.rotated(roll)
		pose.y = pose.y.rotated(roll)
		pose.origin += Vector2(motion.x, motion.y)
		piece.world_velocity = Vector2(motion.z, motion.w)
		piece.sprite.global_transform = pose
		piece.sprite.modulate.a = opacity
		any_visible = any_visible or not has_flow or _blast_director.is_in_view(pose.origin, 180.0)
	if not any_visible:
		queue_free()


## 普通战场在舰舱内部播放原来的空中爆炸。
func _start_impact() -> void:
	var center: Vector2 = to_global(BURST_POINT) # 舰腹上方的爆心，随原机身方向变换。
	var game: MainGameManager = Global.main_game # 只为当前战斗申请相邻爆光的共用预算。
	var budget: BattleBlastFxBudget = game.blast_fx_budget if is_instance_valid(game) and game.is_ancestor_of(self) else null # 展示场景未配置预算。
	var kind: StringName = &"transport_airship_breakup" # 只合并同种且位置靠近的爆光。
	if budget != null and not budget.can_start(kind, center):
		return
	var impact := impact_scene.instantiate() as ArbiterXImpact # 火星和声场独立于舰壳碎块的生命周期。
	impact.z_index = z_index
	get_parent().add_child(impact)
	impact.global_position = center
	if budget != null:
		budget.track(impact, kind, center)
	impact.play_airburst(center, global_transform.x.length() * 0.46, PackedVector2Array())
