## 一次独立的全屏白闪与失焦。附在战场下，显示期间忽略输入。
extends CanvasLayer

## 普通 HUD 和镜头雪之上，切场遮罩之下。
const OVERLAY_LAYER: int = 56
## 读取闪光当帧的完整画面，连续混合白闪和镜头失焦。
const FILTER_SHADER: Shader = preload("res://shaders/environment/battle_whiteout.gdshader")

## 特效的屏幕中心，按逻辑视口像素设置。
var _focus := Vector2.ZERO
## 从峰值到画面完全清晰的持续游戏秒数。
var _duration: float = 0.60
## 峰值冷白覆盖率，范围 0..1。
var _strength: float = 0.97
## 峰值前的渐强秒数，瞬时白闪使用零。
var _build: float = 0.0
## 失焦峰值，较低值能让漫反射中的云纹保留细节。
var _focus_loss: float = 1.0
## 从白闪起始累计的游戏秒。
var _age: float = 0.0
## 本次闪屏独立的合成材质。
var _material: ShaderMaterial
## 始终覆盖当前视口尺寸的合成平面。
var _plane: ColorRect

## 入树前设置 [param screen_point] 为视口坐标、[param duration] 为总游戏秒、[param strength] 为白色覆盖率。
## [param build_seconds] 为可选渐强时间，适用于风雪漫反射逐渐增厚的镜头。
## [param focus_loss] 为失焦的独立峰值，范围 0..1。
func configure(screen_point: Vector2, duration: float, strength: float,
		build_seconds: float = 0.0, focus_loss: float = 1.0) -> void:
	_focus = screen_point
	_duration = maxf(0.1, duration)
	_strength = clampf(strength, 0.0, 1.0)
	_build = clampf(build_seconds, 0.0, _duration * 0.9)
	_focus_loss = clampf(focus_loss, 0.0, 1.0)

## 先复制这帧的战场与 HUD，再合成；可与其他需要采样屏幕的材质并存。
func _ready() -> void:
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	visible = not get_tree().paused
	var capture := BackBufferCopy.new() # 专用屏幕样本包含已合成的实景雪与 HUD。
	capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(capture)
	_material = ShaderMaterial.new()
	_material.shader = FILTER_SHADER
	_plane = ColorRect.new()
	_plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plane.material = _material
	add_child(_plane)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	_apply_envelope(0.0)

## [param delta] 为游戏秒；白闪先消退，失焦拖尾结束后卸掉全屏采样。
func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		visible = false
		queue_free()
		return
	_apply_envelope(_age / _duration)

## 暂停时让出画面，恢复时从原演出进度继续。[param what] 为引擎通知。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		visible = false
	elif what == NOTIFICATION_UNPAUSED:
		visible = true

## 对齐同一视口的尺寸及焦点，窗口缩放期间也覆盖完整画面。
func _fit_viewport() -> void:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect() # 采样和合成使用同一套逻辑坐标。
	_plane.position = viewport_rect.position
	_plane.size = viewport_rect.size
	_material.set_shader_parameter(&"focus_uv", (_focus - viewport_rect.position) / viewport_rect.size)

## [param phase] 为本次演出的归一化进度。若已指定渐强，峰后沿同样的节奏恢复清晰。
func _apply_envelope(phase: float) -> void:
	var lead: float = _build / _duration # 渐强占本次镜头的比例。
	var swell: float = smoothstep(0.0, lead, phase) if lead > 0.0 else 1.0 # 瞬时白闪入树即到峰值。
	var tail: float = maxf(0.0, (phase - lead) / (1.0 - lead)) # 渐强结束后沿原白闪包络衰减。
	_material.set_shader_parameter(&"flash", _strength * swell * (1.0 - smoothstep(0.06, 0.32, tail)))
	_material.set_shader_parameter(&"defocus", _focus_loss * swell * (1.0 - smoothstep(0.12, 1.0, tail)))
