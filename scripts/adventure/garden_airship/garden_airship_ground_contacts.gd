## 只为花园飞艇接入角色的环境色与原生阴影。移动甲板决定接收面，角色状态材质各自独立。
extends RefCounted

## 承重平台的草皮范围，单位为平台局部世界像素。
const AirshipDeck := preload("res://scripts/adventure/garden_airship_deck.gd")
## 现有阴影的边界裁切及色调，两种状态共用同一个着色器。
const CONTACT_SHADER := preload("res://shaders/adventure/wonderland/garden_airship_contact.gdshader")
## 着色器预留的接收平台数，与花园飞艇的八块浮台和长桥一致。
const MAX_RECEIVERS: int = 9
## 可受日照的普通实体弹药。冰、火、发光或特殊表现弹体沿用自身颜色。
const DAYLIGHT_AMMO: Array[BulletRegistry.BulletType] = [
	BulletRegistry.BulletType.Bullet001Pea,
	BulletRegistry.BulletType.Bullet007Cactus,
	BulletRegistry.BulletType.Bullet009Cabbage,
	BulletRegistry.BulletType.Bullet010Corn,
	BulletRegistry.BulletType.Bullet012Melon,
	BulletRegistry.BulletType.Bullet013Basketball,
]

## 当前棋盘上接收阴影的刚性平台。
var _surfaces: Array[BoardSurface] = []
## 对应 [_surfaces] 的各平台局部草皮矩形。
var _turf: Array[Rect2] = []
## 复用的世界坐标矩形数组，顺序为左、上、右、下。
var _world_rects := PackedVector4Array()
## 本战局的僵尸管理器，读取其现有敌我索引。
var _zombies: ZombieManager
## 普通接触阴影共享材质。
var _contact: ShaderMaterial
## 原生滞空或抬升单位共享的淡投影，仍须有接收面。
var _projection: ShaderMaterial
## 本关日照 RGB，透明度留给原有表现。
var _daylight: Color = Color.WHITE
## 当前头顶云的影心、浓度和半宽，对应地面材质的 passing_cloud。
var _passing_cloud := Vector4.ZERO
## 平台独占的材质，世界位置由着色器从实际甲板坐标读取。
var _deck_lights: Array[ShaderMaterial] = []
## 已经实际种在甲板上的单位；离树时从本局照明名单清理。
var _plants: Dictionary[int, Plant000Base] = {}

## 为 [param board] 的地块绑定已有种植信号，并用 [param zombies] 跟踪已登记角色的贴地状态。
## [param bullets] 提供普通弹体入树信号，[param daylight] 为当前关卡的日照 RGB 乘色。
## 不创建新阴影节点。使用同款接收着色器的定制阴影保留自身轮廓，只绑定甲板边界。
func setup(board: BoardRuntime, zombies: ZombieManager, bullets: Node2D, daylight: Color) -> void:
	_zombies = zombies
	_daylight = Color(daylight.r, daylight.g, daylight.b)
	_world_rects.resize(MAX_RECEIVERS)
	for surface: BoardSurface in board.surfaces.values(): # 每个平台仅上传一个接收范围。
		var deck := surface.definition as AirshipDeck # 关卡资源中的草皮，不包含扶手或吊索。
		if deck != null and _surfaces.size() < MAX_RECEIVERS:
			_surfaces.append(surface)
			var visual := surface.get_child(0) as Sprite2D if surface.get_child_count() > 0 else null # BoardSurface 将原画放在首位。
			var material := visual.material as ShaderMaterial if visual != null else null # 避免跨局修改共享资源。
			if material != null:
				_deck_lights.append(material)
			_turf.append(deck.turf_rect)
	_contact = ShaderMaterial.new()
	_contact.shader = CONTACT_SHADER
	_contact.set_shader_parameter(&"receiver_count", _surfaces.size())
	_projection = _contact.duplicate() as ShaderMaterial
	_projection.set_shader_parameter(&"footprint_scale", Vector2(0.90, 0.61))
	_projection.set_shader_parameter(&"projection_strength", 0.32)
	for cell: PlantCell in board.cells(): # 已有植物和后续种植走同一个表现入口。
		cell.signal_plant_create.connect(_bind_plants)
		_bind_plants(cell)
	_zombies.signal_zombie_created.connect(_apply_daylight)
	for zombie: Zombie000Base in _zombies.all_zombies_1d: # 初始化前已登记的实体也应用一次日照。
		_apply_daylight(zombie)
	bullets.child_entered_tree.connect(_on_projectile_entered)
	for child: Node in bullets.get_children(): # 兼容本局开始前已经入树的实体弹体。
		_on_projectile_entered(child)
	refresh()

## 刷新随动草皮的实际位置。角色材质只在首次登记或贴地状态变化时切换。
func refresh() -> void:
	var changed: bool = false # 棋盘静止时不重复上传同一组矩形。
	for index: int in _surfaces.size(): # 平台只平移，局部尺寸与世界尺寸相同。
		var rect: Rect2 = _turf[index] # 已从当前平台定义登记的接收面。
		var origin: Vector2 = _surfaces[index].to_global(rect.position) # 与角色画布共享的实际世界坐标。
		var edge: Vector2 = origin + rect.size # 接收矩形右下界。
		var bounds := Vector4(origin.x, origin.y, edge.x, edge.y) # 着色器的四条连续边界。
		if bounds != _world_rects[index]:
			_world_rects[index] = bounds
			changed = true
	if changed:
		_contact.set_shader_parameter(&"receivers", _world_rects)
		_projection.set_shader_parameter(&"receivers", _world_rects)
	for zombie: Zombie000Base in _zombies.all_zombies_1d: # 不修改生命周期、飞行旗标或碰撞。
		if not is_instance_valid(zombie) or not is_instance_valid(zombie.shadow) or zombie.shadow.use_parent_material:
			continue
		var current: Material = zombie.shadow.material # 其他视觉功能拥有的材质不接管。
		if current != null and current != _contact and current != _projection:
			var custom := current as ShaderMaterial # 车辆独立阴影共享接收着色器与甲板边界。
			if custom != null and custom.shader == CONTACT_SHADER:
				var receiving: bool = custom.get_shader_parameter(&"clip_to_receivers") # 初次加入飞艇时绑定完整接收面。
				if not receiving:
					custom.set_shader_parameter(&"receiver_count", _surfaces.size())
					custom.set_shader_parameter(&"clip_to_receivers", true)
				if changed or not receiving:
					custom.set_shader_parameter(&"receivers", _world_rects)
			continue
		var airborne: bool = zombie.is_native_airborne() or zombie.is_blover_flying_target() \
			or zombie.is_body_up_from_ground \
			or zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsJump \
			or (is_instance_valid(zombie.move_component) and zombie.move_component.is_forced_airborne()) # 跃起与抛飞同样减淡投影。
		var material: ShaderMaterial = _projection if airborne else _contact # 两档只切换共享引用。
		if current != material:
			zombie.shadow.material = material

## 处理 [param cell] 上已提交的植物和伴生植物。[param _plant_type] 由原种植信号提供。
func _bind_plants(cell: PlantCell, _plant_type: int = -1) -> void:
	for plant: Plant000Base in cell.living_plants(): # 读取真实占用，保留原阴影锚点和原动效。
		var plant_id: int = plant.get_instance_id() # 活体可能在不同甲板或承托层之间原地换父节点。
		if not _plants.has(plant_id):
			_plants[plant_id] = plant
			var departure: Callable = _check_departure.bind(plant_id) # 同一株植物在重新登记时只连接一次。
			if not plant.tree_exiting.is_connected(departure):
				plant.tree_exiting.connect(departure)
		_apply_daylight(plant)
		if is_instance_valid(plant.shadow) and plant.shadow.material == null and not plant.shadow.use_parent_material:
			plant.shadow.material = _contact


## [param plant_id] 离树后延迟核对。换父节点时 Godot 同样发离树信号，必须等甲板迁移结束。
func _check_departure(plant_id: int) -> void:
	_finish_departure.call_deferred(plant_id)

## [param plant_id] 对应植物真正离开局内才移出照明名单。
func _finish_departure(plant_id: int) -> void:
	var plant: Variant = _plants.get(plant_id) # 异步期间节点可能已经释放。
	if not is_instance_valid(plant) or not plant.is_inside_tree():
		_plants.erase(plant_id)

## [param cloud] 为真实云底投影。巡航的零值不重传材质或逐角色调色。
func apply_cloud_light(cloud: Vector4) -> void:
	if cloud == _passing_cloud:
		return
	_passing_cloud = cloud
	for material: ShaderMaterial in _deck_lights: # 每张甲板取样当前的世界坐标。
		material.set_shader_parameter(&"passing_cloud", cloud)
	for plant_id: int in _plants: # 已铲除或死亡后离树的个体在该帧结束时从名单清理。
		var plant: Variant = _plants[plant_id] # 给已排队释放的个体保留无副作用的安全检查。
		if is_instance_valid(plant):
			_apply_daylight(plant)
	for zombie: Zombie000Base in _zombies.all_zombies_1d: # 只访问本局已登记的实体。
		_apply_daylight(zombie)

## [param point] 为角色实际战场位置。与共享云影 Shader 的椭圆和冷日照色一致。
func _light_at(point: Vector2) -> Color:
	if _passing_cloud.z <= 0.001:
		return _daylight
	var center := Vector2(_passing_cloud.x, _passing_cloud.y) # 云底投影在甲板坐标的中心。
	var radius := Vector2(maxf(_passing_cloud.w, 1.0), 353.0) # 局部沿两轴的软边范围。
	var relative: Vector2 = (point - center) / radius # 椭圆归一化坐标。
	var coverage: float = (1.0 - smoothstep(0.20, 1.0, relative.length_squared())) * _passing_cloud.z # 接收的阴影权重。
	return _daylight * Color.WHITE.lerp(Color(0.73, 0.79, 0.87), coverage)

## [param character] 的身体走已有环境色通道，受击峰值和其他状态仍按身体组件原规则合成。
func _apply_daylight(character: Character000Base) -> void:
	if is_instance_valid(character) and is_instance_valid(character.body):
		character.body.set_environment_color(_light_at(character.global_position))

## [param node] 属于实际弹体容器。只有普通实体弹药在初始化结束后接受日照。
func _on_projectile_entered(node: Node) -> void:
	var ammunition := node as Bullet000NormBase # 区分普通实体弹体与独立激光和技能特效。
	if ammunition == null or ammunition.bullet_type not in DAYLIGHT_AMMO:
		return
	if ammunition.is_node_ready():
		_tint_projectile(ammunition)
	else:
		ammunition.ready.connect(_tint_projectile.bind(ammunition), CONNECT_ONE_SHOT)

## 给 [param ammunition] 的普通本体叠加日照，保留初始化阶段已有的专属色和透明度。
func _tint_projectile(ammunition: Bullet000NormBase) -> void:
	if not is_instance_valid(ammunition.body) or ammunition.finisher_highlight:
		return
	var color: Color = ammunition.body.modulate # 原有颜色乘数可能包含专属技能高光。
	if Color(color.r, color.g, color.b).is_equal_approx(Color.WHITE):
		ammunition.body.modulate = color * _daylight
