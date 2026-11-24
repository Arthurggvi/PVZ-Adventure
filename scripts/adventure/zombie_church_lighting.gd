## 教堂的四段明暗状态。所有可见区域由同一个光场决定，时间以未暂停的真实秒计。
extends AdventurePhasePresentation

## 环境的常亮、熄灯、完全黑暗与恢复状态。
enum Phase { LIT, EXTINGUISHING, BLACKOUT, RELIGHTING }
## 兼容不同战场与棋盘的低分辨率世界光场。
const LightField = preload("res://scripts/battle/environment/battle_visibility_light_field.gd")
## 灯罩和出战角色的注册入口。
const LightSources = preload("res://scripts/adventure/zombie_church_light_sources.gd")
## 使用同一光场清除死者残影的棋盘机制。
const PlantRemains = preload("res://scripts/adventure/zombie_church_plant_remains.gd")
## 对教堂的卡槽和战斗 UI 统一调色。
const HudGrade = preload("res://scripts/adventure/zombie_church_hud.gd")
## 普通难度的亮灯窗口，单位真实秒，包含复光过渡。
const NORMAL_LIT_SECONDS := 10.0
## 噩梦难度的亮灯窗口，单位真实秒，包含复光过渡。
const NIGHTMARE_LIT_SECONDS := 5.0
## 入场前两种难度共用的熄灯窗口，单位真实秒，包含熄灯过渡。
const DARK_SECONDS := 10.0
## 烛火突然熄灭所需秒数。
const CUT_SECONDS := 0.28
## 复光前收去指针和路灯花残光所需的秒数。
const RELIGHT_DIP_SECONDS := 0.17
## 进入复光态后，第一缕环境光重新亮起的秒数。
const RELIGHT_GLOW_START := 0.24
## 复光态总秒数，包含残光收拢、无光换样和环境光恢复。
const RELIGHT_SECONDS := 0.88
## 结构替换范围，单位为 1916×821 原画像素。前五处为石像，第六处为受难像。
const STRUCTURES: Array[Rect2] = [
	Rect2(354, 24, 105, 168),
	Rect2(469, 24, 105, 171),
	Rect2(581, 23, 113, 173),
	Rect2(1232, 21, 111, 173),
	Rect2(1346, 23, 106, 175),
	Rect2(1451, 3, 203, 313),
]
## 受难像位始终随恢复过渡复原，石像位可由场景单独决定。
const CRUCIFIX_BIT := 1 << 5

## 叠有明亮原画和局部结构材质的战场精灵。
@export var artwork: Sprite2D
## 恢复环境光时让修女像转回原位。关闭后石像保留上一次的朝向。
@export var restore_statues_on_relight := true

## 当前环境状态，用于检测结构变化的切相时机。
var _phase := Phase.LIT
## 每个亮灯加熄灯周期中的进度，单位未暂停的真实秒。
var _cycle_seconds := 0.0
## 本阶段的亮灯窗口，切换难度时重新读取。
var _lit_seconds := NORMAL_LIT_SECONDS
## 未暂停的战斗秒数，用于低分辨率剪影图集的刷新。
var _light_seconds := 0.0
## 首轮从常亮开始，完整循环后才经过恢复态。
var _has_cycled := false
## Boss 登场或进入终末阶段后，本阶段保持环境熄灯。
var _permanent_blackout := false
## 上一次可处理帧的单调时钟读数，避免倍速和掉帧改变熄灯间隔。
var _last_ticks: int
## 当前已经改样的结构位掩码，每一区域独立等待脱离光照。
var _altered := 0
## 进入黑暗时尚待换样的区域位掩码。
var _pending := 0
## 棋盘格的平均世界跨度，用于把光圈设计尺寸换算为像素。
var _cell_span: float
## 画面当前的熄灯量，稳态避免重复写入合成材质。
var _darkness := 0.0
## 原画上蜡烛和窗洞的熄灯量。复光时可在无光帧先恢复材质。
var _room_extinction := 0.0
## 局部光的共同可见权重。常亮时不采样光场。
var _reveal_strength := 1.0
## 本帧是否需要在最终合成中读取红光遮罩。
var _has_red_light := false
## 有活跃裂隙时检查画面 Alpha 的范围，使用归一化屏幕坐标。
var _residual_bounds := Vector4.ZERO
## 教堂借用的世界视口。其捕获 Alpha 会在退出教堂时归还原配置。
var _world_viewport: Viewport
## 进入本场前世界视口的透明底开关。
var _world_was_transparent := false
## 复光时记录是否已经提交过原画恢复的全黑帧。
var _relight_room_restored := false

## 本场独占原画材质，用于蜡烛、窗洞与结构选择。
@onready var _room_material := artwork.material as ShaderMaterial
## 将世界与光场合成的单独材质，置于战斗 UI 之下。
@onready var _composite_material: ShaderMaterial = $Composite.material
## 低分辨率光场，只在明暗过渡与黑暗态渲染。
@onready var _field: LightField = $LightField
## 场景的灯与角色标定，不参与熄灯状态计时。
@onready var _light_sources: LightSources = $LightSources
## 死亡占格和连续暖光清除。
@onready var _plant_remains: PlantRemains = $PlantRemains
## 教堂为通用救主演出提供实际光场与亡影。
@onready var _savior_battle: SaviorBattle = $"../SaviorBattle"
## 置于战斗 UI 上方的独立界面合成。
@onready var _hud_grade: HudGrade = $HudGrade
## 跟随实际鼠标的世界锚点，注册方式和路灯花相同。
@onready var _cursor: Marker2D = $Cursor
## 本场战斗宿主，提供当前棋盘和相机。
@onready var _battle := get_parent() as MainGameManager

## 让正常的精灵 Alpha 混合自然遮住石面余热。合成仍输出不透明画面。
func _enter_tree() -> void:
	_world_viewport = get_viewport()
	_world_was_transparent = _world_viewport.transparent_bg
	_world_viewport.transparent_bg = true

## 离开教堂时恢复视口原有格式，其他关卡沿用各自的渲染设置。
func _exit_tree() -> void:
	if is_instance_valid(_world_viewport):
		_world_viewport.transparent_bg = _world_was_transparent

## 从棋盘几何推导光圈尺寸，绑定角色生命周期信号与画面合成。
func _ready() -> void:
	_cell_span = _light_sources.bind_battle(_battle, _field)
	var zombies: ZombieManager = _battle.get_node("Manager/ZombieManager") # 父战场初始化前接入正式登场信号。
	zombies.signal_living_bosses_changed.connect(_on_living_bosses_changed.bind(zombies))
	_field.register_light(_cursor, LightField.Tone.COOL, _cell_span * 0.88)
	_plant_remains.bind_battle(_battle, _field, is_in_darkness)
	_savior_battle.configure(_battle, _field, _plant_remains)
	_savior_battle.frozen_frame_requested.connect(_present_frozen_lights)
	_savior_battle.final_lights_changed.connect(_refresh_final_lights, CONNECT_DEFERRED)
	_composite_material.set_shader_parameter("light_field", _field.get_texture())
	_composite_material.set_shader_parameter("warm_radiance_scale", LightField.WARM_RADIANCE_SCALE)
	_composite_material.set_shader_parameter("red_light_field", _field.red_texture())
	var areas := PackedVector4Array() # 着色器与不被注视的结构判定共用一份几何数据。
	for region: Rect2 in STRUCTURES: # 上传每个区域的原图左上角和右下角。
		areas.append(Vector4(region.position.x, region.position.y, region.end.x, region.end.y))
	_room_material.set_shader_parameter("structure_areas", areas)
	_reset_cycle(AdventureSession.get_active_phase(_battle.game_para))
	if _permanent_blackout:
		_present(Phase.BLACKOUT, 1.0)

## [param phase] 已通过战场和钥匙预检后，圣堂支持噩梦循环和终末熄灯演出。
func prepare_phase(phase: StagePhaseDefinition) -> bool:
	return phase != null and phase.kind in [StagePhaseDefinition.Kind.NIGHTMARE, StagePhaseDefinition.Kind.TERMINAL]

## 已提交 [param phase] 后让噩梦从亮灯开始。终末在恢复战斗前先熄完烛火。
func play_phase(phase: StagePhaseDefinition) -> void:
	if not prepare_phase(phase):
		return
	_reset_cycle(phase)
	if not _permanent_blackout:
		# 第一段亮灯是新阶段的初始状态，同帧还原原画，不触发复光出怪。
		_present(Phase.RELIGHTING, 1.0, 0.0)
		_present(Phase.LIT, 0.0)
		return
	if _darkness < 1.0 or _reveal_strength < 1.0:
		var cut: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true) # 续战暂停中照常完成环境演出。
		cut.tween_method(_apply_blackout_cut.bind(_darkness, _reveal_strength), 0.0, 1.0, CUT_SECONDS)
		await cut.finished
	_present(Phase.BLACKOUT, 1.0)

## 为 [param phase] 重置明暗计时和本阶段的熄灯锁。无冒险阶段时使用普通节奏。
func _reset_cycle(phase: StagePhaseDefinition) -> void:
	_lit_seconds = NIGHTMARE_LIT_SECONDS if phase != null and phase.kind == StagePhaseDefinition.Kind.NIGHTMARE else NORMAL_LIT_SECONDS
	_permanent_blackout = phase != null and phase.kind == StagePhaseDefinition.Kind.TERMINAL
	_cycle_seconds = 0.0
	_has_cycled = false
	_last_ticks = Time.get_ticks_usec()

## [param zombies] 首次发布存活 Boss 的登场时立即熄灯，本阶段的分裂与退场均不会复光。
func _on_living_bosses_changed(zombies: ZombieManager) -> void:
	if _permanent_blackout or zombies.get_living_bosses().is_empty():
		return
	_permanent_blackout = true
	_present(Phase.BLACKOUT, 1.0)

## [param fraction] 按本次原地熄灯进度插值 [param darkness_at_start] 和 [param reveal_at_start]。
func _apply_blackout_cut(fraction: float, darkness_at_start: float, reveal_at_start: float) -> void:
	var weight: float = pow(smoothstep(0.0, 1.0, fraction), 0.55) # 沿用烛火骤灭的曲线。
	_present(Phase.EXTINGUISHING, lerpf(darkness_at_start, 1.0, weight), lerpf(reveal_at_start, 1.0, weight))

## 环境光归零时，植物失去身体会留下残影。局部灯光不改变环境状态。
func is_in_darkness() -> bool:
	return _darkness >= 1.0

## 时停特写由共用演出更新，教堂只随镜头刷新一次光场。
func _present_frozen_lights() -> void:
	_cursor.hide()
	_sync_residual_bounds()
	var bounds: Rect2 = get_viewport().get_visible_rect() # 使用正在滑动的同一部正式镜头。
	if bounds.has_area():
		_render_light_field(bounds, _battle.get_canvas_transform(), true)

## 暂停通知关闭遮罩更新后再补交一帧，收走临时技能灯并保留救主自己的光。
func _refresh_final_lights() -> void:
	if not is_inside_tree() or _battle.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
			or _phase == Phase.LIT or _reveal_strength <= 0.0:
		return
	var bounds: Rect2 = get_viewport().get_visible_rect() # 与最后一帧世界合成使用同一逻辑视口。
	if bounds.has_area():
		_render_light_field(bounds, _battle.get_canvas_transform(), true)

## [param what] 为暂停相关的场景通知，清除本帧的墙钟差值，恢复时继续原相位。
func _notification(what: int) -> void:
	if what != NOTIFICATION_PAUSED and what != NOTIFICATION_UNPAUSED:
		return
	_last_ticks = Time.get_ticks_usec()
	if is_instance_valid(_field) and _phase != Phase.LIT and _reveal_strength > 0.0:
		_field.set_rendering(what == NOTIFICATION_UNPAUSED)

## 明暗窗口按未暂停的单调时钟计时，不随战斗倍速变化。
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec() # 两帧之间实际流逝的时间。
	var seconds: float = float(now - _last_ticks) * 0.000001 # 微秒换算为秒。
	_last_ticks = now
	if _battle.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		_sync_residual_bounds()
		return
	if get_tree().paused:
		return # 分裂黑场可能在这一帧取得时停，导演下一帧只刷新表现。
	_light_seconds += seconds
	_sync_residual_bounds()
	_plant_remains.advance(seconds)
	if _permanent_blackout:
		_present(Phase.BLACKOUT, 1.0)
		return
	_cycle_seconds += seconds
	var cycle_duration: float = _lit_seconds + DARK_SECONDS # 当前难度的一整轮明暗时长。
	if _cycle_seconds >= cycle_duration:
		_has_cycled = true
		_cycle_seconds = fposmod(_cycle_seconds, cycle_duration)
	var after_cut: float = _cycle_seconds - _lit_seconds # 非负时进入黑暗窗口。
	if after_cut >= CUT_SECONDS:
		_present(Phase.BLACKOUT, 1.0)
	elif after_cut >= 0.0:
		_present(Phase.EXTINGUISHING, pow(smoothstep(0.0, CUT_SECONDS, after_cut), 0.55))
	elif _has_cycled and (_cycle_seconds < RELIGHT_SECONDS or _phase == Phase.BLACKOUT \
			or _phase == Phase.EXTINGUISHING):
		var darkness: float = 1.0 - smoothstep(RELIGHT_GLOW_START, RELIGHT_SECONDS, _cycle_seconds) # 短暂停黑后恢复环境光。
		var reveal: float = 1.0 - smoothstep(0.0, RELIGHT_DIP_SECONDS, _cycle_seconds) # 静止鼠标下的局部光也先收去。
		var already_restored: bool = _phase == Phase.RELIGHTING and _relight_room_restored # 只在本轮第一次完全收光时布置石像。
		_present(Phase.RELIGHTING, darkness, reveal)
		if not already_restored and _relight_room_restored and is_instance_valid(_battle.adventure_runtime):
			# 原画换样的同一帧，环境光和局部光均为零。下一缕烛光会直接照到就位的石像。
			_battle.adventure_runtime.on_lights_restored()
	else:
		_present(Phase.LIT, 0.0)

## 随镜头定位地表余热的读取范围，复制图像中未覆盖地板的像素没有余热语义。
func _sync_residual_bounds() -> void:
	var floor: Rect2 = _savior_battle.savior_channels.heat_bounds() # 合并各自的裂隙，没有有效网格时返回空矩形。
	var mapped := Vector4.ZERO # 零范围关闭余热分支。
	if floor.has_area():
		var view: Rect2 = _world_viewport.get_visible_rect() # 与 WorldCapture 共用累积画布变换。
		if view.has_area():
			var coverage: Rect2 = view.intersection(_battle.get_canvas_transform() * floor) # 不读取地板外像素。
			if coverage.has_area():
				var start: Vector2 = (coverage.position - view.position) / view.size # 屏幕左上端点。
				var finish: Vector2 = (coverage.end - view.position) / view.size # 屏幕右下端点。
				mapped = Vector4(start.x, start.y, finish.x, finish.y)
	if mapped != _residual_bounds:
		_residual_bounds = mapped
		_composite_material.set_shader_parameter(&"residual_bounds", mapped)

## 提交 [param next_phase]、环境熄灯量 [param darkness] 和局部光权重 [param reveal_strength]。
## 复光时先在全黑帧还原原画。进入黑暗时，区域脱离光照后才换样。
func _present(next_phase: Phase, darkness: float, reveal_strength: float = 1.0) -> void:
	if next_phase != _phase:
		_phase = next_phase
		if next_phase == Phase.BLACKOUT:
			_pending = ((1 << STRUCTURES.size()) - 1) & ~_altered
		elif next_phase == Phase.RELIGHTING:
			_relight_room_restored = false
	var room_extinction: float = darkness # 烛台和窗洞默认随环境明暗变化。
	if next_phase == Phase.RELIGHTING and reveal_strength == 0.0:
		if not _relight_room_restored:
			# 跳帧跨过停黑区间时，仍保留一帧全黑来遮住换样。
			darkness = 1.0
			_altered = 0 if restore_statues_on_relight else _altered & ~CRUCIFIX_BIT
			_room_material.set_shader_parameter("structure_mask", _altered)
			_relight_room_restored = true
		room_extinction = 0.0
	if room_extinction != _room_extinction:
		_room_extinction = room_extinction
		_room_material.set_shader_parameter("extinction", room_extinction)
	if darkness != _darkness:
		_darkness = darkness
		_composite_material.set_shader_parameter("ambient", 1.0 - darkness)
		_hud_grade.set_darkness(darkness)
	if reveal_strength != _reveal_strength:
		_reveal_strength = reveal_strength
		_composite_material.set_shader_parameter("reveal_strength", reveal_strength)
	var needs_field: bool = next_phase != Phase.LIT and reveal_strength > 0.0 # 只有可见的局部光需要更新光场。
	_field.set_rendering(needs_field)
	if not needs_field:
		return
	var viewport: Viewport = get_viewport() # 战斗和合成共用的主视口。
	var bounds: Rect2 = viewport.get_visible_rect() # 支持实际窗口拉伸与镜头变换。
	if not bounds.has_area():
		return
	var pointer: Vector2 = viewport.get_mouse_position() # 直接追随当前鼠标位置。
	var world_to_view: Transform2D = _battle.get_canvas_transform() # 世界到主视口的相机变换。
	_cursor.visible = get_window().has_focus() and bounds.has_point(pointer)
	_cursor.global_position = world_to_view.affine_inverse() * pointer
	_render_light_field(bounds, world_to_view)
	if next_phase == Phase.BLACKOUT and _pending != 0:
		_change_unseen_structures()

## 用 [param bounds] 和 [param world_to_view] 提交光场。[param single_frame] 只刷新一次冻结的遮罩。
func _render_light_field(bounds: Rect2, world_to_view: Transform2D, single_frame: bool = false) -> void:
	var has_red_light: bool = _field.render_lights(bounds, world_to_view, _light_seconds, single_frame) # 红光离场时立即跳过旧遮罩。
	if has_red_light != _has_red_light:
		_has_red_light = has_red_light
		_composite_material.set_shader_parameter("has_red_light", has_red_light)

## 用同一组有效光圈检查原画区域。区域已被照亮时保持它原有的样子。
func _change_unseen_structures() -> void:
	var changed: int = _altered # 一帧内的所有可换样区域一起提交材质。
	var art_to_world: Transform2D = artwork.global_transform # 原画像素转换为战场坐标。
	for index: int in range(STRUCTURES.size()): # 每个塑像单独受观察条件约束。
		var bit: int = 1 << index # 对应这一处变化的位。
		if (_pending & bit) == 0 or _field.lights_intersect(art_to_world * STRUCTURES[index]):
			continue
		changed |= bit
		_pending &= ~bit
	if changed != _altered:
		_altered = changed
		_room_material.set_shader_parameter("structure_mask", changed)
