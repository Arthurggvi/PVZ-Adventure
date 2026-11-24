## 全关卡共用的技能演出，只消费已提交的技能资源，不参与施放和计时。
extends Control

## 覆盖战斗特效，保留全局切场遮幕的上层优先级。
const CANVAS_LAYER: int = 91
## 斜幕与速度线共用材质，每场战斗只在首次施放时创建实例。
const BACKDROP_SHADER := preload("res://shaders/adventure/character_skill_cut_in.gdshader")
## 默认战场画布尺寸；宽高变化时立绘与标题一起等比缩放。
const DESIGN_SIZE := Vector2(1066.0, 600.0)
## 演出总长度，单位为实际秒。
const DURATION: float = 1.23
## 主幕保持完全展开直到该时间，随后启动技能的退场方式。
const EXIT_START: float = 0.89
## 原人物立绘的构图范围，在斜幕上下保留完整轮廓。
const PORTRAIT_RECT := Rect2(569.0, 32.0, 411.0, 530.0)
## 技能标题的构图范围，位于速度线较稀疏的幕心。
const TITLE_RECT := Rect2(107.0, 230.0, 401.0, 142.0)

## 当前演出的唯一时间轴，隐藏时没有逐帧更新。
var _timeline: Tween
## 每帧只更新切入边界、压暗和横向线条位移。
var _material: ShaderMaterial
## 人物全身立绘。
var _portrait: TextureRect
## 原创技能标题字图。
var _title: TextureRect
## 旧资源缺少字图时，显示可读的实际技能名称。
var _name_fallback: Label
## 当前技能是否沿刀口裂开幕布。
var _blade_exit: bool = false
## 本局共用的起手音，暂停、结算或切换演出时停止。
var _cue: AudioStreamPlayer

## 建立全屏幕布与前景内容，所有层均放行输入。
func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = BACKDROP_SHADER
	var backdrop := ColorRect.new() # 单层着色器同时绘制压暗、幕布和速度线。
	backdrop.material = _material
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_portrait = _add_image()
	_title = _add_image()
	_name_fallback = Label.new()
	_name_fallback.mouse_filter = MOUSE_FILTER_IGNORE
	_name_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_fallback.clip_text = true
	_name_fallback.add_theme_color_override("font_color", Color("eafaff"))
	_name_fallback.add_theme_color_override("font_outline_color", Color("102347"))
	_name_fallback.add_theme_constant_override("outline_size", 9)
	add_child(_name_fallback)
	_cue = AudioStreamPlayer.new()
	_cue.bus = SoundManager.spatial_sfx_bus(SoundManager.SFXSpace.UI)
	_cue.volume_db = -4.0
	add_child(_cue)
	TreePauseManager.pause_factors_changed.connect(_on_pause_changed)
	hide()

## 创建保持纹理原比例的前景图层，尺寸完全由演出布局决定。
func _add_image() -> TextureRect:
	var picture := TextureRect.new() # 立绘和字图共用无输入的透明图层。
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(picture)
	return picture

## 播放 [param skill] 的立绘、技能名和切入转场；重复施放直接替换当前镜头。
func play(skill: CharacterSkillDefinition) -> void:
	stop()
	_portrait.texture = skill.cut_in_portrait if skill.cut_in_portrait != null else skill.icon
	_title.texture = skill.cut_in_title
	_title.visible = _title.texture != null
	_title.accessibility_name = skill.display_name
	_name_fallback.visible = not _title.visible
	_name_fallback.text = skill.display_name
	_blade_exit = skill.cut_in_blade_exit
	_material.set_shader_parameter(&"accent", skill.cut_in_accent)
	_render_frame(0.0)
	show()
	if skill.cut_in_sound != null:
		_cue.stream = skill.cut_in_sound
		_cue.play()
	_timeline = create_tween().set_ignore_time_scale(true)
	_timeline.tween_method(_render_frame, 0.0, DURATION, DURATION)
	_timeline.finished.connect(_finish)

## 取消残留画面；暂停、结算和下一次施放共用同一入口。
func stop() -> void:
	if _timeline != null:
		_timeline.kill()
	_cue.stop()
	_finish()

## 自然退场或打断时隐藏绘制，让下次施放从完整入场开始。
func _finish() -> void:
	_timeline = null
	hide()

## 暂停立即让出战场画面，恢复战斗时不继续上一次切入。
func _on_pause_changed() -> void:
	if (visible or _cue.playing) and get_tree().paused:
		stop()

## [param elapsed] 为实际秒数；立绘、标题与运动线独立错峰进场，退场统一还原战场。
func _render_frame(elapsed: float) -> void:
	var open: float = smoothstep(0.0, 0.31, elapsed) # 先揭幕再让立绘停稳。
	var close: float = smoothstep(EXIT_START, DURATION, elapsed) # 收幕平滑加速并在最后一帧完全透明。
	var portrait_entry: float = ease(clampf((elapsed - 0.025) / 0.37, 0.0, 1.0), 0.24) # 立绘先冲入再强减速。
	var title_entry: float = ease(clampf((elapsed - 0.085) / 0.30, 0.0, 1.0), 0.26) # 标题稍晚从反方向进入。
	var drift: float = smoothstep(0.29, EXIT_START, elapsed) # 停留期间保留很轻的滑动。
	var line_travel: float = 1.15 * (1.0 - exp(-elapsed * 8.0)) + elapsed * 0.52 \
		+ pow(maxf(0.0, elapsed - EXIT_START) * 2.94, 2.1) # 两端掠过更快，中间保持可读。
	_material.set_shader_parameter(&"leading_edge", lerpf(1.36, -0.36, open))
	_material.set_shader_parameter(&"trailing_edge", 1.36 if _blade_exit else lerpf(1.36, -0.36, close))
	_material.set_shader_parameter(&"blade_exit", close if _blade_exit else 0.0)
	_material.set_shader_parameter(&"dim", open * (1.0 - close) * 0.65)
	_material.set_shader_parameter(&"travel", line_travel)
	var fit: float = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y) # 横竖余量均保留人物比例。
	var origin: Vector2 = (size - DESIGN_SIZE * fit) * 0.5 # 以等比构图中心对齐当前视口。
	var portrait_slide: float = lerpf(340.0, 0.0, portrait_entry) - drift * 12.0 + close * 288.0 # 从右掠入并甩出。
	var title_slide: float = lerpf(-290.0, 0.0, title_entry) + drift * 11.0 - close * 312.0 # 对向进出形成交叉动势。
	var blade_offset: float = close if _blade_exit else 0.0 # 刀口上下两半各自沿退场方向散开。
	var portrait_alpha: float = smoothstep(0.035, 0.21, elapsed) * (1.0 - close) # 人物轮廓先于主幕收净。
	var title_alpha: float = smoothstep(0.085, 0.235, elapsed) * (1.0 - close) # 等幕布有足够对比度才显字。
	var title: Control = _title if _title.visible else _name_fallback # 两种标题走相同坐标和动线。
	_portrait.position = origin + (PORTRAIT_RECT.position + Vector2(portrait_slide, -drift * 4.0 - blade_offset * 112.0)) * fit
	_portrait.size = PORTRAIT_RECT.size * fit
	_portrait.modulate.a = portrait_alpha
	title.position = origin + (TITLE_RECT.position + Vector2(title_slide, blade_offset * 88.0)) * fit
	title.size = TITLE_RECT.size * fit
	title.pivot_offset = TITLE_RECT.size * fit * 0.5
	title.scale = Vector2(1.0 + blade_offset * 0.18, 1.0 - blade_offset * 0.66)
	title.modulate.a = title_alpha
	if _name_fallback.visible:
		var font_size: int = maxi(1, roundi(fit * 75.0)) # 未绘制专用字图时仍维持标题层级。
		if _name_fallback.get_theme_font_size("font_size") != font_size:
			_name_fallback.add_theme_font_size_override("font_size", font_size)
