## 入场十字的柱身、地面、灯和音效。每次呈现只读取战斗已结算的物理轨迹。
extends Node2D

## 教堂现有的可见性光场和阴影图集。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 读取施法者的当前原画，用于遮住位于身后的柱芯。
const SilhouettePart = preload("res://scripts/battle/environment/battle_silhouette_part.gd")
## 柱身与石面触光复用「疯狂」的柱光材质。
const PILLAR_SHADER = preload("res://shaders/adventure/wonderland/savior_madness_pillars.gdshader")
## 教堂原有的触地低鸣。
const QUAKE_SOUND = preload("res://assets/adventure/zombies/savior/savior_madness_quake.wav")
## 四向连续命中的物理状态及着地事件。
const Attack = preload("res://scripts/character/zombie_boss/savior/savior_entry_cross_attack.gd")
## 与六柱共用的原画遮挡标定。
const Occlusion = preload("res://scripts/fx/savior_pillar_occlusion.gd")
## 与柱光材质的局部柱底位置保持一致。
const GROUND_Y := 0.88
## 柱身网格的半宽和半高，以地面接触半径为单位。
const BEAM_SCALE := Vector2(1.64, 5.55)

## 对应一组物理轨迹的绘制批次与灯源。
class View:
	## 每根柱身对应同一个发光点和地面投影垂足。
	var anchors: Array[Marker2D] = []
	## 每位救主的四根柱身共用同一套原画遮挡参数。
	var beams: MultiMeshInstance2D
	## 石面触光绘制于角色下方，与柱身共用同一个实例资源。
	var ground: MultiMeshInstance2D
	## 用于读取施法者当前原画像素的透光信息。
	var pose: SilhouettePart

## 由战场直接推进的物理结算器。
var _attack: Attack
## 每名施法者的独立绘制资源。
var _views: Dictionary[Attack.Cross, View] = {}
## 提供本场棋盘、镜头和场上实体。
var _game: MainGameManager
## 本场已有的低分辨率世界光场。
var _field: LightField
## 地面层进入世界合成，因此接触印记会被角色正常挡住。
var _ground_layer: CanvasLayer
## 共用触地节拍只响一次，遵循场景暂停和战斗倍速。
var _quake: AudioStreamPlayer
## 地面和柱身使用同尺寸的标准四边形。
var _quad := QuadMesh.new()

## [param game] 提供镜头和画布，[param field] 提供光场，[param attack] 提供轨迹生命周期。
func configure(game: MainGameManager, field: LightField, attack: Attack) -> void:
	_game = game
	_field = field
	_ground_layer = game.get_node(^"CanvasLayerBG") as CanvasLayer
	_quad.size = Vector2(2.0, 2.0)
	_quake = AudioStreamPlayer.new()
	_quake.stream = QUAKE_SOUND
	_quake.volume_db = -1.0
	add_child(_quake)
	_attack = attack
	_attack.cross_started.connect(_add_view)
	_attack.cross_ended.connect(_release_view)
	_attack.landed.connect(_impact)
	_attack.interrupted.connect(_quake.stop)

## 为 [param cross] 的四个接触点分配同一套绘制资源。
func _add_view(cross: Attack.Cross) -> void:
	var view := View.new() # 资源只由该轨迹的表现持有。
	_views[cross] = view
	var visual := cross.caster.get_node_or_null(^"Body/SaviorVisual") as AnimatedSprite2D # 使用当前实际动画作遮挡。
	if visual != null:
		view.pose = SilhouettePart.new(visual)
	var mesh := MultiMesh.new() # 柱身和石面只需写入一套位置、颜色与阶段参数。
	mesh.transform_format = MultiMesh.TRANSFORM_2D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = _quad
	mesh.instance_count = Attack.DIRECTIONS.size()
	mesh.visible_instance_count = 0
	view.beams = _add_batch(self, mesh, false)
	view.ground = _add_batch(_ground_layer, mesh, true)
	if is_instance_valid(_field):
		for _direction: Vector2 in Attack.DIRECTIONS: # 各方向独立登记到共享红光遮罩。
			var anchor := Marker2D.new() # 灯的水平原点和虚拟离地高度随这一束柱。
			_game.add_child(anchor)
			anchor.global_position = cross.origin
			view.anchors.append(anchor)
			_field.register_light(anchor, LightField.Tone.RED, cross.radius * 2.75, Vector2(0.0, -cross.radius * 0.34),
				anchor, cross.radius * 3.05, cross.radius * 0.16, 0.0, false, true)

## 相机更新后提交最新物理步的位置和受光；不查询植物或提交伤害。
func present_frame() -> void:
	if _quake.playing:
		_quake.pitch_scale = maxf(0.01, Engine.time_scale)
	var elapsed: float = _attack.age # 同一物理时钟也决定落地、收光和退场。
	var since_impact: float = elapsed - Attack.LAND_SECONDS # 以着地时刻为零。
	var retire: float = clampf((since_impact - Attack.SWEEP_SECONDS) / Attack.RELEASE_SECONDS, 0.0, 1.0) # 离地后的剩余光。
	for cross: Attack.Cross in _views: # 等待下一物理步清理的演员不再提交新画面。
		if is_instance_valid(cross.caster) and is_instance_valid(cross.caster.shadow):
			_submit_cross(cross, _views[cross], elapsed, since_impact, retire)

## 在 [param host] 上创建使用 [param mesh] 的柱身或石面批次，由 [param ground_only] 区分。
func _add_batch(host: Node, mesh: MultiMesh, ground_only: bool) -> MultiMeshInstance2D:
	var shader_material := ShaderMaterial.new() # 每位救主保有自己的原画参数与触地点。
	shader_material.shader = PILLAR_SHADER
	shader_material.set_shader_parameter(&"ground_y", GROUND_Y)
	shader_material.set_shader_parameter(&"section_in_radii", BEAM_SCALE)
	shader_material.set_shader_parameter(&"ground_only", ground_only)
	var batch := MultiMeshInstance2D.new() # 四根柱共用此批次。
	batch.multimesh = mesh
	batch.material = shader_material
	host.add_child(batch)
	return batch

## [param caster_count] 位施法者共用一次触地冲击声和镜头震动。
func _impact(caster_count: int) -> void:
	var strength: float = 1.0 + float(caster_count - 1) * 0.10 # 合演只触发一次较强的全场震动。
	_game.camera_2d.shake_once(Vector2(16.0, 27.0) * strength, 0.77, 11.0)
	_game.camera_2d.force_update_scroll()
	_quake.pitch_scale = maxf(0.01, Engine.time_scale)
	_quake.bus = SoundManager.spatial_sfx_bus()
	_quake.play()

## 将 [param cross] 的物理落点投到 [param view]。材质使用同一 [param elapsed]、触地相对时间 [param since_impact] 与退光进度 [param retire]。
func _submit_cross(cross: Attack.Cross, view: View, elapsed: float, since_impact: float, retire: float) -> void:
	var points: PackedVector2Array = cross.points # 保持柱底与已判定的线段终点一致。
	var camera: Transform2D = _game.get_canvas_transform() # 先读取同一帧已经震动后的相机。
	view.beams.transform = get_global_transform_with_canvas().affine_inverse() * camera
	var ground_canvas: Transform2D = view.ground.get_canvas_transform() # 跟随视口的背景层仍需与世界画布精确对齐。
	view.ground.transform = ground_canvas.affine_inverse() * camera
	var beam_material := view.beams.material as ShaderMaterial # 此批次只掩住本组施法者的当前姿态。
	var ground_material := view.ground.material as ShaderMaterial # 保持石面裂光在原始触地坐标。
	var masked: bool = Occlusion.bind_pose(view.pose, beam_material, get_viewport_rect()) # 已退场的原画不能继续遮挡。
	var descent: float = clampf(elapsed / Attack.LAND_SECONDS, 0.0, 1.0) # 柱尖从视野上方开始加速落下。
	var lift: float = smoothstep(0.07, 0.92, retire) # 先收紧，下沿再离开石面。
	var reach: float = lerpf(0.16, 1.0, pow(descent, 1.55)) * (1.0 - 0.91 * lift) # 实际柱尖的纵向比例。
	var impact: float = 1.0 - smoothstep(0.0, 0.17, since_impact) # 着地权重由突亮渐回稳定。
	var shaft: float = smoothstep(0.015, 0.16, elapsed) * (0.73 + 0.25 * impact) \
		* (1.0 - smoothstep(0.23, 0.94, retire)) # 下落时显形，结束前完全收束。
	var incident: float = smoothstep(-0.028, 0.0, since_impact) * (0.72 + 0.26 * impact) \
		* (1.0 - smoothstep(0.21, 1.0, retire)) # 石面和真实光在同一时刻接到柱头。
	var half_size: Vector2 = cross.radius * BEAM_SCALE # 材质接触边缘映射到同一个世界半径。
	var mesh: MultiMesh = view.beams.multimesh # 石面节点与柱身读取相同实例数据。
	var has_lights: bool = not view.anchors.is_empty() and is_instance_valid(_field) # 非教堂仍绘制柱身并结算扫掠。
	for index: int in range(points.size()): # 一盏移动灯对应一根可见柱和一条扫掠线。
		var point: Vector2 = points[index] # 这一束的当前地面位置。
		var split: float = 1.0 if index == 0 else smoothstep(cross.radius * 0.10, cross.radius * 1.26,
			point.distance_to(points[0])) # 重合时只留一道，分开时自然显出四束。
		if has_lights:
			var anchor: Marker2D = view.anchors[index] # 真实照明与阴影从此处发出。
			anchor.global_position = point
			_field.set_light_intensity(anchor.get_instance_id(), LightField.Tone.RED, incident * split)
		var behind: float = 0.0 if not masked else 1.0 - smoothstep(0.0, cross.radius * 0.37,
			point.y - cross.caster.shadow.global_position.y) # 只有更靠前的柱能覆盖原画。
		var center: Vector2 = point - Vector2(0.0, half_size.y * GROUND_Y) # 与材质中柱底的地面位置对齐。
		mesh.set_instance_transform_2d(index, Transform2D(0.0, half_size, 0.0, center))
		mesh.set_instance_color(index, Color(retire, 1.0, 1.0, behind))
		mesh.set_instance_custom_data(index, Color(reach, shaft * split, incident * split, float(index) / points.size()))
	mesh.visible_instance_count = points.size()
	beam_material.set_shader_parameter(&"flow_time", elapsed)
	beam_material.set_shader_parameter(&"seconds_after_impact", since_impact)
	ground_material.set_shader_parameter(&"seconds_after_impact", since_impact)
	ground_material.set_shader_parameter(&"impact_offset", (points[0] - cross.origin) / cross.radius)

## 释放 [param cross] 的绘制资源，可与场景卸载重复执行。
func _release_view(cross: Attack.Cross) -> void:
	var view: View = _views.get(cross) # 即使场景先退树，物理层也可重复撤销。
	if view == null:
		return
	_views.erase(cross)
	for anchor: Marker2D in view.anchors: # 先注销，再隐藏并送交场景树释放。
		if is_instance_valid(anchor):
			if is_instance_valid(_field):
				_field.unregister_light(anchor.get_instance_id())
			anchor.queue_free()
	for batch: MultiMeshInstance2D in [view.beams, view.ground]: # 背景批次不在本节点的子树中。
		if is_instance_valid(batch):
			batch.hide()
			batch.queue_free()

## 退出期间先归还挂在背景和世界根的子节点。
func _exit_tree() -> void:
	for cross: Attack.Cross in _views.keys(): # 回收时会修改原字典。
		_release_view(cross)
