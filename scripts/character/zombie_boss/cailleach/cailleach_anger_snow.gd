## 愠怒的两层近雪；按实际雪场风速推进固定容量的解析粒子。
extends CanvasLayer

## 密雪在掉落物与操作栏之间，紧邻而不替换原有世界近雪。
const NEAR_LAYER: int = 7
## 大雪掠过更靠前一层，卡槽和技能界面仍在其上。
const LENS_LAYER: int = 8
## 所有粒宽及视口内风速以 600 像素高的画幅为参照。
const REFERENCE_HEIGHT: float = 600.0
## 复用寒冰菇的三帧雪花，只在演出入树时载入。
const FLAKE_PATH: String = "res://assets/image/particles/bullet/SnowFlakes.png"
## 两层共用形状和漂移逻辑，分别设定密度、视差和失焦。
const FLAKE_SHADER = preload("res://shaders/adventure/wonderland/cailleach_anger_snow.gdshader")

## 与本场地吹雪共用风向、阵风和变化速度。
var _snow: SnowEnvironmentController
## 较细、较密且保留冰晶轮廓的一组雪片。
var _near: MultiMeshInstance2D
## 镜头前的失焦大雪画布，与密雪一起结束。
var _lens: CanvasLayer
## 距镜头最近的大雪批次。
var _close: MultiMeshInstance2D
## 由当前愠怒时序给出的强度，范围为 0..1。
var _strength: float = 0.0
## 本次演出的游戏秒，用于雪粒翻卷。
var _age: float = 0.0
## 在同一风场中累进的二维运动，单位为参照像素。
var _near_travel := Vector2.ZERO
## 镜头前的大雪视差与密雪不同，独立累积避免突跳。
var _lens_travel := Vector2.ZERO
## 当前视口把参考画幅换算到逻辑像素的倍率。
var _pixel_scale: float = 1.0

## [param snow] 为当前战场的天气。无实例时使用向左的备用风，仍可演出。
func _init(snow: SnowEnvironmentController) -> void:
	_snow = snow
	name = "CailleachAngerSnow"

## 入树时各分配一次；低画质与移动端减少两层实例数量，保留层次。
func _ready() -> void:
	layer = NEAR_LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var low_detail: bool = OS.has_feature("mobile") # 无本场质量设置时仍按平台选择预算。
	if is_instance_valid(_snow):
		low_detail = _snow.quality_mode == 1 or (_snow.quality_mode == 0 and low_detail)
	var flakes := load(FLAKE_PATH) as Texture2D # 两层只引用原有雪花图集。
	_near = _create_batch(112 if low_detail else 188, false, flakes)
	_near.name = "NearSnow"
	add_child(_near)
	_lens = CanvasLayer.new()
	_lens.layer = LENS_LAYER
	add_child(_lens)
	_close = _create_batch(22 if low_detail else 35, true, flakes)
	_close.name = "LensSnow"
	_lens.add_child(_close)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	present(_strength)

## 应用本次动作的 [param strength]。零强度隐藏两个批次，不占正常暴雪预算。
func present(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	if _near == null:
		return
	var snow_visible: bool = _strength > 0.002 and not get_tree().paused # 暂停模态上不残留额外粒子。
	visible = snow_visible
	_lens.visible = snow_visible
	if snow_visible:
		(_near.material as ShaderMaterial).set_shader_parameter(&"strength", _strength)
		(_close.material as ShaderMaterial).set_shader_parameter(&"strength", _strength)

## 以 [param delta] 游戏秒按当前世界风推进；粒子大小及拉丝随屏幕风速更新。
func _process(delta: float) -> void:
	var wind: Vector2 = _snow.get_visual_wind() if is_instance_valid(_snow) else Vector2(-530.0, 45.0) # 无雪场使用固定向左的小幅风。
	var screen_wind: Vector2 = get_viewport().get_canvas_transform().basis_xform(wind) / _pixel_scale # 真实风到参考像素的投影。
	var near_velocity: Vector2 = screen_wind * 1.13 + Vector2(0.0, 110.0) # 密雪保留可见的自然落速。
	var lens_velocity: Vector2 = screen_wind * 1.75 + Vector2(0.0, 83.0) # 镜头近处横掠更快、下坠更少。
	_age += delta
	_near_travel += near_velocity * delta
	_lens_travel += lens_velocity * delta
	_set_motion(_near, _near_travel, near_velocity)
	_set_motion(_close, _lens_travel, lens_velocity)

## 刷新场景树的暂停可见性。[param what] 为引擎发出的节点通知。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		present(_strength)

## 生成 [param count] 个共享四边形，固定 [param lens_blur] 所在的摄影深度。
## [param flakes] 是外层雪晶的三帧贴图，返回可直接加入画布的单批次。
func _create_batch(count: int, lens_blur: bool, flakes: Texture2D) -> MultiMeshInstance2D:
	var quad := QuadMesh.new() # 齐次单位四边形，实际位置和大小由顶点着色器计算。
	quad.size = Vector2.ONE
	var mesh := MultiMesh.new() # 一层只提交一次绘制。
	mesh.transform_format = MultiMesh.TRANSFORM_2D
	mesh.use_custom_data = true
	mesh.mesh = quad
	mesh.instance_count = count
	var random := RandomNumberGenerator.new() # 本地固定种子保证各帧连贯，也不消耗选技能的随机序列。
	random.seed = 918773 if lens_blur else 287153
	for index: int in range(count): # 两个种子确定初始位置，另两个用于独立的尺寸和密度变化。
		mesh.set_instance_transform_2d(index, Transform2D.IDENTITY)
		mesh.set_instance_custom_data(index, Color(random.randf(), random.randf(), random.randf(), random.randf()))
	var material := ShaderMaterial.new() # 两层使用同一程序，分别上传位移和选用片元形状。
	material.shader = FLAKE_SHADER
	material.set_shader_parameter(&"flakes", flakes)
	material.set_shader_parameter(&"lens_blur", lens_blur)
	var batch := MultiMeshInstance2D.new() # 成员随动作节点卸载，不影响现有天气粒子。
	batch.multimesh = mesh
	batch.material = material
	return batch

## 随逻辑视口调整绘制及粒子循环边界，镜头缩放时不会在画面内重生。
func _fit_viewport() -> void:
	var view: Rect2 = get_viewport().get_visible_rect() # 包含本场画面伸缩后的可见范围。
	_pixel_scale = maxf(1.0, view.size.y) / REFERENCE_HEIGHT
	var bounds: Rect2 = view.grow(250.0 * _pixel_scale) # 明确 GPU 位移范围，防止批次按单位四边形错裁。
	for batch: MultiMeshInstance2D in [_near, _close]: # 两层保持相同视口比例。
		batch.multimesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -1.0),
			Vector3(bounds.size.x, bounds.size.y, 2.0))
		var material := batch.material as ShaderMaterial # 窗口改变才上传几何和比例。
		material.set_shader_parameter(&"view_origin", view.position)
		material.set_shader_parameter(&"reference_size", view.size / _pixel_scale)
		material.set_shader_parameter(&"pixel_scale", _pixel_scale)

## 为 [param batch] 设置实际累计 [param travel] 和 [param velocity]，二者均以参照像素为单位。
func _set_motion(batch: MultiMeshInstance2D, travel: Vector2, velocity: Vector2) -> void:
	var material := batch.material as ShaderMaterial # 每层独立记录方向及快门拉丝长度。
	material.set_shader_parameter(&"travel", travel)
	material.set_shader_parameter(&"velocity", velocity)
	material.set_shader_parameter(&"age", _age)
