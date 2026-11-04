## 两场景共用的少量环境节点容器；只管理效果生命周期及船体美术浮动。
extends Node2D

## 单效果组件，不引入全局服务。
const EFFECT = preload("res://scripts/environment/environment_sprite.gd")
## 候选叶片纹理形变，不是独立叶层或树冠物理摆动。
const LEAF_WIND = preload("res://assets/adventure/environment_fx/v2/leaf_wind_provisional.gdshader")
## 集中可调的效果配置路径。
@export_file("*.json") var configuration: String
## 明确指定静态背景；运行时构建的地图可留空，按唯一铺满画布的背景绑定。
@export_node_path("TextureRect") var background_path: NodePath
@export_group("Ocean overlays")
## 仅作用于配置中标记water的海面效果，不改动云、瀑布或毒液。
@export_range(0.0, 1.0) var water_opacity := 0.75
## 海面漂移速度，单位为原背景纹理像素/秒。
@export_range(7.0, 15.0) var water_drift_pixels_per_second := 10.0
## 淡入淡出循环中的水平漂移距离，单位为原背景像素。
@export_range(80.0, 240.0) var water_drift_distance_pixels := 160.0
## 岸边涟漪扩散周期，单位秒。
@export_range(3.0, 5.0) var shoreline_pulse_seconds := 4.0
## 只供主菜单使用的已安装海水遮罩；为空时不替换既有遮罩。
@export var water_region_mask: Texture2D
@export_group("Provisional leaf texture wind")
## 临时局部纹理风动开关，不表示完成整树或树冠摆动。
@export var provisional_leaf_wind_enabled := false
## 候选叶片纹理区域，黑色区域完全保持原像素采样。
@export var leaf_region_mask: Texture2D
## 仅在遮罩内采样偏移的幅度，单位为原图像素。
@export_range(0.0, 3.0) var leaf_amplitude_pixels := 2.0
## 已实例化的有界效果节点。
var effects: Array[AnimatedSprite2D] = []
## 总效果开关。
var enabled := true
## 云是否可以显示；关闭去云背景时必须同步停云。
var clouds_enabled := true
## 可选的原有船体节点。
var ship: Control
## 船体初始位置，用于关闭效果时恢复。
var ship_origin: Vector2
## 船体初始旋转，不改变码头或按钮。
var ship_rotation := 0.0
## 船体浮动本地时钟。
var elapsed := 0.0
## 与效果共用同一设计画布的静态背景。
var background: TextureRect
## 场景原有材质，环境层单独移除时须恢复。
var original_background_material: Material
## 本场景独立的临时叶片材质。
var leaf_material: ShaderMaterial

## 按数据创建固定数量效果，所有Node2D不参与GUI命中。
func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(configuration)) # 本场景的效果数据。
	background = _find_background()
	var display_region := _background_region() # 实际显示区，不使用窗口或素材文件名推测UV。
	var pixel_scale := display_region.size / background.texture.get_size() # 原背景像素转为画布局部像素。
	_setup_leaf_wind()
	if data.get("ship_float", false):
		ship = get_node("../ship") as Control
		ship_origin = ship.position
		ship_rotation = ship.rotation
	for entry: Dictionary in data.effects: # 仅在场景加载时分配节点。
		if entry.has("water"):
			if water_region_mask == null:
				push_warning("海面效果缺少已配置的海水遮罩，保持停用")
				continue
			entry.opacity = water_opacity
			entry.mask = water_region_mask.resource_path
			if entry.water == "surface":
				entry.speed = water_drift_pixels_per_second * float(entry.get("speed_scale", 1.0)) * pixel_scale.x
				entry.travel = water_drift_distance_pixels * pixel_scale.x
			else:
				entry.period = shoreline_pulse_seconds
		var effect := EFFECT.new() # 复用同一组件处理各类局部效果。
		effect.name = entry.name
		add_child(effect)
		effect.configure(entry, ship, display_region)
		effects.append(effect)
	# Sky/cloud effects are built at runtime; the tree must render after them.
	# The whole environment node still remains behind buildings and menu UI.
	if has_node("FoliageFX"):
		move_child($FoliageFX, get_child_count() - 1)
	visibility_changed.connect(_apply_running)
	_apply_running()

## 优先使用显式路径；匿名地图背景必须是同画布中唯一铺满的TextureRect，拒绝猜选。
func _find_background() -> TextureRect:
	if not background_path.is_empty():
		return get_node(background_path) as TextureRect
	var candidates: Array[TextureRect] = [] # 地图在环境层之前构建背景，不依赖自动生成的节点名。
	for sibling: Node in get_parent().get_children(): # 不修改地图构建或交互逻辑。
		if sibling is TextureRect and sibling.texture != null and sibling.size.is_equal_approx(get_parent().size):
			candidates.append(sibling)
	assert(candidates.size() == 1, "环境层需要唯一背景或显式background_path")
	return candidates[0]

## 当前两场景都使用居中的等比背景，位置与尺寸必须在同一画布局部空间。
func _background_region() -> Rect2:
	var native_size := background.texture.get_size() # 真实源纹理尺寸。
	var factor := minf(background.size.x / native_size.x, background.size.y / native_size.y) # 背景实际等比缩放。
	var displayed := native_size * factor # 兼容非1920源纹理，避免遮罩UV错位。
	return Rect2(background.position + (background.size - displayed) / 2.0, displayed)

## 只给原背景装配局部纹理采样材质，不移动节点、顶点、树干或建筑。
func _setup_leaf_wind() -> void:
	if leaf_region_mask == null:
		return
	original_background_material = background.material
	leaf_material = ShaderMaterial.new()
	leaf_material.shader = LEAF_WIND
	leaf_material.set_shader_parameter("leaf_region_mask", leaf_region_mask)
	leaf_material.set_shader_parameter("artwork_pixels", background.texture.get_size())
	leaf_material.set_shader_parameter("amplitude_pixels", leaf_amplitude_pixels)
	background.material = leaf_material

## 环境层单独卸载时也不会在背景留下仍运行的材质。
func _exit_tree() -> void:
	if is_instance_valid(background) and background.material == leaf_material:
		background.material = original_background_material

## [param active] 为总FX开关；[param clean_sky] 控制云层是否与去云背景配套。
func set_flags(active: bool, clean_sky: bool) -> void:
	enabled = active
	clouds_enabled = clean_sky
	_apply_running()

## 隐藏、关闭与场景卸载不会留下独立Timer、Tween或烟团队列。
func _apply_running() -> void:
	var running := enabled and is_visible_in_tree() # 继承场景可见性。
	set_process(running)
	for effect in effects: # 云开关只影响云，其他效果仍可独立使用。
		effect.set_running(running and (clouds_enabled or not effect.settings.get("cloud", false)))
	if not running and is_instance_valid(ship):
		elapsed = 0.0
		ship.position = ship_origin
		ship.rotation = ship_rotation
	if is_instance_valid(ship) and ship.material != null:
		ship.material.set_shader_parameter("animate", running)
	if leaf_material != null:
		leaf_material.set_shader_parameter("wind_enabled", running and provisional_leaf_wind_enabled)

## [param delta] 为秒；只动船体美术及烟囱随动点，交互牌、码头和海岸不动。
func _process(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	elapsed += delta
	ship.position = ship_origin + Vector2(0, 4.5 * sin(elapsed * TAU / 7.5))
	ship.rotation = ship_rotation + deg_to_rad(0.25) * sin(elapsed * TAU / 8.0)
