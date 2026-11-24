## 妇人一阶段使用 36 帧待机与杖击，转为凯莱赫时切换到 60 帧慢速待机。
## 一阶段的冰封统一使用 [method Plant000Base.apply_hunter_ice_shell]。
extends ZB000Base
class_name ZB006Cailleach

## 一阶段杖尖触地、已启动视听效果后发出的时序信号。
signal staff_impact
## 杖击回归一阶段站姿后通知外部技能层。
signal staff_finished

## 二阶段图集的单帧尺寸，用于按战斗视口等比排版。
const PHASE_TWO_FRAME_SIZE: Vector2 = Vector2(836.0, 470.0)
## 天幕构图以视口横向比例和图顶高度定位，让亮眼高于雪脊并避开出战栏。
const SKY_ART_ANCHOR := Vector2(0.57, -0.072)
## 原画在天幕中相对全屏覆盖的缩放比，保留两侧风雪与山脊轮廓。
const SKY_ART_SCALE: float = 0.88
## 现身时原画从雪脊后上升的距离，单位为图集像素。
const SKY_REVEAL_RISE: float = 67.0
## 战斗和图鉴共用二阶段原画场景，在切至二阶段时才加载。
const PHASE_TWO_SCENE_PATH: String = "res://scenes/character/zombie_boss/cailleach_phase2_visual.tscn"
## 一阶段只由当前视觉节点持有，不再静态进入Boss逻辑根资源。
const PHASE_ONE_SCENE_PATH: String = "res://scenes/character/zombie_boss/cailleach_visual.tscn"
## 杖击实战演出，仅从原画触地事件启动。
const StaffImpact = preload("res://scripts/character/zombie_boss/cailleach/cailleach_staff_impact.gd")
## 随本体生命周期播放显形或消隐的白雾传送。
const SnowTeleport = preload("res://scripts/character/zombie_boss/cailleach/cailleach_snow_teleport.gd")
## 一阶段的技能、随机池及结算时钟。
const PhaseOne = preload("res://scripts/character/zombie_boss/cailleach/cailleach_phase_one.gd")
## 白障合拢后才切换原画的二阶段显现。
const PhaseTwoReveal = preload("res://scripts/character/zombie_boss/cailleach/cailleach_phase_two_reveal.gd")
## 二阶段技能共用的愠怒动作，在眼中星爆的一拍结算。
const Anger = preload("res://scripts/character/zombie_boss/cailleach/cailleach_anger.gd")
## 二阶段与妇人共用的植物状态、落星及雪弹结算。
const SkillEffects = preload("res://scripts/character/zombie_boss/cailleach/cailleach_skill_effects.gd")
## 死亡与极光同帧起风雪，随后让原画从远景消隐。
const DeathDeparture = preload("res://scripts/character/zombie_boss/cailleach/cailleach_death_departure.gd")
## 二阶段显形或收势后，重新抽取技能前的基础等待时间，单位为动作秒。
const PHASE_TWO_INTERVAL: float = 4.5
## 一阶段常驻的本体伤害减免比例。
const PHASE_ONE_DAMAGE_REDUCTION: float = 0.2
## 二阶段替换一阶段来源的伤害减免比例。
const PHASE_TWO_DAMAGE_REDUCTION: float = 0.4
## 二阶段仰望的随机极光数。
const PHASE_TWO_AURORAS: int = 9
## 二阶段每发极光叠加的悲寒层数。
const PHASE_TWO_AURORA_GRIEF: int = 2
## 二阶段呼啸最多覆盖的不同路线数。
const PHASE_TWO_HOWL_LANES: int = 3
## 二阶段呼啸每路 200 枚实际雪弹，单发 10 点基础伤害。
const PHASE_TWO_HOWL_SHOTS: int = 200
## 雪山提供的三段棋盘地形沉降，其他战场可直接交给显现。
const TerrainCollapse = preload("res://scripts/adventure/snow_mountain_collapse.gd")
## 远景原画和穿过雪脊的雾带共用实景天光。
const SKY_PORTRAIT_SHADER: Shader = preload("res://shaders/adventure/wonderland/cailleach_sky_portrait.gdshader")
## 雪脊雾带复用显现时已有的卷雾纹理。
const RIDGE_CLOUD_PATH: String = "res://assets/adventure/environment_fx/v1/zombie_island/fog/fog_03.png"
## 半血退场比击败退场多留一拍，之后将舞台让给地震。
const PHASE_DEPARTURE_SECONDS: float = 2.16
## 抬杖时逐渐增加的嗡鸣音源，首次在实战起手时加载。
const STAFF_HUM_PATH: String = "res://resources/adventure/audio/cailleach_staff_charge.ogg"

## 一阶段原画，缩放以场景脚点为原点。
var _visual: CailleachVisual
## 一阶段第 18 帧的真实杖尖；随原画的缩放和朝向变换。
var _staff_contact: Marker2D
## 起手嗡鸣由本体持有，触地或动作中断即让出音轨。
@onready var _staff_hum: AudioStreamPlayer = $StaffHum
## 二阶段屏幕坐标层，有独立天空和地形层时插在二者之间。
@onready var _phase_two_layer: CanvasLayer = $PhaseTwoCanvas
## 二阶段播放器：进入二阶段后才实例化以节省进入战场时的内存。
var _phase_two_visual: AnimatedSprite2D
## 是否在场景为天空与地形保留的中间深度，决定面部位置和出雾高度。
var _phase_two_in_sky: bool = false
## 二阶段显现已经完成，当前称谓可以从妇人切换为凯莱赫。
var _phase_two_name_revealed: bool = false
## 从白障合拢到余雪退去的当前「显现」。
var _phase_two_reveal: PhaseTwoReveal
## 原画边缘读取各帧自己的图集区域，不向相邻动画帧串色。
var _sky_portrait_material: ShaderMaterial
## 常驻低云紧贴真实雪脊，位于人物之前与地形之后。
var _sky_ridge_veil: ColorRect
## 使中间画布的云和人物都使用实景镜头投影。
var _sky_terrain_canvas: CanvasLayer
## 人物与雪脊低云的天光来源。
var _sky_weather: SnowEnvironmentController
## 原画构图建立时的相机屏幕位移，用于派生轻微中景视差。
var _sky_camera_origin := Vector2.ZERO
## 构图的屏幕坐标，不含镜头移位。
var _sky_pose_anchor := Vector2.ZERO
## 从退场到显现结束之前，避免玩家攻击中断实体换位。
var _transitioning: bool = false
## 登场后的半血保护是否由本体安装，转阶段时交还原值。
var _phase_hp_floor: int = -1
## 活跃的传送演出，由本体持有，结束后清除引用。
var _teleport: SnowTeleport
## 传送入场结束后才接入的阶段行动。
var _phase_one: PhaseOne
## 正在进行的愠怒，期间免疫伤害并暂停二阶段抽取。
var _anger: Anger
## 一次正常二阶段死亡的演出资格，最后一阵雪停后才归还胜利结算。
var _defeat_presentation: bool = false
## 凯莱赫显现后创建的本阶段共用结算源。
var _phase_two_effects: SkillEffects
## 额外登记到本场二阶段的技能结算。
var _phase_two_skills: Array[Callable] = []
## 二阶段待机时的单次随机抽取计时，按本体行动倍率推进。
var _phase_two_clock: SpeedTimer

## 保留角色原有初始化；屏幕变化时独立调整半身原画大小。
func _ready() -> void:
	super._ready()
	hp_component.damage_reduction.set_source(get_instance_id(), damage_reduction_for_phase(boss_phase))
	set_process(false)
	signal_action_rate_changed.connect(_on_action_rate_changed)
	get_viewport().size_changed.connect(_layout_phase_two)
	_apply_boss_visual_phase(boss_phase, false)
	var battle: MainGameManager = _active_battle() # 展示实例没有正式战场，不播放传送。
	if boss_phase < 2 and battle != null and not is_death and not is_queued_for_deletion():
		_phase_hp_floor = hp_component.combat_minimum_hp
		hp_component.combat_minimum_hp = maxi(_phase_hp_floor, ceili(hp_component.max_hp * phase_two_threshold_ratio) - 1)
		_start_snow_teleport(battle, true)

## [param rate] 同步原画和已启动的技能时钟，保留当前帧与等待进度。
func _on_action_rate_changed(rate: float) -> void:
	if is_instance_valid(_visual):
		_visual.set_action_rate(rate)
	if is_instance_valid(_phase_one):
		_phase_one.set_action_rate(rate)
	if is_instance_valid(_phase_two_visual):
		_phase_two_visual.speed_scale = rate
	if is_instance_valid(_phase_two_clock):
		_phase_two_clock.set_speed_scale(rate)

## 一阶段雾散后使用现有的演出结束信号亮出钻石。
func drop_diamond_after_presentation() -> bool:
	return boss_phase < 2

## 不指定 [param phase] 时返回演出已公开的称谓，图鉴仍可直接查询指定阶段。
func get_boss_display_name(phase: int = 0) -> String:
	var display_phase: int = phase if phase != 0 else (2 if _phase_two_name_revealed else 1) # 血量门槛与身份揭晓各自推进。
	return super.get_boss_display_name(display_phase)

## [param revealed] 为 true 时公开凯莱赫的称谓，只在确实切换时刷新界面。
func _set_phase_two_name_revealed(revealed: bool) -> void:
	if _phase_two_name_revealed != revealed:
		_phase_two_name_revealed = revealed
		signal_boss_display_name_changed.emit()

## 返回 [param phase] 的常驻减伤比例，供战斗和图鉴共用。
static func damage_reduction_for_phase(phase: int) -> float:
	return PHASE_TWO_DAMAGE_REDUCTION if phase >= 2 else PHASE_ONE_DAMAGE_REDUCTION

## 进入二阶段时替换原减伤来源，再按 [param animated] 执行基类的阶段切换。
func _enter_phase_two(animated: bool) -> void:
	hp_component.damage_reduction.set_source(get_instance_id(), PHASE_TWO_DAMAGE_REDUCTION)
	super._enter_phase_two(animated)

## [param damage] 已按来源修正的灰烬伤害，奇数向下取整；随后仍按阶段减伤结算。
func ash_damage_received(damage: int) -> int:
	return damage >> 1

## 播放一次一阶段的杖击原画，实战起手时加入蓄势嗡鸣。返回是否成功启动。
func perform_staff_tap() -> bool:
	if boss_phase >= 2 or is_death or not is_inside_tree() or is_queued_for_deletion() or is_instance_valid(_teleport):
		return false
	if not is_instance_valid(_visual) or not _visual.play_staff_tap():
		return false
	if _active_battle() != null:
		if _staff_hum.stream == null:
			_staff_hum.stream = load(STAFF_HUM_PATH) as AudioStream
		if _staff_hum.stream != null:
			_staff_hum.bus = SoundManager.spatial_sfx_bus(SoundManagerClass.SFXSpace.COMBAT)
			_staff_hum.play()
	return true

## [param restore_idle] 指定是否恢复一阶段站姿；死亡可保留停顿帧。
func cancel_staff_tap(restore_idle: bool = true) -> void:
	if is_instance_valid(_staff_hum):
		_staff_hum.stop()
	if is_instance_valid(_visual):
		_visual.cancel_staff_tap(restore_idle)

## [param phase] 为 Boss 基类提交的阶段，[param animated] 只在实战血量转换时播放「显现」。
func _apply_boss_visual_phase(phase: int, animated: bool) -> void:
	if not is_instance_valid(_phase_two_layer):
		return
	if phase < 2:
		if not _ensure_phase_one_visual():
			return
		_set_phase_two_name_revealed(false)
		_stop_phase_two_actions()
		_clear_anger()
		_visual.show()
		set_process(false)
		_phase_two_layer.hide()
		_phase_two_layer.process_mode = Node.PROCESS_MODE_DISABLED
		if is_instance_valid(_phase_two_visual):
			_phase_two_visual.queue_free()
			_phase_two_visual = null
		cancel_staff_tap()
		return
	_stop_phase_one()
	cancel_staff_tap(false)
	if _phase_hp_floor >= 0 and not retreat_after_phase_two:
		hp_component.combat_minimum_hp = _phase_hp_floor
	var battle: MainGameManager = _active_battle() if animated else null # 静默读档与图鉴按已有协议直接恢复画面。
	if battle != null:
		_transitioning = true
		hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Prepare)
		var snow: SnowEnvironmentController = battle.background_manager.snow_environment # 退场掠风后仍让棋盘清楚可见。
		if is_instance_valid(snow):
			snow.play_wind_burst(Vector2(-820.0, 78.0), 2.45, 0.42)
		_start_snow_teleport(battle, false, PHASE_DEPARTURE_SECONDS)
	else:
		if is_instance_valid(_teleport):
			_teleport.stop()
			_teleport = null
		_show_phase_two_pose()

## 传送退场后，等待 [param battle] 的雪山沉降结束，再开始显现。
func _after_phase_two_departure(battle: MainGameManager) -> void:
	var collapse := battle.get_node_or_null(^"TerrainCollapse") as TerrainCollapse # 雪山的专用地形演出。
	if collapse != null and collapse.begin(self):
		collapse.finished.connect(_after_terrain_collapse, CONNECT_ONE_SHOT)
		return
	_start_phase_two_reveal(battle)

## 棋盘已完成三次提交且可重新交互，从此帧接手天气。
func _after_terrain_collapse() -> void:
	var battle: MainGameManager = _active_battle() # 结算或切场不会创建新的演出。
	if battle != null and not is_death:
		_start_phase_two_reveal(battle)

## 用 [param battle] 的实时暴雪替本次显现起势，白障到峰值后才接入原画。
func _start_phase_two_reveal(battle: MainGameManager) -> void:
	_phase_two_in_sky = _place_phase_two_between_sky_and_terrain()
	if _phase_two_in_sky:
		_phase_two_layer.show() # 山脊后的风雾先起，白障合拢时才创建凯莱赫原画。
		_phase_two_layer.process_mode = Node.PROCESS_MODE_INHERIT
	_phase_two_reveal = PhaseTwoReveal.new(battle.background_manager.snow_environment,
		_phase_two_layer if _phase_two_in_sky else null)
	_phase_two_reveal.covered.connect(_on_phase_two_covered)
	_phase_two_reveal.finished.connect(_on_phase_two_reveal_finished)
	add_child(_phase_two_reveal)

## 白障最厚时安装原画，随后由近雪与山脊自然遮挡。
func _on_phase_two_covered() -> void:
	if _show_phase_two_pose():
		_phase_two_reveal.set_pose(_phase_two_visual, SKY_REVEAL_RISE if _phase_two_in_sky else 0.0)

## 演出正常结束后，原画接着播放慢速待机。
func _on_phase_two_reveal_finished() -> void:
	_phase_two_reveal = null
	_transitioning = false
	if is_instance_valid(_phase_two_visual):
		_set_phase_two_name_revealed(true)
	hurt_box_component.enable_component(ComponentNormBase.E_IsEnableFactor.Prepare)
	signal_status_update.emit()
	_arm_phase_two_clock()

## 将无参数的 [param effect] 加入二阶段随机抽取。它仅在愠怒的实际星爆关键帧运行。
func register_phase_two_skill(effect: Callable) -> void:
	if effect.is_valid() and not _phase_two_skills.has(effect):
		_phase_two_skills.append(effect)
		_arm_phase_two_clock()

## 在有二阶段原画的正式雪战中开始愠怒。[param effect] 为空时可仅预览演出。
## 成功启动返回 true。已有变身或施法、战场未就绪时保留原时钟和当前动作。
func perform_anger(effect: Callable = Callable()) -> bool:
	var battle: MainGameManager = _anger_battle() # 只在当前正式暴雪场景消费技能。
	if battle == null or not can_process():
		return false
	if is_instance_valid(_phase_two_clock):
		_phase_two_clock.stop()
	var veil := _sky_ridge_veil.material as ShaderMaterial # 施法期间持有原有雪脊低云。
	_anger = Anger.new(battle, _phase_two_visual, _sky_portrait_material, veil, effect)
	_anger.finished.connect(_on_anger_finished, CONNECT_ONE_SHOT)
	hp_component.set_immunity_source(get_instance_id(), true)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	add_child(_anger)
	signal_status_update.emit()
	return true

## 返回能够启动二阶段演出的正式雪场，避免图鉴、转阶段及特殊撤离进入行动池。
func _anger_battle() -> MainGameManager:
	if (not is_node_ready() or boss_phase < 2 or _transitioning or retreat_after_phase_two
			or is_death or is_queued_for_deletion() or is_instance_valid(_anger)
			or not is_instance_valid(_phase_two_visual) or not is_instance_valid(_sky_weather)
			or not is_instance_valid(_sky_ridge_veil)):
		return null
	return _active_battle()

## 慢动作完全收势后才重新进入下一轮，不把施法时间算入抽取间隔。
func _arm_phase_two_clock() -> void:
	var battle: MainGameManager = _anger_battle() # 转阶段与被击败后的角色均不启动技能。
	if battle == null:
		return
	if not is_instance_valid(_phase_two_effects):
		_phase_two_effects = SkillEffects.new(battle, self)
		add_child(_phase_two_effects)
	if not is_instance_valid(_phase_two_clock):
		_phase_two_clock = SpeedTimer.new()
		_phase_two_clock.name = "PhaseTwoActionClock"
		_phase_two_clock.one_shot = true
		_phase_two_clock.base_wait_time = PHASE_TWO_INTERVAL
		_phase_two_clock.set_speed_scale(action_rate())
		_phase_two_clock.timeout.connect(_draw_phase_two_skill)
		add_child(_phase_two_clock)
	if _phase_two_clock.is_stopped():
		_phase_two_clock.start_scaled()

## 按当前场况随机抽取一项。「安息吧」只有满悲寒与冻结同时在场时入池。
func _draw_phase_two_skill() -> void:
	if not is_instance_valid(_phase_two_effects) or not _phase_two_effects.is_active():
		_arm_phase_two_clock()
		return
	var choices: Array[Callable] = [_phase_two_effects.sleep, _phase_two_aurora, _phase_two_howl] # 三个固定候选等权。
	if _phase_two_effects.can_rest():
		choices.append(_phase_two_effects.rest)
	_phase_two_skills = _phase_two_skills.filter(func(effect: Callable) -> bool: return effect.is_valid())
	choices.append_array(_phase_two_skills)
	if not perform_anger(choices.pick_random()):
		_arm_phase_two_clock()

## 星爆后引发九次极光冲击，最后一发命中后允许收势，已经凝成的星河冰继续消散。
func _phase_two_aurora() -> void:
	var barrage: Node2D = _phase_two_effects.aurora(PHASE_TWO_AURORAS, PHASE_TWO_AURORA_GRIEF) # 只等待实际落星。
	if is_instance_valid(barrage):
		await Signal(barrage, &"impacts_finished")

## 星爆后释放三路贴坡雪暴，等待弹幕结算并退场。
func _phase_two_howl() -> void:
	var barrage: Node2D = _phase_two_effects.howl(PHASE_TWO_HOWL_LANES, PHASE_TWO_HOWL_SHOTS) # 最多覆盖三条现存攻击行。
	if is_instance_valid(barrage):
		await barrage.tree_exited

## 离开二阶段时同步停止计时和在途技能，当前阶段的回调随后一并失效。
func _stop_phase_two_actions() -> void:
	if is_instance_valid(_phase_two_clock):
		_phase_two_clock.stop()
	if is_instance_valid(_phase_two_effects):
		_phase_two_effects.queue_free()
		_phase_two_effects = null

## 雪停、白影归还后撤销本次免伤并启动下一轮。
func _on_anger_finished() -> void:
	_clear_anger()
	_arm_phase_two_clock()

## 收势、死亡或切换表现都执行同一份清理，不移除其他伤害免疫来源。
func _clear_anger() -> void:
	if not is_instance_valid(_anger):
		return
	_anger.stop()
	_anger = null
	hp_component.set_immunity_source(get_instance_id(), false)
	if not is_death:
		hurt_box_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)
		signal_status_update.emit()

## 往返世界和天幕期间，所有普通与特殊命中都共用原有受击门禁。
func _can_receive_damage() -> bool:
	return not _transitioning and not is_instance_valid(_anger) and super._can_receive_damage()

## 仅在需要一阶段时构造原生视觉节点，原场景比例及杖尖挂点保持不变。
func _ensure_phase_one_visual() -> bool:
	if is_instance_valid(_visual):
		return true
	var scene: PackedScene = load(PHASE_ONE_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("妇人一阶段原画不可用")
		return false
	_visual = scene.instantiate() as CailleachVisual
	if _visual == null:
		return false
	_visual.scale = Vector2(0.8,0.8)
	$Body.add_child(_visual)
	_staff_contact = _visual.get_node("StaffContact") as Marker2D
	_visual.staff_impact.connect(_on_staff_impact)
	_visual.staff_finished.connect(_on_staff_finished)
	_visual.set_action_rate(action_rate())
	return true

## 不影响独立的HUD头像、二阶段技能或逻辑碰撞。
func _release_phase_one_visual() -> void:
	if is_instance_valid(_visual):
		_visual.hide()
		_visual.queue_free()
	_visual = null
	_staff_contact = null

## 第一次使用时载入既有图集，之后共享常驻的慢速待机。
func _show_phase_two_pose() -> bool:
	if is_death:
		return false
	if not is_instance_valid(_phase_two_reveal):
		_phase_two_in_sky = _place_phase_two_between_sky_and_terrain()
	if not _ensure_phase_two_visual():
		return false
	_release_phase_one_visual() # 白障覆盖或静默恢复，旧原画和衔接材质随节点释放。
	shadow.hide()
	_phase_two_layer.show()
	_phase_two_layer.process_mode = Node.PROCESS_MODE_INHERIT
	_phase_two_visual.modulate.a = 1.0
	set_process(is_instance_valid(_sky_portrait_material))
	_phase_two_visual.speed_scale = action_rate()
	_phase_two_visual.play(&"idle")
	_phase_two_visual.set_frame_and_progress(0, 0.0)
	if not _transitioning:
		_set_phase_two_name_revealed(true) # 读档直接恢复完整二阶段外观，同帧公开称谓。
	_arm_phase_two_clock()
	return true

## 当场景将天幕与地板分层时，由其真实层号确定凯莱赫的中间深度。
func _place_phase_two_between_sky_and_terrain() -> bool:
	var battle: MainGameManager = _active_battle() # 非正式战场沿用原画预览层。
	if battle == null:
		return false
	var background: BackgroundManager = battle.background_manager # 当前场景提供的天空与地形节点。
	if not is_instance_valid(background.environment_sky) or not is_instance_valid(background.background):
		return false
	var sky: CanvasLayer = background.environment_sky.get_parent() as CanvasLayer # 天幕使用独立画布。
	var terrain: CanvasLayer = background.background.get_parent() as CanvasLayer # 实际雪脊仍以地板材质裁边。
	if sky == null or terrain == null or terrain.layer - sky.layer < 2:
		return false
	_phase_two_layer.layer = terrain.layer - 1
	_sky_terrain_canvas = terrain
	_sky_weather = background.snow_environment
	return true

## 创建仅含 60 帧 idle 的原生 AnimatedSprite2D；缺失资源时维持一阶段显示。
func _ensure_phase_two_visual() -> bool:
	if is_instance_valid(_phase_two_visual):
		return true
	var scene: PackedScene = load(PHASE_TWO_SCENE_PATH) as PackedScene # 实战白障闭合后才读取图集。
	if scene == null:
		push_error("凯莱赫二阶段原画场景不可用。")
		return false
	var instance: Node = scene.instantiate() # 临时实例在接口检验后才交给 CanvasLayer。
	var sprite: AnimatedSprite2D = instance as AnimatedSprite2D
	if sprite == null:
		instance.free()
		push_error("凯莱赫二阶段原画场景根节点必须为 AnimatedSprite2D。")
		return false
	_phase_two_layer.add_child(sprite)
	_phase_two_visual = sprite
	if _phase_two_in_sky:
		_sky_portrait_material = ShaderMaterial.new()
		_sky_portrait_material.shader = SKY_PORTRAIT_SHADER
		sprite.material = _sky_portrait_material
		sprite.frame_changed.connect(_sync_sky_portrait_frame)
		_sync_sky_portrait_frame()
		if is_instance_valid(_sky_weather):
			_build_ridge_veil()
			_sky_weather.bind_sky_subject(_sky_portrait_material)
	_layout_phase_two()
	return true

## 只在当前帧区域内取透明轮廓及相邻像素，消除毛边并避免图集污染。
func _sync_sky_portrait_frame() -> void:
	var atlas := _phase_two_visual.sprite_frames.get_frame_texture(_phase_two_visual.animation, _phase_two_visual.frame) as AtlasTexture # 二阶段原画的实际帧。
	if atlas == null or atlas.atlas == null:
		return
	var page: Vector2 = atlas.atlas.get_size() # 在整张纹理中定位当前帧的四条边。
	var bounds: Rect2 = atlas.region # 着色器会再收半像素，防止边缘插值跨帧。
	_sky_portrait_material.set_shader_parameter(&"frame_uv", Vector4(bounds.position.x / page.x,
		bounds.position.y / page.y, bounds.end.x / page.x, bounds.end.y / page.y))

## 显现后的雪脊保留一层卷雾，让人物和背后的天空一起经过近侧风雪。
func _build_ridge_veil() -> void:
	var material := ShaderMaterial.new() # 与原画共用坐标和色温，绘制分支只采样雪云。
	material.shader = SKY_PORTRAIT_SHADER
	material.set_shader_parameter(&"ridge_veil", true)
	material.set_shader_parameter(&"blowing_snow", load(RIDGE_CLOUD_PATH))
	_sky_weather.bind_sky_subject(material)
	_sky_ridge_veil = ColorRect.new()
	_sky_ridge_veil.name = "RidgeSpindrift"
	_sky_ridge_veil.z_index = 1
	_sky_ridge_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_ridge_veil.material = material
	_phase_two_layer.add_child(_sky_ridge_veil)

## [param _delta] 不推进独立时钟。镜头、极光和世界雪墙直接采样本场状态。
func _process(_delta: float) -> void:
	if not is_instance_valid(_sky_terrain_canvas) or not is_instance_valid(_phase_two_visual):
		return
	var camera: Transform2D = _sky_terrain_canvas.get_final_transform() # 此画布与天空使用同一镜头。
	var view: Rect2 = get_viewport().get_visible_rect() # 场景中各层对应相同逻辑视口。
	var world: Rect2 = camera.affine_inverse() * view # 画面中的世界雪线位置。
	var world_bounds := Vector4(world.position.x, world.position.y, world.size.x, world.size.y) # 矩形展开成着色器参数。
	_phase_two_visual.position = _sky_pose_anchor + (camera.origin - _sky_camera_origin) * 0.65
	_sky_portrait_material.set_shader_parameter(&"world_view", world_bounds)
	if is_instance_valid(_sky_weather) and is_instance_valid(_sky_ridge_veil):
		var weather: Vector3 = _sky_weather.sky_subject_weather() # 能见度、世界雪墙位移和极光明灭。
		var veil := _sky_ridge_veil.material as ShaderMaterial # 与原画的坐标和天气保持同步。
		_sky_portrait_material.set_shader_parameter(&"storm", weather)
		veil.set_shader_parameter(&"world_view", world_bounds)
		veil.set_shader_parameter(&"storm", weather)

## 保持原画宽高比，大场景将视线置于雪脊上方，其余场景保持原来的居中构图。
func _layout_phase_two() -> void:
	if not is_instance_valid(_phase_two_visual):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size # 当前屏幕可见范围。
	var fill_scale: float = maxf(viewport_size.x / PHASE_TWO_FRAME_SIZE.x,
		viewport_size.y / PHASE_TWO_FRAME_SIZE.y) # 取最大比值保证满屏无留白。
	if _phase_two_in_sky:
		var battle: MainGameManager = _active_battle() # 下沉后新增的天幕高度用于展示披风和辫子。
		var larger_sky: bool = battle != null and is_instance_valid(battle.main_game_slope) and battle.main_game_slope.position.y > 1.0 # 沉降后的构图有更多纵深。
		fill_scale *= 0.84 if larger_sky else SKY_ART_SCALE
		var anchor: Vector2 = Vector2(0.59, 0.015) if larger_sky else SKY_ART_ANCHOR # 留出帽顶和两侧极光。
		_sky_pose_anchor = viewport_size * anchor + Vector2(0.0, PHASE_TWO_FRAME_SIZE.y * fill_scale * 0.5)
		_sky_camera_origin = _sky_terrain_canvas.get_final_transform().origin
		_phase_two_visual.position = _sky_pose_anchor
		if is_instance_valid(_sky_ridge_veil):
			_sky_ridge_veil.position = Vector2(0.0, viewport_size.y * 0.075)
			_sky_ridge_veil.size = viewport_size * Vector2(1.0, 0.72)
	else:
		_phase_two_visual.position = viewport_size * 0.5
	_phase_two_visual.scale = Vector2.ONE * fill_scale

## 正式二阶段死亡先召来极光，再在真实暴雪中退场并归还胜利结算。
func character_death() -> void:
	if is_death:
		return
	var battle: MainGameManager = _active_battle() # 死亡信号可能立即把战斗变为等待奖杯。
	_defeat_presentation = (boss_phase >= 2 and battle != null and forced_defeat_source.is_empty()
		and is_instance_valid(battle.background_manager.snow_environment))
	super.character_death()
	_stop_phase_one()
	_stop_phase_two_actions()
	_clear_anger()
	cancel_staff_tap(false)
	if is_instance_valid(_phase_two_reveal):
		_phase_two_reveal.stop()
		_phase_two_reveal = null
	if _defeat_presentation:
		_play_defeat_presentation(battle)
		return
	if boss_phase < 2 and is_instance_valid(battle) and not battle.is_queued_for_deletion() and not is_queued_for_deletion():
		_start_snow_teleport(battle, false)
		return
	if is_instance_valid(_phase_two_visual) and _phase_two_layer.visible:
		var fade: Tween = create_tween() # 独立画面层不继承角色根节点透明度。
		fade.tween_property(_phase_two_visual, ^"modulate:a", 0.0, 1.0)
		if is_instance_valid(_sky_ridge_veil):
			fade.parallel().tween_property(_sky_ridge_veil, ^"modulate:a", 0.0, 1.0)
	request_trophy()
	_fade_and_remove()

## 把常规清场与 Boss 奖杯的发布延到凯莱赫最后一阵风雪结束。
func delays_victory_for_defeat_presentation() -> bool:
	return _defeat_presentation

## 在 [param battle] 仍持有本次死亡流程时，落星与风雪同步开始，末发结算后才收势。
func _play_defeat_presentation(battle: MainGameManager) -> void:
	var active: Callable = _can_finish_defeat_presentation.bind(battle) # 已进入等待奖杯仍可结算这次死亡。
	if active.call():
		var snow: SnowEnvironmentController = battle.background_manager.snow_environment # 原战场拥有真正的落雪和风声。
		var ridge: ShaderMaterial = _sky_ridge_veil.material as ShaderMaterial if is_instance_valid(_sky_ridge_veil) else null # 保留真实雪脊遮挡。
		var departure := DeathDeparture.new(snow, _phase_two_visual, _sky_portrait_material, ridge) # 起雪及白光与死亡同帧。
		add_child(departure)
		var effects := SkillEffects.new(battle, self) # 与已停用的二阶段行动相隔离，随死亡演出离场。
		add_child(effects)
		var barrage: Node2D = effects.death_aurora(active) # 第一枚死亡当帧开始，之后每发独立错峰。
		if is_instance_valid(barrage):
			barrage.name = "CailleachDeathAurora"
			await Signal(barrage, &"impacts_finished")
		if active.call():
			departure.begin_dissolve()
			await departure.finished
	if active.call():
		request_trophy()
	_defeat_presentation = false
	queue_free()

## [param battle] 仍允许这名已倒下的 Boss 完成最后行动时返回真。
func _can_finish_defeat_presentation(battle: MainGameManager) -> bool:
	return (is_inside_tree() and not is_queued_for_deletion() and _defeat_presentation
		and is_instance_valid(battle) and not battle.is_queued_for_deletion()
		and battle.zombie_manager.allows_boss_defeat_presentation(self))

## [param battle] 用于同步暴雪风向，[param arriving] 决定是落点显形还是击败后消隐。
## [param departure_seconds] 允许正式转阶段采用更慢的退场。
func _start_snow_teleport(battle: MainGameManager, arriving: bool,
		departure_seconds: float = SnowTeleport.DEPARTURE_SECONDS) -> void:
	if is_instance_valid(_teleport):
		_teleport.begin_departure(departure_seconds)
		return
	_teleport = SnowTeleport.new()
	_teleport.configure(_visual, shadow, battle.background_manager.snow_environment, arriving, departure_seconds)
	_teleport.finished.connect(_on_teleport_finished)
	add_child(_teleport)

## 白雾入场后开始登场杖击；死亡退场则通过原有奖杯信号完成结算。
func _on_teleport_finished() -> void:
	_teleport = null
	if is_death:
		request_trophy()
		queue_free()
		return
	var battle: MainGameManager = _active_battle() # 只有当前正式战斗可以开启技能。
	if boss_phase >= 2 and _transitioning and battle != null:
		_after_phase_two_departure(battle)
		return
	if boss_phase < 2 and battle != null and not is_queued_for_deletion():
		_phase_one = PhaseOne.new(battle, perform_staff_tap, self)
		staff_impact.connect(_phase_one.resolve_impact)
		staff_finished.connect(_phase_one.finish_staff)
		add_child(_phase_one)
		_phase_one.set_action_rate(action_rate())

## 过半与死亡同时撤销待触地的技能和新的抽取。
func _stop_phase_one() -> void:
	if is_instance_valid(_phase_one):
		_phase_one.queue_free()
		_phase_one = null

## 在一阶段触地帧播放实战效果，再通知调用方。展示角色只转发信号。
func _on_staff_impact() -> void:
	if is_death or boss_phase >= 2 or is_queued_for_deletion():
		return
	_staff_hum.stop()
	var battle: MainGameManager = _active_battle() # 视听节点由本次战斗持有。
	if battle != null:
		var impact := StaffImpact.new() # 一次触地只创建一组冰光和横风。
		impact.z_index = z_index + 12
		battle.add_child(impact)
		impact.play(battle, _staff_contact.global_position)
	staff_impact.emit()

## 返回当前实战场景。展示、选卡和关卡结算阶段没有实战演出。
func _active_battle() -> MainGameManager:
	if character_init_type != E_CharacterInitType.IsNorm:
		return null
	var parent_node: Node = get_parent() # 只认角色自己的战场，防止独立展示误用当前对局。
	while parent_node != null and not parent_node is MainGameManager:
		parent_node = parent_node.get_parent()
	var battle := parent_node as MainGameManager # 胜负和重开后不能再启动入场或杖击。
	if is_instance_valid(battle) and not battle.is_queued_for_deletion() \
		and battle.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		return battle
	return null

## 一阶段杖击完整结束时通知原行动层。
func _on_staff_finished() -> void:
	if not is_death and boss_phase < 2:
		staff_finished.emit()
