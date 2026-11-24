## 根视口中的雪镜头。天气控制器推进相位，独立的显隐判断立即保护战斗模态。
extends CanvasLayer

## 绘制在本关的普通战斗 HUD（５０）上方，技能切入、教学与切场遮幕下方。
const HUD_SNOW_LAYER: int = 51
## 两轴的参考像素周期，与着色器的噪声格和冰粒格严格对齐。
const TRAVEL_PERIOD: float = 4096.0
## 参考视口高，单位为像素。窗口等比缩放时保持相同的风带构图。
const REFERENCE_HEIGHT: float = 600.0
## 仅雪山镜头实例引用的全屏合成着色器。
const LENS_SHADER: Shader = preload("res://shaders/weather/snow_lens_overlay.gdshader")

## 当前关卡，提供流程及模态可见状态。
var _game: MainGameManager
## 实际承载战场和 HUD 的根视口，离场时断开尺寸通知。
var _viewport: Viewport
## 本战的屏幕合成矩形，始终忽略 GUI 输入。
var _plane: ColorRect
## 本战独立的可变材质。
var _material: ShaderMaterial
## 设置音量和更改战斗流程的原版暂停面板，可能打开而不暂停场景树。
var _pause_menu: Control
## 原版战斗提示对话框，未暂停时也需保持清晰。
var _dialog: Control
## 当前场景自身的加载与揭幕层。
var _transition: Node
## 同层红色大波提示。
var _approaching: Control
## 同层红色末波提示。
var _final_wave: Control
## 两轴世界风换算成镜头参考像素后的有界累计位移。
var _travel: Vector2 = Vector2.ZERO
## 镜头的局部冲击强度，０到１；合成透明度由着色器限制。
var _whiteout: float = 0.0
## 本帧底色的透明度，由当前雪量与资源上限计算。
var _frost_alpha: float = 0.0
## 普通 HUD 区域的最大合成透明度，不超过 0.18。
var _alpha_cap: float = 0.09
## 红字当前是否独占可读性。只在状态切换时写入材质。
var _warning_visible: bool = false


## 读取 [param game] 的战斗 UI 状态并装配屏幕矩形，[param profile] 提供本场色调和透明度上限。
func configure(game: MainGameManager, profile: SnowVisualProfile) -> void:
	_game = game
	_pause_menu = game.get_node_or_null(^"%BattlePauseMenu") as Control
	_dialog = game.get_node_or_null(^"%Dialog") as Control
	_transition = game.get_node_or_null(^"SceneTransition")
	_approaching = game.get_node_or_null(^"%UIRemindWord/Approaching") as Control
	_final_wave = game.get_node_or_null(^"%UIRemindWord/FinalWave") as Control
	layer = HUD_SNOW_LAYER
	follow_viewport_enabled = false
	# 暂停期间仅刷新绘制资格。唯一运动入口仍由可暂停的天气控制器调用。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_alpha_cap = clampf(profile.lens_frost_alpha, 0.0, 0.18)
	_material = ShaderMaterial.new()
	_material.shader = LENS_SHADER
	_material.set_shader_parameter(&"lens_tint", profile.lens_tint)
	_material.set_shader_parameter(&"hud_cap", _alpha_cap)
	_plane = ColorRect.new()
	_plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plane.focus_mode = Control.FOCUS_NONE
	_plane.material = _material
	_plane.hide()
	add_child(_plane)
	_viewport = get_viewport()
	_viewport.size_changed.connect(_sync_viewport)
	TreePauseManager.pause_factors_changed.connect(_sync_presentation)
	for control: Control in [_pause_menu, _dialog, _approaching, _final_wave]: # 本场已有 UI 生命周期。
		if is_instance_valid(control):
			control.visibility_changed.connect(_sync_presentation)
	_sync_viewport()


## 只以 [param delta] 游戏秒推进。[param wind] 为世界风速（像素/秒）。
## [param lens_whiteout] 和 [param hud_frost] 均为０到１的权重；[param high_quality] 调整细雪采样层数。
func advance(delta: float, wind: Vector2, lens_whiteout: float, hud_frost: float, high_quality: bool) -> void:
	if _material == null:
		return
	# 同一风向的近镜头视差与轻微下落。位移的两个端点在 GPU 噪声格内相接。
	var velocity: Vector2 = wind * 1.65 + Vector2(0.0, 19.0) # 参考像素/游戏秒。
	var direction: Vector2 = velocity.normalized() if velocity.length_squared() > 0.01 else Vector2.DOWN # 静止时冰粒仍有稳定短轴。
	_travel += velocity * delta
	_travel = Vector2(fposmod(_travel.x, TRAVEL_PERIOD), fposmod(_travel.y, TRAVEL_PERIOD))
	_whiteout = clampf(lens_whiteout, 0.0, 1.0)
	_frost_alpha = clampf(hud_frost, 0.0, 1.0) * _alpha_cap
	_material.set_shader_parameter(&"travel", _travel)
	_material.set_shader_parameter(&"wind_axis", direction)
	_material.set_shader_parameter(&"lens_whiteout", _whiteout)
	_material.set_shader_parameter(&"frost_alpha", _frost_alpha)
	_material.set_shader_parameter(&"fine_detail", high_quality)
	_sync_presentation()


## [param _delta] 不参与天气相位。只同步流程、切场和非天气原因引起的暂停或恢复。
func _process(_delta: float) -> void:
	_sync_presentation()


## 由根视口实际可见矩形映射 UV，窗口改变时只修改自己的尺寸与参照尺度。
func _sync_viewport() -> void:
	if not is_inside_tree() or not is_instance_valid(_plane) or not is_instance_valid(_viewport):
		return
	var view: Rect2 = _viewport.get_visible_rect() # 逻辑视口，含项目伸缩规则。
	_plane.position = view.position
	_plane.size = view.size
	_material.set_shader_parameter(&"reference_size", view.size * (REFERENCE_HEIGHT / maxf(1.0, view.size.y)))


## 保护结算、选卡、切场、暂停、未暂停的模态、教学和实战红字。
func _sync_presentation() -> void:
	if not is_instance_valid(_plane) or not is_inside_tree():
		return
	var in_battle: bool = is_instance_valid(_game) and get_tree().current_scene == _game \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME # 只有操作阶段允许画到 HUD。
	var modal_open: bool = get_tree().paused or _control_visible(_pause_menu) or _control_visible(_dialog) \
		or (is_instance_valid(_transition) and _transition.busy) # 暂停之外的可见面板也受保护。
	var warning: bool = _control_visible(_approaching) or _control_visible(_final_wave) # 实战内部红字只接受轻冷色。
	if warning != _warning_visible:
		_warning_visible = warning
		_material.set_shader_parameter(&"warning_visible", warning)
	var effect_visible: bool = _frost_alpha > 0.0005 or (_whiteout > 0.002 and not warning) # 干燥阶段避免整屏透明绘制。
	_plane.visible = in_battle and not modal_open and effect_visible


## 返回 [param control] 是否在本树实际显示，兼容不同关卡缺少个别 UI。
func _control_visible(control: Control) -> bool:
	return is_instance_valid(control) and control.is_visible_in_tree()


## 卸载时解除两个持久宿主的通知，场景内 UI 信号随本局释放。
func _exit_tree() -> void:
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_sync_viewport):
		_viewport.size_changed.disconnect(_sync_viewport)
	if TreePauseManager.pause_factors_changed.is_connected(_sync_presentation):
		TreePauseManager.pause_factors_changed.disconnect(_sync_presentation)
