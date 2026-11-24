## 四分之一分辨率的可见性光场。各灯共用投影，红色与普通照明分别合成。
extends SubViewport

## 可复用的地面剪影批处理器。
const ShadowProjection = preload("res://scripts/battle/environment/battle_shadow_projection.gd")
## 共享灯的世界位置、视觉位置与衰减参数。
const LightSource = preload("res://scripts/battle/environment/battle_light_source.gd")
## 遮挡局部图集的格尺寸。
const Ground = preload("res://scripts/battle/environment/battle_shadow_ground.gd")
## 冷光先绘制，暖光与演出白光共用正常遮罩；红光使用独立遮罩。
enum Tone { COOL, WARM, RED, WHITE }
## 每个遮罩像素对应的主视口像素数。
const DOWNSCALE := 4.0
## 普通暖光占据遮罩的下半段。合成取回原亮度，保留空间给强白光。
const WARM_RADIANCE_SCALE := 0.52

## 可选地面投影器，提交局部遮挡图集后才打包灯光批次。
@export var shadow_projection: ShadowProjection

## 按色调及实例 ID 登记，同色灯保持插入顺序。
var _sources: Array[Dictionary] = [{}, {}, {}, {}]
## 主视口中实际有效的光源，光场描绘和塑像换样共同使用。
var _visible_lights: Array[LightSource] = []
## 光圈共享的二维网格及其边缘材质。
@onready var _batch: MultiMeshInstance2D = $LightBatch
## 有可见红光时才刷新，与主遮罩保持同一采样网格。
@onready var _red_mask: SubViewport = $RedMask
## 复用投影纹理及灯片材质，保留红光自己的覆盖率。
@onready var _red_batch: MultiMeshInstance2D = $RedMask/LightBatch

## 为灯光批次绑定当前战场的遮挡图集。
func _ready() -> void:
	var material := _batch.material as ShaderMaterial # 场景独占的灯片材质。
	material.set_shader_parameter(&"edge_margin", LightSource.EDGE_MARGIN)
	material.set_shader_parameter(&"footprint_feather", LightSource.FOOTPRINT_FEATHER)
	material.set_shader_parameter(&"warm_radiance_scale", WARM_RADIANCE_SCALE)
	if shadow_projection != null:
		material.set_shader_parameter(&"shadow_mask", shadow_projection.mask_texture())
		material.set_shader_parameter(&"shadow_grid", Vector2(Ground.LIGHT_GRID))
		material.set_shader_parameter(&"shadow_tile_size", float(Ground.LIGHT_TILE))

## [param enabled] 为 false 时同时停用两张遮罩；恢复时由可见灯源决定是否刷新红光。
func set_rendering(enabled: bool) -> void:
	var mode: SubViewport.UpdateMode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED # 常亮和暂停时停用主遮罩。
	if render_target_update_mode != mode:
		render_target_update_mode = mode
	if not enabled and _red_mask.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		_red_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED

## 返回红光遮罩，供战场单独设定红光色调与曝光。
func red_texture() -> ViewportTexture:
	return _red_mask.get_texture()

## 登记 [param anchor] 和 [param tone]。[param radius] 为可见外沿，单位为世界像素。
## [param offset] 是锚点局部偏移。只有给出 [param ground_anchor] 和 [param height] 才生成投影。
## [param source_radius] 描述虚拟光源半径，[param intensity] 是零至一权重。
## [param affects_gameplay] 控制棋盘查询，[param shadow_priority] 优先分配投影格。
## 无效或已登记时返回 false。
func register_light(anchor: Node2D, tone: Tone, radius: float, offset: Vector2 = Vector2.ZERO,
		ground_anchor: Node2D = null, height: float = 0.0, source_radius: float = 0.0,
		intensity: float = 1.0, affects_gameplay: bool = true, shadow_priority: bool = false) -> bool:
	var id: int = anchor.get_instance_id() # 本场景内的稳定来源标识。
	if radius <= 0.0 or _sources[tone].has(id):
		return false
	var source := LightSource.new() # 发光点与垂足随实体移动，标定数据只设置一次。
	source.id = id
	source.anchor = anchor
	source.offset = offset
	source.ground_anchor = ground_anchor
	source.radius = radius
	source.reach = radius * LightSource.EDGE_MARGIN
	source.tone = tone
	source.intensity = clampf(intensity, 0.0, 1.0)
	source.affects_gameplay = affects_gameplay
	source.shadow_priority = shadow_priority
	source.seed = float(id % 997) / 997.0
	source.height = height if tone != Tone.COOL else 0.0
	source.source_radius = maxf(0.0, source_radius)
	_sources[tone][id] = source
	return true

## 更新 [param tone] 下登记的 [param id] 的 [param intensity]，零亮度会自然离开投影及绘制批次。
func set_light_intensity(id: int, tone: Tone, intensity: float) -> void:
	var source: LightSource = _sources[tone].get(id) # 实例参数留在原登记中，避免动画期间重复分配。
	if source != null:
		source.intensity = clampf(intensity, 0.0, 1.0)

## 更新 [param id] 的红灯。参数为发光偏移 [param offset]、名义半径 [param radius] 与投影高度 [param height]。
## [param footprint] 为可选世界范围。[param spread] 控制扩张的能量分布，[param absorbing] 衰减附近暖光表现。
func set_red_light_shape(id: int, offset: Vector2, radius: float, height: float,
		footprint: Rect2 = Rect2(), spread: float = 0.0, absorbing: bool = false) -> void:
	var source: LightSource = _sources[Tone.RED].get(id) # 保留同一光源身份，避免切换影子的主灯。
	if source == null:
		return
	source.offset = offset
	source.radius = radius
	source.reach = radius * LightSource.EDGE_MARGIN
	source.height = height
	source.footprint = footprint
	source.spread = clampf(spread, 0.0, 1.0)
	source.absorbing = absorbing

## 同步撤销 [param id]，下一次光场绘制立即收回其可见范围。
func unregister_light(id: int) -> void:
	for sources: Dictionary in _sources: # 各色调共用来源身份。
		var source: LightSource = sources.get(id) # 角色可能仍持有上一帧主灯引用。
		if source != null:
			source.shadow_slot = -1
		sources.erase(id)

## 使用 [param bounds] 和 [param world_to_view] 将世界光圈投到低分辨率视口。
## [param elapsed] 为累计战斗秒数，供共享剪影图集限制姿态刷新频率。
## [param single_frame] 在战斗退场时刷新一次暂停后的最终遮罩。
## 返回本帧是否有可见的红灯。
func render_lights(bounds: Rect2, world_to_view: Transform2D, elapsed: float, single_frame: bool = false) -> bool:
	var target_size := Vector2i((bounds.size / DOWNSCALE).ceil()).max(Vector2i(2, 2)) # 每轴保留固定采样密度。
	if size != target_size:
		size = target_size
	var field_bounds := Rect2(Vector2.ZERO, Vector2(size)) # 可见遮罩区域，离屏光源无需提交。
	var ratio := Vector2(size) / bounds.size # 主视口单位转换为光场像素。
	var projection := Transform2D(0.0, ratio, 0.0, -bounds.position * ratio) * world_to_view # 含相机平移和缩放。
	var regular_mesh: MultiMesh = _batch.multimesh # 冷光和暖光共用主遮罩批次。
	var red_mesh: MultiMesh = _red_batch.multimesh # 红光使用相同几何提交到独立遮罩。
	var needed: int = _sources[Tone.COOL].size() + _sources[Tone.WARM].size() + _sources[Tone.WHITE].size() # 主遮罩实例上限。
	if regular_mesh.instance_count < needed:
		regular_mesh.instance_count = maxi(needed, regular_mesh.instance_count * 2)
	var red_needed: int = _sources[Tone.RED].size() # 红灯批次的容量独立于普通灯的数量。
	if red_mesh.instance_count < red_needed:
		red_mesh.instance_count = maxi(red_needed, red_mesh.instance_count * 2)
	var world_bounds: Rect2 = projection.affine_inverse() * field_bounds # 用世界包围盒保守剔除离屏灯。
	_collect(world_bounds)
	var masked: bool = shadow_projection != null and shadow_projection.render_shadows(projection, field_bounds, _visible_lights, elapsed) # 本帧灯格是否有效。
	var regular_count := 0 # 主遮罩已提交的实例数。
	var red_count := 0 # 红光遮罩已提交的实例数。
	for light: LightSource in _visible_lights: # 两张遮罩都各自按原有灯序提交。
		var is_red: bool = light.tone == Tone.RED # 红光与暖光共享灯片衰减与遮挡计算。
		var mesh: MultiMesh = red_mesh if is_red else regular_mesh # 只写入该光源所属的遮罩。
		var index: int = red_count if is_red else regular_count # 各批次的连续索引。
		var quad := Transform2D(0.0, Vector2.ONE * light.reach, 0.0, light.center) # 以可见灯罩为光圈中心。
		var encoded_slot: int = light.shadow_slot + 1 if masked else 0 # 零表示整体透光。
		mesh.set_instance_transform_2d(index, projection * quad)
		var profile: float = float(light.tone != Tone.COOL) # 冷光为零，标准红光保留原编码。
		if light.tone == Tone.WARM:
			profile = 0.96875 if light.affects_gameplay else 0.90625 # 路灯花和演出暖灯使用独立的渲染亮度档。
		elif light.tone == Tone.WHITE:
			profile = 0.1875 # 按暖灯衰减与投影，保留完整光强。
		if is_red and light.footprint.has_area():
			profile = 0.75 if light.absorbing else 0.375 + 0.20 * light.spread # 散晕的渐变区间与吸收档分开。
			var quad_origin: Vector2 = light.center - Vector2.ONE * light.reach # 裁剪边界写入灯片本身的坐标。
			var low: Vector2 = (light.footprint.position - quad_origin) / (light.reach * 2.0) # 羽化前的左上边。
			var high: Vector2 = (light.footprint.end - quad_origin) / (light.reach * 2.0) # 羽化前的右下边。
			mesh.set_instance_color(index, Color(clampf(low.x, 0.0, 1.0), clampf(low.y, 0.0, 1.0),
				clampf(high.x, 0.0, 1.0), clampf(high.y, 0.0, 1.0)))
		mesh.set_instance_custom_data(index, Color(profile, light.seed, encoded_slot / 255.0, light.intensity))
		if is_red:
			red_count += 1
		else:
			regular_count += 1
	regular_mesh.visible_instance_count = regular_count
	red_mesh.visible_instance_count = red_count
	if red_count > 0 and _red_mask.size != size:
		_red_mask.size = size
	var red_mode: SubViewport.UpdateMode = SubViewport.UPDATE_DISABLED # 没有有效红灯时停用独立遮罩。
	if red_count > 0:
		red_mode = SubViewport.UPDATE_ONCE if single_frame else SubViewport.UPDATE_ALWAYS
	# UPDATE_ONCE 由渲染服务器消费。冻结中每次提交都要重新请求，属性仍可能保留旧枚举。
	if (single_frame and red_count > 0) or _red_mask.render_target_update_mode != red_mode:
		_red_mask.render_target_update_mode = red_mode
	if single_frame:
		render_target_update_mode = SubViewport.UPDATE_ONCE
	return red_count > 0

## 按 [param world_bounds] 收集屏幕所需灯光，刷新椭圆边界与平面垂足。
func _collect(world_bounds: Rect2) -> void:
	_visible_lights.clear()
	for sources: Dictionary in _sources: # 主遮罩内仍先写冷光，再按覆盖率叠入暖光。
		for id: int in sources.keys(): # 允许回收已经释放的来源。
			var source: LightSource = sources[id] # 所有灯都从无影槽位开始本帧。
			source.shadow_slot = -1
			if not is_instance_valid(source.anchor):
				sources.erase(id)
				continue
			if not source.refresh_center():
				continue
			if not world_bounds.grow(source.reach).has_point(source.center):
				continue
			if is_instance_valid(source.ground_anchor):
				source.ground = source.ground_anchor.global_position
			_visible_lights.append(source)

## 返回仍发光的暖灯。[param gameplay_only] 为 true 时只采样参与棋盘判定的来源。
## 镜头裁剪不影响实际覆盖。
func warm_lights(gameplay_only: bool = false) -> Array[LightSource]:
	var lights: Array[LightSource] = [] # 冷色探查光不进入这组来源。
	for light: LightSource in _sources[Tone.WARM].values(): # 刷新真实灯罩的中心，换格或死亡即时反映。
		if (not gameplay_only or light.affects_gameplay) and light.refresh_center():
			lights.append(light)
	return lights

## 返回最近一次绘制的光是否可能碰到 [param area] 的世界边界。
## 使用保守半径，让低亮度边缘处的结构也等到完全离开光圈再改变。
func lights_intersect(area: Rect2) -> bool:
	for light: LightSource in _visible_lights: # 仅遍历本帧还在绘制的光源。
		if light.center.distance_squared_to(light.center.clamp(area.position, area.end)) <= light.reach * light.reach:
			return true
	return false
