## 设置页手动启动的原版五星 Shader 自测，退出后不留下任何 ShaderMaterial。
## 仅自测路径使用旧 Shader，正常游戏的全部星章只使用预烘焙帧。
extends TextureRect

## 8 秒恰好覆盖旧版扫光的一个完整循环。
const DURATION_SECONDS: float = 8.0
## 原本用于玩家五星徽章的 Shader，此资源绝不自动预加载。
const LEGACY_SHADER_PATH: String = "res://shaders/adventure/star_badge_fx.gdshader"
## 自测只加载旧版五星彩章及其两份原始蒙版。
const ROOT: String = "res://assets/adventure/ui/star_badges/"
## 只需覆盖约 31px 原版大小，不新建战场或全屏合成。
const PREVIEW_SIZE: Vector2 = Vector2(31, 31)

## 自测正常完成后通知设置中的紧凑提示行。
signal finished(success: bool)

## 独立的一次性定时器，不依赖战斗时间倍率。
var _timer: Timer
## true 表示已写入 running 且尚未正常完成的诊断。
var _running: bool = false
## 临时自定义材质仅属于这个节点，退出后立即归还 GPU 资源。
var _shader_material: ShaderMaterial

## 小图不截获复选框操作；默认不绘制任何内容。
func _init() -> void:
	name = "LegacyStarShaderProbe"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	size = PREVIEW_SIZE
	visible = false

## 先持久化 running，再创建旧 ShaderMaterial；驱动闪退可于下次打开识别。
func begin() -> Error:
	var config: ConfigService = Global.config_service
	if config == null:
		return ERR_UNCONFIGURED
	var saved: Error = config.set_render_probe_state("running")
	if saved != OK:
		return saved
	_running = true
	var body: Texture2D = load(ROOT + "static/256/star_05.png") as Texture2D
	var sweep: Texture2D = load(ROOT + "masks/star_05_sweep_mask.png") as Texture2D
	var guard: Texture2D = load(ROOT + "masks/star_05_number_guard.png") as Texture2D
	var old_shader: Shader = load(LEGACY_SHADER_PATH) as Shader
	if body == null or sweep == null or guard == null or old_shader == null:
		_cancel()
		return ERR_FILE_NOT_FOUND
	texture = body
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = old_shader
	_shader_material.set_shader_parameter("effect_mode", 0)
	_shader_material.set_shader_parameter("rank", 5.0)
	_shader_material.set_shader_parameter("sweep_mask", sweep)
	_shader_material.set_shader_parameter("number_guard", guard)
	material = _shader_material # 与原版一样，不填充可选的 rainbow_mask。
	show()
	_timer = Timer.new()
	_timer.name = "EightSecondProbe"
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.ignore_time_scale = true
	_timer.one_shot = true
	_timer.wait_time = DURATION_SECONDS
	add_child(_timer)
	_timer.timeout.connect(_on_timeout)
	_timer.start()
	return OK

## 仅供设置行显示进度；不会读取或修改玩家资产。
func elapsed_seconds() -> float:
	return DURATION_SECONDS - _timer.time_left if _timer != null else 0.0

## 计时正常结束后先释放旧材质，再将状态保存为通过。
func _on_timeout() -> void:
	if not _running:
		return
	_running = false
	material = null
	_shader_material = null
	texture = null
	hide()
	var status: Error = Global.config_service.set_render_probe_state("passed")
	finished.emit(status == OK)

## 手动关窗或切后台时记为取消，不能误判成 GPU 驱动闪退。
func _cancel() -> void:
	if not _running:
		return
	_running = false
	if is_instance_valid(_timer):
		_timer.stop()
	material = null
	_shader_material = null
	texture = null
	if is_instance_valid(Global.config_service):
		Global.config_service.set_render_probe_state("canceled")

## 自测窗口被正常释放时清理，避免旧材质残留在下次设置会话。
func _exit_tree() -> void:
	_cancel()

## Android 切到后台时停止自测，不把系统正常中断标记成崩溃。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and _running:
		_cancel()
		finished.emit(false) # 暂停不应让设置页的自测按钮永久锁定。
