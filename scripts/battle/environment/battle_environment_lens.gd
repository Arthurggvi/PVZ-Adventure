## 场景私有的整屏水下透镜；同时提供与显示采样严格一致的鼠标映射。
extends CanvasLayer
class_name BattleEnvironmentLens

## 最终屏幕材质，不包含音乐或任何逻辑坐标修改。
const SHADER = preload("res://shaders/environment/submerged_lens.gdshader")
## 物理触点先交给场景私有路由，避免折射层提前丢弃多指手势。
const PointerRouter = preload("res://scripts/battle/input/battle_pointer_router.gd")
## 当前视口的弱引用入口，战斗结束立即移除，不作为全局服务或资源缓存。
const POINTER_KEY := &"battle_environment_lens"
## 重映射事件上的原始视口坐标，供拖动阈值忽略画面折射的位移。
const PHYSICAL_POINTER_POSITION := &"battle_physical_pointer_position"
## 四组不等周期使画面各区域以不同速度弯曲，单位真实秒。
const PERIODS := Vector4(7.6, 11.3, 19.7, 31.0)
## 本场资源，只用于位移基准。
var profile: BattleEnvironmentProfile
## 当前 CPU/GPU 共用相位。
var phase := Vector4.ZERO
## 当前两轴 UV 位移幅度，包含强度与事件。
var amplitude := Vector2.ZERO
## 最终屏幕材质实例。
var _material: ShaderMaterial
## 无介质时显式停止整屏读回。
var _copy: BackBufferCopy
## 真实鼠标事件转发期间防止递归。
var _forwarding: bool = false
## 转发期间的原画坐标，保证点击回调中手持、铲子、加农炮与 UI 一致。
var _event_position := Vector2.ZERO
## 静止指针经过流动界面时也更新悬停；从不移动系统指针。
var _last_logical_pointer := Vector2.INF
## 是否已解除本场表现和输入，允许重复释放。
var _disposed: bool = false

## 追加在窗口根的最后，使输入在游戏脚本之前映射；生命周期仍归场景渲染器所有。
func _ready() -> void:
	name = "SubmergedLens"
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	get_viewport().set_meta(POINTER_KEY, weakref(self))
	_copy = BackBufferCopy.new() # 前面所有战场、头像和 UI 都已绘制。
	_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_copy)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var rect := ColorRect.new() # 鼠标由统一事件映射处理，不用透明控件拦截 GUI。
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _material
	add_child(rect)
	hide()

## [param seconds] 为共享时钟；[param strength] 为环境渐变；[param energy] 为声画事件包络。
func apply_state(seconds: float, strength: float, energy: float) -> void:
	phase = Vector4(fposmod(seconds, PERIODS.x) / PERIODS.x, fposmod(seconds, PERIODS.y) / PERIODS.y,
		fposmod(seconds, PERIODS.z) / PERIODS.z, fposmod(seconds, PERIODS.w) / PERIODS.w) * TAU
	var size: Vector2 = get_viewport().get_visible_rect().size # 位移随实际视口纵横比换算，缩放窗口仍精确点击。
	amplitude = Vector2(1.0, size.x / size.y) * profile.screen_refraction_pixels / 1920.0 * strength * (0.78 + energy * 0.62)
	visible = strength > 0.0001 and not _disposed
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if visible else BackBufferCopy.COPY_MODE_DISABLED
	_material.set_shader_parameter("lens_phase", phase)
	_material.set_shader_parameter("lens_amplitude", amplitude)
	_material.set_shader_parameter("immersion", strength)
	_material.set_shader_parameter("current_energy", energy)

## 将显示位置 [param point] 映射到原始视口坐标；公式逐项对应 source_uv，不移动实体或按钮。
func screen_to_source(point: Vector2) -> Vector2:
	var size: Vector2 = get_viewport().get_visible_rect().size # 原版视口单位。
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return point
	var uv := point / size # 鼠标在变形后的完整画面中。
	var q := uv + Vector2(sin(uv.y * 5.0 + phase.z) * 0.045, cos(uv.x * 4.0 - phase.w) * 0.04) # 宽幅非均匀折叠。
	var x: float = sin(q.y * 12.0 + phase.x + sin(q.x * 5.0 + phase.z) * 0.55) * 0.58 + sin(q.y * 26.0 - phase.y + q.x * 3.0) * 0.26 + sin(q.x * 8.0 + q.y * 5.0 + phase.w) * 0.16 # 水平方向折射。
	var y: float = sin(q.x * 10.0 - phase.y + cos(q.y * 4.0 + phase.w) * 0.45) * 0.58 + cos(q.x * 21.0 + phase.z - q.y * 4.0) * 0.24 + cos(q.y * 7.0 + phase.x) * 0.18 # 垂直方向折射。
	var edge := Vector2(smoothstep(0.0, 0.055, uv.x) * smoothstep(0.0, 0.055, 1.0 - uv.x), smoothstep(0.0, 0.055, uv.y) * smoothstep(0.0, 0.055, 1.0 - uv.y)) # 外沿保持封闭，无空白边。
	return (uv + Vector2(x, y) * amplitude * edge).clamp(Vector2.ZERO, Vector2.ONE) * size

## 在 [param event] 交给原版 GUI 与游戏输入前映射一次；触屏沿用同一鼠标输入流。
func _input(event: InputEvent) -> void:
	if _forwarding or not visible or _disposed:
		return
	if PointerRouter.filter_before_mapping(get_viewport(), event):
		get_viewport().set_input_as_handled()
		return
	if Input.emulate_mouse_from_touch and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		# Godot 先发模拟鼠标事件；原始触摸若继续传递，会在未折射坐标再次触发 GUI。
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouse:
		return
	var mapped := event.duplicate() as InputEventMouse # 只改副本，原生系统指针始终停在玩家真实位置。
	mapped.set_meta(PHYSICAL_POINTER_POSITION, event.position)
	mapped.position = screen_to_source(event.position)
	mapped.global_position = mapped.position
	if mapped is InputEventMouseMotion:
		mapped.relative = mapped.position - screen_to_source(event.position - event.relative)
	_forward_event(mapped)
	get_viewport().set_input_as_handled()

## 发送已经换算好的 [param event]，点击回调可读取同一原画坐标；不再次施加折射。
func _forward_event(event: InputEventMouse) -> void:
	_forwarding = true
	_event_position = event.position
	_last_logical_pointer = event.position
	get_viewport().push_input(event, true)
	_forwarding = false

## [param _delta] 不推进动画；原环境时钟暂停时悬停和菜单输入仍然可用。
func _process(_delta: float) -> void:
	if not visible or _disposed or not get_window().has_focus():
		return
	var physical: Vector2 = get_viewport().get_mouse_position() # 系统指针真实位置，不隐藏或强制移动鼠标。
	if not get_viewport().get_visible_rect().has_point(physical):
		return
	var logical := screen_to_source(physical) # 悬停随流动后的显示位置更新。
	if logical.distance_squared_to(_last_logical_pointer) < 0.04:
		return
	var motion := InputEventMouseMotion.new() # 仅更新悬停，不合成点击。
	motion.position = logical
	motion.global_position = logical
	motion.button_mask = Input.get_mouse_button_mask()
	_forward_event(motion)

## 返回 [param item] 所在画布的指针位置；[param global] 为 true 时返回该画布的全局坐标。
## 无环境时严格沿用原版鼠标位置，供按帧轮询的手持预览和命中共用。
static func mouse_position(item: CanvasItem, global: bool = true) -> Vector2:
	var viewport: Viewport = item.get_viewport() # 不查询关卡编号或阶段身份。
	var point: Vector2 = viewport.get_mouse_position() # 未启用透镜的默认坐标。
	var reference: WeakRef = viewport.get_meta(POINTER_KEY) as WeakRef if viewport.has_meta(POINTER_KEY) else null # 场景退出不保留强引用；空默认值在 Godot 仍会报缺键，先检查存在。
	var lens: BattleEnvironmentLens = reference.get_ref() as BattleEnvironmentLens if reference != null else null # 仅使用当前视口仍存活的实例。
	if is_instance_valid(lens) and lens.visible and not lens._disposed:
		point = lens._event_position if lens._forwarding else lens.screen_to_source(point)
	point = item.get_global_transform_with_canvas().affine_inverse() * point
	return item.get_global_transform() * point if global else point

## 先同步撤销画面与输入，再等待节点释放；重开时不覆盖新场景的弱引用。
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if is_instance_valid(_copy):
		_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	hide()
	set_process(false)
	set_process_input(false)
	var reference: WeakRef = get_viewport().get_meta(POINTER_KEY) as WeakRef if get_viewport().has_meta(POINTER_KEY) else null # 只清除自己拥有的视口入口。
	if reference != null and reference.get_ref() == self:
		get_viewport().remove_meta(POINTER_KEY)

## 窗口关闭也走同一回收路径。
func _exit_tree() -> void:
	dispose()
