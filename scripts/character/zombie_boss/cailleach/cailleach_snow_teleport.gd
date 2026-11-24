## 妇人的白雾传送，将原画消隐、局部失焦和雾中泛光绑在同一条时间线上。
extends CanvasLayer

## 原画与白雾都已到达终点，可以交回待机或死亡结算。
signal finished

## 世界雪以上，战斗卡槽、结算和暂停界面以下。
const OVERLAY_LAYER: int = 8
## 入场先聚雾再显形，单位为战斗秒。
const ARRIVAL_SECONDS: float = 1.38
## 退场先消去人物，再让白雾随风退散，单位为战斗秒。
const DEPARTURE_SECONDS: float = 1.56
## 非雪山场地仍有这次传送自身的侧向气流，单位为世界像素每秒。
const FALLBACK_WIND := Vector2(-230.0, 24.0)
## 专用于这次传送的原画显隐和镜头雾材质。
const POSE_SHADER: Shader = preload("res://shaders/adventure/wonderland/cailleach_teleport_pose.gdshader")
## 读取世界画面，以同一片雾实现散焦和泛光。
const VEIL_SHADER: Shader = preload("res://shaders/adventure/wonderland/cailleach_teleport_veil.gdshader")

## 所属雪场，只读实际视觉风速。
var _snow: SnowEnvironmentController
## 一阶段当前实际显示的原画。
var _sprite: AnimatedSprite2D
## 平时使用的原画材质，传送结束或转阶段时交还。
var _sprite_material: Material
## 原画原有透明度，也供被冻住的杖击合成层继承。
var _sprite_alpha: float = 1.0
## 当前原画在其本地坐标的完整帧范围。
var _sprite_bounds := Rect2()
## 世界脚点的原有投影。
var _shadow: Sprite2D
## 传送前的投影透明度，入场完成后准确恢复。
var _shadow_alpha: float = 1.0
## 本次传送使用的原画消隐材质。
var _pose_material: ShaderMaterial
## 本次传送使用的白雾屏幕材质。
var _veil_material: ShaderMaterial
## 随视口大小变化的白雾合成矩形。
var _plane: ColorRect
## 当前视口逻辑像素，用于对齐纹理采样和镜头投影。
var _viewport_bounds := Rect2()
## 当前播放方向，true 为入场。
var _arriving: bool = true
## 正常离场用默认秒数，转阶段另有更长的气氛停留。
var _departure_seconds: float = DEPARTURE_SECONDS
## 当前一段传送已经推进的战斗秒数。
var _age: float = 0.0
## 沿风轴积累的镜头像素位移，退场接续入场时保留连续相位。
var _wind_travel: float = 0.0
## x 原画显形比例，y 白雾密度，z 泛光强度，w 向下游拉出的雾尾。
var _mix := Vector4.ZERO
## 退场开始时的画面状态，中途击败时从正在显形的状态继续。
var _departure_from := Vector4(1.0, 0.0, 0.0, 0.0)

## 入树前绑定 [param sprite] 原画、[param shadow] 世界投影和可选的 [param snow]。
## [param arriving] 为 true 时从无影的雪中显形，为 false 时从当前原画消失。
## [param departure_seconds] 调整退场节奏。
func configure(sprite: AnimatedSprite2D, shadow: Sprite2D, snow: SnowEnvironmentController, arriving: bool,
		departure_seconds: float = DEPARTURE_SECONDS) -> void:
	_snow = snow
	_sprite = sprite
	_sprite_material = sprite.material
	_sprite_alpha = sprite.modulate.a
	_shadow = shadow
	_shadow_alpha = _shadow.self_modulate.a
	_arriving = arriving
	_departure_seconds = departure_seconds
	var frame_size: Vector2 = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame).get_size() # 原画单帧像素。
	_sprite_bounds = Rect2(sprite.offset, frame_size) # 一阶段原画以独立的脚点偏移定位。

## 复制刚绘制的世界和近雪。上层界面继续按正常顺序绘制。
func _ready() -> void:
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_pose_material = ShaderMaterial.new()
	_pose_material.shader = POSE_SHADER
	_sprite.material = _pose_material
	var capture := BackBufferCopy.new() # 让白雾采样本帧已合成的战场。
	capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(capture)
	_veil_material = ShaderMaterial.new()
	_veil_material.shader = VEIL_SHADER
	_plane = ColorRect.new()
	_plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plane.material = _veil_material
	add_child(_plane)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	_present(0.0, 0.0)

## 若入场未结束，从当前画面接着消隐，[param departure_seconds] 为退场总秒数。
func begin_departure(departure_seconds: float = DEPARTURE_SECONDS) -> void:
	_arriving = false
	_departure_seconds = departure_seconds
	_departure_from = _mix
	_age = 0.0
	_present(0.0, 0.0)

## 立即交还原画和影子，转阶段时同步卸下白雾。
func stop() -> void:
	_sprite.material = _sprite_material
	_sprite.modulate.a = _sprite_alpha
	_shadow.self_modulate.a = _shadow_alpha
	hide()
	set_process(false)
	get_viewport().size_changed.disconnect(_fit_viewport)
	queue_free()

## [param delta] 为战斗秒。原画与雾尾全结束后释放材质并通知本体。
func _process(delta: float) -> void:
	var duration: float = ARRIVAL_SECONDS if _arriving else _departure_seconds # 当前方向允许不同的构图时序。
	_age = minf(_age + delta, duration)
	_present(_age / duration, delta)
	if _age >= duration:
		if not _arriving:
			_sprite.hide()
			_shadow.hide()
		stop()
		finished.emit()

## [param progress] 为当前入场或退场段进度，[param delta] 用于推进雾纹平流。
func _present(progress: float, delta: float) -> void:
	if _arriving:
		_mix.x = smoothstep(0.22, 0.72, progress)
		_mix.y = smoothstep(0.02, 0.30, progress) * (1.0 - smoothstep(0.48, 1.0, progress))
		_mix.z = smoothstep(0.16, 0.38, progress) * (1.0 - smoothstep(0.54, 0.87, progress))
		_mix.w = lerpf(-0.32, 0.26, smoothstep(0.04, 1.0, progress))
	else:
		_mix.x = _departure_from.x * (1.0 - smoothstep(0.19, 0.62, progress))
		var mist_build: float = lerpf(_departure_from.y, 1.0, smoothstep(0.0, 0.36, progress)) # 白雾从当前密度升到峰值。
		var light_build: float = lerpf(_departure_from.z, 0.94, smoothstep(0.03, 0.35, progress)) # 接续当前泛光。
		_mix.y = mist_build * (1.0 - smoothstep(0.54, 1.0, progress))
		_mix.z = light_build * (1.0 - smoothstep(0.47, 0.87, progress))
		_mix.w = lerpf(_departure_from.w, 0.88, smoothstep(0.19, 1.0, progress))
	_update_picture(delta)

## [param delta] 为战斗秒。两种材质共用原画中心、缩放及当前天气的平流。
func _update_picture(delta: float) -> void:
	var placement: Transform2D = _sprite.get_global_transform_with_canvas() # 从同一世界脚点投影到本视口。
	var center: Vector2 = placement * _sprite_bounds.get_center() - _viewport_bounds.position # 当前屏幕侧的雾心。
	var width: float = placement.basis_xform(Vector2(_sprite_bounds.size.x, 0.0)).length() # 原画当前显示宽度。
	var height: float = placement.basis_xform(Vector2(0.0, _sprite_bounds.size.y)).length() # 原画当前显示高度。
	var radii := Vector2(maxf(width * 0.65, height * 0.92), height * 0.77).max(Vector2.ONE) # 沿风轴与垂直轴分别扩散。
	var world_wind: Vector2 = _snow.get_visual_wind() if is_instance_valid(_snow) else FALLBACK_WIND # 雪场和雾体使用同一个风向。
	var screen_wind: Vector2 = get_viewport().get_canvas_transform().basis_xform(world_wind) # 换算成当前镜头像素每秒。
	var direction: Vector2 = FALLBACK_WIND.normalized() if screen_wind.is_zero_approx() else screen_wind.normalized() # 未配置时保留软边方向。
	_wind_travel += screen_wind.length() * delta
	for material: ShaderMaterial in [_pose_material, _veil_material]: # 消隐和雾带在同一片空气中运动。
		material.set_shader_parameter(&"focus_px", center)
		material.set_shader_parameter(&"fog_radius", radii)
		material.set_shader_parameter(&"wind_axis", direction)
		material.set_shader_parameter(&"wind_travel", _wind_travel)
		material.set_shader_parameter(&"glow", _mix.z)
	_pose_material.set_shader_parameter(&"presence", _mix.x)
	_sprite.modulate.a = _sprite_alpha * sqrt(_mix.x)
	_shadow.self_modulate.a = _shadow_alpha * _mix.x
	_veil_material.set_shader_parameter(&"mist", _mix.y)
	_veil_material.set_shader_parameter(&"wake", _mix.w)

## 按逻辑视口覆盖战场；屏幕纹理坐标和两张材质采用同一尺寸。
func _fit_viewport() -> void:
	_viewport_bounds = get_viewport().get_visible_rect()
	_plane.position = _viewport_bounds.position
	_plane.size = _viewport_bounds.size
	_pose_material.set_shader_parameter(&"viewport_size", _viewport_bounds.size.max(Vector2.ONE))
	_veil_material.set_shader_parameter(&"viewport_size", _viewport_bounds.size.max(Vector2.ONE))
	_update_picture(0.0)
