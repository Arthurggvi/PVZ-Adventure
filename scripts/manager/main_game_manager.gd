extends Node2D
class_name MainGameManager

## 当前战斗唯一空间索引，在子管理器 ready 之前完成装配。
var board: BoardRuntime
## 初次展示实体分帧构造期间阻止统一遮幕提前揭开。
var _initializing_visuals := false

## 统一过渡查询首屏构造是否完成；演出时长不计入资源准备。
func is_visual_ready() -> bool:
	return not _initializing_visuals

## 正式战斗内复用的战外档案头像框。
const ProfileHud = preload("res://scripts/adventure/ui/adventure_profile_hud.gd")
## 角色主动技能共用的切入演出脚本，实战首次成功施放时才创建画布。
const CharacterSkillCutIn = preload("res://scripts/adventure/skills/character_skill_cut_in.gd")
## 手机双指手势仅绑定当前战斗，物理输入先于环境折射与 GUI 处理。
const BattleTouchInput = preload("res://scripts/battle/input/battle_touch_input.gd")
## 首次可操作战斗的技能入口教学，保存和暂停均复用既有服务。
const CharacterSkillGuide = preload("res://scripts/adventure/skills/character_skill_guide.gd")
## 两种战斗外观共用的头像框宽度，单位为 1066×600 战斗画布的逻辑像素。
const BATTLE_PROFILE_WIDTH: float = 168.0
## 两种战斗外观共用的技能方框边长，热区与可见按钮一起放大。
const BATTLE_SKILL_WIDTH: float = 42.0
## 战斗画布左侧与顶部的留白。
const BATTLE_HUD_MARGIN: float = 12.0
## 技能方框在头像下方的固定间距。
const BATTLE_SKILL_GAP: float = 5.0
## 头像框右侧与战斗卡栏之间的留白。
const BATTLE_CARD_BAR_GAP: float = 8.0

#region 游戏测试
@export_group("测试相关")
## 游戏时测试方便修改阳光数
@export var test_change_sun_value := 9999:
	set(value):
		test_change_sun_value = value
		EventBus.push_event("test_change_sun_value", [value])

## 所有僵尸死亡
@export var test_death_all_zombie:=false:
	set(value):
		print("设置值")
		EventBus.push_event("test_death_all_zombie")

## 游戏速度
## INFO: 游戏速度超过8会代码执行顺序会有问题，可能会导致一些莫名其妙的bug
@export var test_time_scale:=1:
	set(value):
		test_time_scale = value
		Engine.time_scale = test_time_scale

#endregion
#region 游戏管理器
@onready var manager: Node = %Manager
@onready var card_manager: CardManager = %CardManager
@onready var hand_manager: HandManager = %HandManager
@onready var zombie_manager: ZombieManager = %ZombieManager
## 当前战斗可显式注入位置音效接收器，普通战场继续走原音效池。
@export var world_audio: Node
## 当前战斗可为既有烟尘和碎片提供同一表现层风场。
@export var world_wind: Node
@onready var game_item_manager: GameItemManager = %GameItemManager
@onready var plant_cell_manager: PlantCellManager = %PlantCellManager
@onready var background_manager: BackgroundManager = %BackgroundManager
@onready var day_suns_manager: DaySunsManagner = %DaySunsManager
@onready var drop_item_manager: DropItemManager = %DropItemManager

#endregion

#region UI元素、相机
@onready var camera_2d: MainGameCamera = %Camera2D
@onready var ui_remind_word: UIRemindWord = %UIRemindWord
@onready var level_info: LevelInfo = $CanvasLayerUI/LevelInfo
## 正式战斗中显示当前速度，暂停期间不接收输入。
@onready var _battle_speed_button: Button = %BattleSpeedButton
## 出战卡栏就绪后，已购买手套的冒险战斗在铲子旁显示此入口。
@onready var battle_glove_button: Button = %BattleGloveButton
## 开启二倍速前的物理频率；为零时表示当前没有接管引擎速度。
var _normal_physics_ticks: int = 0
## 开启二倍速前的引擎倍率，保留场景自带调试设置。
var _normal_engine_scale: float = 1.0
## 开启二倍速前的全局倍率。
var _normal_global_scale: float = 1.0

#endregion

#region 游戏主元素
@onready var canvas_layer_temp: CanvasLayer = %CanvasLayerTemp
@onready var canvas_layer_ui: CanvasLayer = %CanvasLayerUI

## 阳光收集位置,出战卡槽时更新
var marker_2d_sun_target: Marker2D
@onready var marker_2d_sun_target_default: Marker2D = %Marker2DSunTargetDefault

## 场景内独立物件的挂载节点，包括博士释放的冰火球。
@onready var items: Node2D = %Items

## 将子弹\爆炸\阳光
@onready var bullets: Node2D = %Bullets
@onready var bombs: Node2D = %Bombs
## 本局爆炸表现的共享额度，独立于伤害和状态结算。
var blast_fx_budget := BattleBlastFxBudget.new()
@onready var suns: Node2D = %Suns

@onready var coin_bank_label: CoinBankLabel = %CoinBankLabel
## 卡槽
@onready var card_slot_root: CardSlotRoot = %CardSlotRoot
## 僵尸进家panel
@onready var panel_zombie_go_home: Panel = %PanelZombieGoHome
@onready var marker_2d_zombie_go_home: Marker2D = %Marker2DZombieGoHome

## 全局检测组件,用于检测敌人
##TODO:可能会用于检测敌人离开场景后删除
@onready var detect_component_global: DetectComponent = %DetectComponentGlobal

#endregion

#region 锤子进入节点鼠标显示
## 鼠标是否一致显示,当有锤子时
var is_mouse_visibel_on_hammer:bool = false
@onready var node_mouse_appear_have_hammer:Array[Control] = [
	## 卡槽
	%CardSlotRoot,
	## 菜单
	%MainGameMenuButton, %BattlePauseMenu, %Dialog
]

#endregion

#region bgm
@export_group("bgm")
## 选卡bgm
var bgm_choose_card: AudioStream = preload("res://assets/audio/BGM/choose_card.mp3")
## 关卡配置的原始战斗音乐，用于常规战斗及解除僵王音乐覆盖。
var bgm_main_game: AudioStream
## 存活僵王入场后覆盖原始战斗音乐的曲目，不改变关卡配置。
var bgm_boss: AudioStream
#endregion


#region 主游戏运行阶段
enum E_MainGameProgress{
	NONE,			## 无
	CHOOSE_CARD,	## 选卡界面
	PREPARE,		## 准备阶段(红字)
	MAIN_GAME,		## 游戏阶段
	GAME_OVER,		## 游戏结束阶段
	RE_CHOOSE_CARD,	## 多轮游戏重新选卡阶段
}

## 重新选卡是否暂停
var is_pause_on_re_choose_card:=false
## 正在保存、等待或重选下一轮时为 true，防止计时器与清场奖杯并发推进轮数。
var _round_transition_pending: bool = false
## 本轮已接受胜利或轮间计时请求；在发送事件或等待前置位，正式开战时重置。
var _round_end_claimed: bool = false
## 本轮实际由额外 Boss 条件结束，用于等待演出和跳过剩余自然波次。
var _round_end_by_boss: bool = false
## 冒险本局权威控制器；由主战斗场景持有，不隶属于原版波次系统。
var adventure_runtime: AdventureBattleRuntime
## 跨普通、噩梦、终末阶段唯一的角色主动技能运行时，随战场场景销毁。
var character_skill_runtime: CharacterSkillRuntime
## 仅冒险战斗显示的主动技能按钮，完全从运行时读取状态。
var character_skill_hud: CharacterSkillHud
## 本场战斗唯一的切入画布内容，普通、噩梦、终末阶段复用。
var _character_skill_cut_in: CharacterSkillCutIn
## 仅冒险模式拥有的连续阶段调度器。
var adventure_continuation: AdventureContinuationController
## 正式战斗内左上角的档案头像框；选卡、准备和结算阶段隐藏。
var battle_profile_hud
## 入场时按当前档案的有效徽章决定，并在本战场内由头像和技能按钮共用。
var _battle_hud_skin: ValhallaBattleSkin
## 当前关卡流程阶段；更新时同步通知卡槽与角色行为。
var main_game_progress := E_MainGameProgress.NONE:
	set(value):
		main_game_progress = value
		if value != E_MainGameProgress.MAIN_GAME and is_instance_valid(_character_skill_cut_in):
			_character_skill_cut_in.stop()
		_refresh_battle_profile_hud_visibility()
		_refresh_battle_tools()
		EventBus.push_event("main_game_progress_update", [value])

#endregion

#region 游戏数据
@export_group("地图特殊地形")
## 斜面(屋顶)
@export var main_game_slope:MainGameSlope
## 雪人僵尸逃跑概率(默认不使用该概率,赌狗小游戏使用)
var p_yeti_run :float= -1
#endregion

#region 游戏参数
@export_group("本局游戏参数")
## 正常进入游戏会自动更新对应关卡数据,直接进入该场景会使用该关卡数据,并设置is_test=true
@export var game_para : ResourceLevelData
## 战斗预览使用场景内的固定参数，不写关卡进度；此路径是打完或退出时的返回场景。
@export_file("*.tscn") var preview_return_scene: String = ""
## 可选的连续阶段预览，复用 AdventureSession，不建立独立难度状态。
@export var preview_stage: StageDefinition
## 可选的场景内阶段演出，供续战控制器预检并播放。
@export var phase_presentation: AdventurePhasePresentation
## 可选的奖杯画布，可配置在环境合成层上方。未配置时沿用临时物件层。
@export var trophy_layer: CanvasLayer
## 若为true,选卡无冷却
var is_test := false
## 当前轮次
var curr_game_round = 1:
	set(value):
		curr_game_round = value
		level_info.set_round(curr_game_round)

## 初始化时是否存档
var is_save_game_data_on_init:=false

#endregion

#endregion
func _enter_tree() -> void:
	set_game_para()
	if game_para != null and not is_queued_for_deletion():
		board = BoardSceneAdapter.install(self)

## 进入树时更新游戏参数，子管理器赋值对应的游戏参数
func set_game_para() -> void:
	Global.main_game = self
	if not preview_return_scene.is_empty():
		# 预览独占参数副本，重开时从场景配置重新开始。
		if game_para != null:
			game_para = game_para.duplicate() as ResourceLevelData
		Global.game_para = game_para
		if preview_stage != null:
			AdventureSession.prepare_stage_preview(game_para, preview_stage)
	elif Global.game_para != null:
		game_para = Global.game_para
	else:
		is_test = true
	if game_para == null:
		push_error(
			"主游戏缺少关卡数据 ResourceLevelData：请从选关流程进入，或在编辑器中为该主游戏场景根节点指定「本局游戏参数 / game_para」。"
		)
		queue_free()
		return

func _exit_tree() -> void:
	## 避免切场景后主游戏节点已释放，Global 仍持有野指针
	if Global.main_game == self:
		_reset_battle_speed()
		if not preview_return_scene.is_empty() and Global.game_para == game_para:
			AdventureSession.release_stage_preview(game_para)
			Global.game_para = null
		Global.main_game = null

func _ready() -> void:
	if board == null or not board.configured:
		push_error("战场空间初始化失败，未启动战斗。")
		return
	# 参数资源负责校验与初始化；失败时保持 NONE 阶段，不继续选卡或初始化子管理器。
	if not game_para.init_para():
		return
	BoardSceneAdapter.align_legacy_water_lanes(self)
	# 原版初始化仅保留随机白名单里的预览物种；冒险在这一层恢复完整阶段敌人池。
	# Legacy 不走该分支，仍使用其原有筛选和刷怪规则。
	if AdventureSession.owns_battle(game_para):
		game_para.zombie_refresh_types = AdventureBattleEnvironmentAdapter.preview_zombies(
			AdventureSession.get_active_phase(game_para))
	## 多轮游戏并且有存档
	is_save_game_data_on_init = game_para.game_round != 1 and game_para.save_game_data_main_game != null

	if is_save_game_data_on_init:
		var saved: ResourceSaveGamePlantCellManager = game_para.save_game_data_main_game.plant_cell_manager_data # 空间快照预检。
		if not plant_cell_manager.accepts_save(saved):
			push_error("存档布局不兼容，未恢复任何战斗状态。")
			return
	## 订阅总线事件
	event_bus_subscribe()
	## 默认禁用全局敌人检测组件(追踪子弹调用, 放置追踪植物时启用,追踪植物死亡时,检测是否关闭)
	detect_component_global.disable_component(ComponentNormBase.E_IsEnableFactor.Global)
	## 正式战斗 HUD：复用战外头像框，选卡阶段不显示。
	_setup_battle_profile_hud()
	## 主游戏进程
	main_game_progress = E_MainGameProgress.CHOOSE_CARD
	## 播放选卡bgm
	SoundManager.play_bgm(bgm_choose_card)
	## 连接子节点信号
	signal_connect()
	## 初始化子管理器
	_initializing_visuals = true
	await init_manager()
	if not is_inside_tree():
		return
	coin_bank_label.visible = false
	## 初始化游戏背景音乐
	_init_game_BGM()

	## 若有存档
	if is_save_game_data_on_init:
		if not load_game_main_game():
			_initializing_visuals = false
			return
		# 存档表示上一轮已经结束，选卡阶段直接恢复过渡，不重新判胜。
		_advance_to_next_round()
		_initializing_visuals = false
	else:

		## 如果有戴夫对话
		if game_para.crazy_dave_dialog:
			_initializing_visuals = false # 对话需要揭幕后才能交互，不等待玩家操作。
			var crazy_dave:CrazyDave = SceneRegistry.CRAZY_DAVE.instantiate()
			crazy_dave.init_dave(game_para.crazy_dave_dialog)
			canvas_layer_ui.add_child(crazy_dave)
			await crazy_dave.signal_dave_leave_end
			crazy_dave.queue_free()

		## 如果看展示僵尸
		if game_para.look_show_zombie:
			## 创建展示僵尸，等待一秒移动相机
			await zombie_manager.create_prepare_show_zombies()
			if not is_inside_tree():
				return
			_initializing_visuals = false
			await get_tree().create_timer(1.0).timeout
			await camera_2d.move_look_zombie()
			## 如果可以选卡
			if game_para.can_choosed_card:
				card_manager.card_slot_appear_choose()
			else:
				await get_tree().create_timer(1.0).timeout
				no_choosed_card_start_game()
		else:
			_initializing_visuals = false
			main_game_start()

## 为正式冒险战斗建立唯一主动技能控制器与表现层；无技能时 HUD 自动隐藏。
func _setup_character_skill_runtime() -> void:
	character_skill_runtime = CharacterSkillRuntime.new() # 不挂载在会被续战销毁的阶段运行时下。
	character_skill_runtime.setup(self)
	add_child(character_skill_runtime)
	character_skill_runtime.cast_committed.connect(_play_character_skill_cut_in)
	character_skill_hud = CharacterSkillHud.new() # 只订阅同一个运行时，输入和触摸共用施放入口。
	character_skill_hud.setup(character_skill_runtime, _battle_hud_skin)
	canvas_layer_ui.add_child(character_skill_hud)
	character_skill_hud.bind_avatar(battle_profile_hud.avatar_control())
	var pointer_idle: Callable # 手机额外等副指与残留释放结束，桌面直接使用引擎输入状态。
	if OS.has_feature("mobile"):
		var touch_input: Node = BattleTouchInput.new() # 与技能运行时共同跨阶段存活，不登记为Autoload。
		touch_input.setup(character_skill_runtime.is_input_enabled, character_skill_runtime.try_activate)
		add_child(touch_input)
		pointer_idle = touch_input.is_pointer_idle
	var skill_guide: CanvasLayer = CharacterSkillGuide.new() # 自行等待真正可操作时机，不阻塞选卡和开场动画。
	skill_guide.setup(self, character_skill_runtime, battle_profile_hud.avatar_control(), pointer_idle)
	add_child(skill_guide)
	# 界面重排时仍固定两种样式的尺寸，并让技能按钮跟随头像框下缘。
	battle_profile_hud.item_rect_changed.connect(_layout_character_skill_hud)
	_layout_character_skill_hud()

## 在 [param skill_id] 提交且战局仍可操作时播放，所有冒险战场复用此入口。
func _play_character_skill_cut_in(skill_id: StringName) -> void:
	if %BattlePauseMenu.visible or not CharacterSkillContext.new(self, skill_id).is_active():
		return
	if not is_instance_valid(_character_skill_cut_in):
		var overlay := CanvasLayer.new() # 独立于摄像机和关卡灯光，仍随本场景离树。
		overlay.name = "CharacterSkillCutInLayer"
		overlay.layer = CharacterSkillCutIn.CANVAS_LAYER
		add_child(overlay)
		_character_skill_cut_in = CharacterSkillCutIn.new()
		_character_skill_cut_in.theme = battle_profile_hud.theme
		overlay.add_child(_character_skill_cut_in)
		# 菜单允许在少数 Boss 阶段开启而不暂停，此时也需要立即让出屏幕。
		%BattlePauseMenu.visibility_changed.connect(_character_skill_cut_in.stop)
	_character_skill_cut_in.play(character_skill_runtime.definition())

## 将技能按钮固定在头像下方，两种皮肤具有同一画布尺寸。
func _layout_character_skill_hud() -> void:
	if not is_instance_valid(character_skill_hud) or not is_instance_valid(battle_profile_hud):
		return
	var portrait: Control = battle_profile_hud as Control # 技能位置跟随档案框的画布外沿。
	character_skill_hud.scale = Vector2.ONE * (BATTLE_SKILL_WIDTH / character_skill_hud.size.x)
	character_skill_hud.position = portrait.position + Vector2(0.0, portrait.size.y * portrait.scale.y + BATTLE_SKILL_GAP)

## 按当前档案的有效徽章选择战斗头像框，共用加大的左上战斗布局。
func _setup_battle_profile_hud() -> void:
	battle_profile_hud = ProfileHud.new()
	battle_profile_hud.name = "BattleProfileHud"
	if Global.save_service.is_current_profile_loaded():
		_battle_hud_skin = ValhallaBattleSkin.for_equipment(Global.global_game_state.adventure_state.equipment)
	battle_profile_hud.configure_battle_layout(BATTLE_PROFILE_WIDTH, BATTLE_HUD_MARGIN, _battle_hud_skin)
	var all_ui := canvas_layer_ui.get_node_or_null("All_UI") as Control # 沿用战斗主题作为中文和缺字回退。
	if all_ui != null:
		battle_profile_hud.theme = all_ui.theme # 复用战斗 UI 的中文字体。
	canvas_layer_ui.add_child(battle_profile_hud)
	canvas_layer_ui.move_child(battle_profile_hud, 0) # 位于菜单、对话和红字提示之后。
	card_slot_root.configure_battle_layout(BATTLE_HUD_MARGIN + BATTLE_PROFILE_WIDTH + BATTLE_CARD_BAR_GAP, _battle_speed_button)
	battle_profile_hud.visible = false

## 只在正式战斗阶段显示头像，并为它腾出卡栏左侧空间。
func _refresh_battle_profile_hud_visibility() -> void:
	if is_instance_valid(battle_profile_hud):
		var in_combat: bool = main_game_progress == E_MainGameProgress.MAIN_GAME # 选卡和准备沿用原来的卡栏起点。
		card_slot_root.use_combat_layout(in_combat)
		battle_profile_hud.visible = in_combat

## 仅当前档案已购买时，允许在其冒险战斗内使用手套。
func has_battle_glove() -> bool:
	if not AdventureSession.owns_battle(game_para) or Global.global_game_state == null:
		return false
	var state: AdventureState = Global.global_game_state.adventure_state # 解锁状态属于当前玩家档案。
	return state != null and state.shop != null and state.shop.glove_unlocked

## 选卡、结算和轮间过渡隐藏战斗工具，并结束本轮的临时操作。
func _refresh_battle_tools() -> void:
	if not is_instance_valid(_battle_speed_button):
		return
	var in_combat: bool = main_game_progress == E_MainGameProgress.MAIN_GAME # 准备红字结束后才开放操作。
	_battle_speed_button.visible = in_combat
	if not in_combat:
		battle_glove_button.hide()
		hand_manager.cancel_glove()
		_reset_battle_speed()

## 在 GUI 拦截鼠标之前将侧键 [param event] 分发给战斗快捷键，弹窗打开时交由界面处理。
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not ConfigService.is_tool_shortcut_mouse_button(event.button_index) \
			or not event.is_pressed() or get_tree().current_scene != self \
			or main_game_progress != E_MainGameProgress.MAIN_GAME or get_tree().paused or PVZCheat.is_open():
		return
	if %Dialog.is_visible_in_tree() or %BattlePauseMenu.is_visible_in_tree():
		return
	if card_slot_root.handle_tool_shortcut(event):
		return
	if is_instance_valid(character_skill_hud) and character_skill_hud.handle_skill_shortcut(event):
		return
	_handle_battle_speed_shortcut(event)

## 将界面未消耗的键盘事件 [param event] 交给倍速快捷键处理。
func _unhandled_key_input(event: InputEvent) -> void:
	_handle_battle_speed_shortcut(event)

## 在战斗接受 [param event] 触发的倍速切换时消费该输入。
func _handle_battle_speed_shortcut(event: InputEvent) -> void:
	if event.is_action_pressed(ConfigService.BATTLE_SPEED_ACTION, false, true) \
			and not PVZCheat.is_open() and _toggle_battle_speed():
		get_viewport().set_input_as_handled()

## 切换本轮战斗速度并返回是否切换成功；开启二倍速时同步提高物理频率以保持命中检测精度。
func _toggle_battle_speed() -> bool:
	if main_game_progress != E_MainGameProgress.MAIN_GAME or get_tree().paused \
			or get_tree().current_scene != self:
		_battle_speed_button.set_pressed_no_signal(_normal_physics_ticks > 0)
		return false
	SoundManager.play_other_SFX(&"tap")
	if _normal_physics_ticks > 0:
		_reset_battle_speed()
		return true
	_normal_physics_ticks = Engine.physics_ticks_per_second
	_normal_engine_scale = Engine.time_scale
	_normal_global_scale = Global.time_scale
	Engine.physics_ticks_per_second = _normal_physics_ticks * 2
	Engine.time_scale = 2.0
	Global.time_scale = 2.0
	_battle_speed_button.text = "2×"
	_battle_speed_button.set_pressed_no_signal(true)
	return true

## 回收本轮倍率，保留退出或重开流程已主动恢复的速度。
func _reset_battle_speed() -> void:
	if _normal_physics_ticks == 0:
		return
	Engine.physics_ticks_per_second = _normal_physics_ticks
	_normal_physics_ticks = 0
	if Engine.time_scale == 2.0:
		Engine.time_scale = _normal_engine_scale
	if Global.time_scale == 2.0:
		Global.time_scale = _normal_global_scale
	if is_instance_valid(_battle_speed_button):
		_battle_speed_button.text = "1×"
		_battle_speed_button.set_pressed_no_signal(false)

## 主游戏管理器事件总线订阅
func event_bus_subscribe():
	## 手持锤子时，修改鼠标离开ui是否显示鼠标
	EventBus.subscribe("change_is_mouse_visibel_on_hammer", change_is_mouse_visibel_on_hammer)
	## 僵尸进家
	EventBus.subscribe("zombie_go_home", on_zombie_go_home)
	## 创建奖杯
	EventBus.subscribe("create_trophy", create_trophy)
	## 游戏胜利
	EventBus.subscribe("win_main_game", win_main_game)
	## 正常选卡结束后开始游戏
	EventBus.subscribe("card_slot_norm_start_game", choosed_card_start_game)
	## 多轮游戏触发下一轮游戏
	EventBus.subscribe("start_next_round_game", start_next_round_game)
	## 更新阳光收集位置
	EventBus.subscribe("update_marker_2d_sun_target", update_marker_2d_sun_target)


## 更新阳光收集位置
func update_marker_2d_sun_target(new_marker_2d_sun_target:Marker2D):
	marker_2d_sun_target = new_marker_2d_sun_target

#region 游戏关卡初始化
## 初始化管理器；等待选卡候选分帧构造完成后再启动依赖卡槽的子管理器。
func init_manager():
	await card_manager.init_manager()
	if not is_inside_tree():
		return
	plant_cell_manager.init_manager()
	game_item_manager.init_manager()
	hand_manager.init_manager()
	zombie_manager.init_manager()
	if AdventureSession.owns_battle(game_para):
		var phase: StagePhaseDefinition = AdventureSession.get_active_phase(game_para)
		if phase != null:
			adventure_runtime = AdventureBattleRuntime.new()
			adventure_runtime.setup(zombie_manager.zombie_wave_manager, zombie_manager, phase)
			add_child(adventure_runtime)
			adventure_continuation = AdventureContinuationController.new()
			adventure_continuation.setup(self)
			add_child(adventure_continuation)
			_setup_character_skill_runtime() # 与阶段事件平级持有，阶段交接不得释放冷却。
	background_manager.init_manager()
	drop_item_manager.init_manager()
	day_suns_manager.init_manager()
	print("info:管理器初始化完成")

## 信号连接
func signal_connect():
	zombie_manager.signal_living_bosses_changed.connect(refresh_battle_bgm)
	if game_para.is_hammer:
		for ui_node:Control in node_mouse_appear_have_hammer:
			ui_node.mouse_entered.connect(mouse_appear_have_hammer)
			ui_node.mouse_exited.connect(mouse_disappear_have_hammer)

## 加载关卡配置的普通与 Boss 音乐；已配专属曲目时不额外加载原版音乐。
func _init_game_BGM():
	var music: BattleMusicProfile = game_para.battle_music_profile # 只随本关卡加载的可选曲目组合。
	bgm_main_game = music.normal_music if music != null else null
	bgm_boss = music.boss_music if music != null else null
	if bgm_main_game == null:
		bgm_main_game = load(ConstLevelData.GameBGMMap[game_para.game_BGM]) as AudioStream
	if bgm_boss == null:
		bgm_boss = load(ConstLevelData.GameBGMMap[ConstLevelData.GameBGM.Boss]) as AudioStream


## 正式战斗时按当前阶段和存活僵王选择音乐；僵王离场后恢复本阶段曲目。
## 所有存活僵王都在等待入场音乐提示时，先停掉当前曲目，音效继续播放。
## 单轮僵王死亡获胜先进入结算，因此保留僵王音乐，不在结算阶段恢复原曲。
## 相同曲目继续播放，选卡、结算或场景卸载时不覆盖其他界面的音乐。
func refresh_battle_bgm() -> void:
	if not is_inside_tree() or is_queued_for_deletion() \
		or get_tree().current_scene != self or main_game_progress != E_MainGameProgress.MAIN_GAME:
		return
	var living_bosses: Array[ZB000Base] = zombie_manager.get_living_bosses() # 死亡演出中的僵王不进入存活快照。
	var has_boss: bool = not living_bosses.is_empty() # 决定读取当前阶段的战斗曲还是 Boss 曲。
	if has_boss and not living_bosses.any(func(boss: ZB000Base) -> bool: return boss.is_boss_music_ready()):
		SoundManager.bgm_play.stop()
		return
	var battle_bgm: AudioStream = bgm_boss if has_boss else bgm_main_game # 原版及未配置阶段曲目时的默认音乐。
	var phase: StagePhaseDefinition = AdventureSession.get_active_phase(game_para) # 续战和重开均读取会话的当前阶段。
	if game_para.battle_music_profile != null:
		var kind: StagePhaseDefinition.Kind = phase.kind if phase != null else StagePhaseDefinition.Kind.NORMAL # 阶段身份统一读取 Session。
		var profile_music: AudioStream = game_para.battle_music_profile.resolve(kind, has_boss) # Boss 退场时按实际阶段恢复。
		if profile_music != null:
			battle_bgm = profile_music
	if phase != null:
		var phase_music: AudioStream = phase.boss_music if has_boss else phase.battle_music # 当前战况对应的阶段曲目。
		if phase_music != null:
			battle_bgm = phase_music
	SoundManager.play_bgm_if_changed(battle_bgm)


## 不用选择卡片进行的流程
func no_choosed_card_start_game():
	await get_tree().create_timer(2.0).timeout
	## 相机移动回游戏场景
	await camera_2d.move_back_ori()
	main_game_start()
#endregion

#region 多轮游戏下一轮
## 末波计时器请求进入下一轮；末轮不占用结算状态，也不通过计时器创建奖杯。
func start_next_round_game() -> void:
	if curr_game_round == game_para.game_round:
		return
	if not try_claim_round_end():
		return
	_advance_to_next_round()


## 执行已确认的轮间过渡，也供选卡阶段恢复轮末存档；正式开战后解除过渡锁定。
func _advance_to_next_round() -> void:
	## 多轮游戏僵尸管理器计时器触发时，判断是否为最后一轮
	if curr_game_round == game_para.game_round or _round_transition_pending \
		or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false):
		return
	_round_transition_pending = true
	print("-----------------开始下一轮游戏---------------")
	print("下一轮次：", curr_game_round + 1)
	## 等待3秒后进行下一轮
	await get_tree().create_timer(3).timeout
	# 轮间等待仍允许进房失败；旧协程不能继续推进轮数或重新写入已删除的存档。
	if not is_inside_tree() or is_queued_for_deletion() \
		or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false):
		return
	# 暂停选卡与清场前保存，将等待期间成功召唤的僵王和血量变化一并纳入快照。
	save_game_main_game()
	## 播放选卡bgm
	if game_para.look_show_zombie:
		## 重新选卡阶段暂停游戏
		start_pause_on_re_choose_card_progress()
		print("----------------播放选卡bgm", bgm_choose_card)
		SoundManager.play_bgm(bgm_choose_card)
	curr_game_round += 1
	main_game_progress = E_MainGameProgress.RE_CHOOSE_CARD
	## 暂停天降阳光
	if game_para.is_day_sun:
		day_suns_manager.pause_day_sun()
	## 更新卡槽数据
	card_manager.start_next_game_card_manager_update()
	## 更新背景,浓雾回退
	background_manager.start_next_game_background_manager_update()
	coin_bank_label.visible = false
	## 更新僵尸管理器
	zombie_manager.start_next_game_zombie_mananger_update(_round_end_by_boss)
	## 更新植物格子数据，（创建罐子） 清除植物数据需要等待两帧
	await plant_cell_manager.start_next_game_plant_cell_manager_update()
	game_item_manager.start_next_game_game_item_manager_update()

	## 如果看展示僵尸
	if game_para.look_show_zombie:
		## 创建展示僵尸，等待一秒移动相机
		await zombie_manager.create_prepare_show_zombies()
		if not is_inside_tree():
			return
		await get_tree().create_timer(1.0).timeout
		await camera_2d.move_look_zombie()
		## 如果可以选卡
		if game_para.can_choosed_card:
			card_manager.card_slot_appear_choose()
		else:
			await get_tree().create_timer(1.0).timeout
			no_choosed_card_start_game()
	else:
		main_game_start()


## 下轮选卡时暂停游戏
func start_pause_on_re_choose_card_progress():
	is_pause_on_re_choose_card = true
	## 设置相机可以移动
	camera_2d.process_mode = Node.PROCESS_MODE_ALWAYS
	card_slot_root.process_mode = Node.PROCESS_MODE_ALWAYS
	TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.ReChooseCard)

## 下轮选卡结束时取消暂停游戏
func end_pause_on_re_choose_card_progress():
	is_pause_on_re_choose_card = false
	## 设置相机可以移动
	camera_2d.process_mode = Node.PROCESS_MODE_INHERIT
	card_slot_root.process_mode = Node.PROCESS_MODE_INHERIT
	TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.ReChooseCard)

#endregion

## 选择卡片完成
func choosed_card_start_game():
	print("选卡完成")
	## 主游戏进程阶段
	main_game_progress = E_MainGameProgress.PREPARE
	## 隐藏待选卡槽
	await card_manager.card_slot_disappear_choose()
	## 相机移动回游戏场景
	await camera_2d.move_back_ori()
	main_game_start()

## 选卡结束，恢复主游戏；浓雾自行决定继续三叶草等待或正常入场。
func main_game_start():
	if is_pause_on_re_choose_card:
		end_pause_on_re_choose_card_progress()
	print("主游戏开始")
	## 主游戏进程阶段
	main_game_progress = E_MainGameProgress.PREPARE
	if game_para.is_fog:
		background_manager.fog.start_round()

	## 删除展示僵尸
	if game_para.look_show_zombie:
		zombie_manager.delete_prepare_show_zombies()

	## 开始天降阳光
	if game_para.is_day_sun:
		day_suns_manager.start_day_sun()
	print("生成墓碑", game_para.init_tombstone_num)
	## 生成墓碑
	if game_para.init_tombstone_num > 0:
		plant_cell_manager.create_tombstone(game_para.init_tombstone_num)

	## 等待1秒红字出现
	await get_tree().create_timer(1.0).timeout
	await ui_remind_word.ready_set_plant()
	# 先清除上一轮结算记录，再通知战斗阶段，避免同步事件看到旧轮锁定。
	_round_end_claimed = false
	_round_end_by_boss = false
	_round_transition_pending = false
	main_game_progress = E_MainGameProgress.MAIN_GAME
	if is_instance_valid(character_skill_runtime):
		character_skill_runtime.bind_skill(AdventureSession.character_skill_id_for(game_para)) # 单局只绑定一次，阶段交接保持冷却。
	# 僵王只有在正式战斗阶段才能恢复；先恢复实例与血量，再启用出战卡片。
	zombie_manager.restore_saved_bosses()
	card_manager.card_slot_update_main_game()

	# 初代节奏从可种植时起算首波保护，音乐延迟不计入保护时间。
	var classic_spawn_timing: bool = zombie_manager.zombie_wave_manager.uses_classic_spawn_timing()
	if classic_spawn_timing:
		zombie_manager.start_game()

	# 本次延迟所属轮次，防止旧轮协程重新播放音乐或启动下一轮刷怪。
	var start_round: int = curr_game_round
	# 红字结束后一秒按当前存活僵王选择音乐，不能覆盖读档或卡牌入场已切换的僵王曲目。
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree() or is_queued_for_deletion() or get_tree().current_scene != self \
		or main_game_progress != E_MainGameProgress.MAIN_GAME or curr_game_round != start_round:
		return
	refresh_battle_bgm()

	if not classic_spawn_timing:
		zombie_manager.start_game()


#region 游戏结束
## 修改僵尸位置
func change_zombie_position(zombie:Zombie000Base):
	## 要删除碰撞器，不然会闪退(这里好像是因为暂停的时候会重复循环执行一些代码，不清楚为什么)
	zombie.hurt_box_component.free()
	zombie.get_parent().remove_child(zombie)
	panel_zombie_go_home.add_child(zombie)
	zombie.position = marker_2d_zombie_go_home.position
	if game_para.game_BG == ConstLevelData.GameBg.Roof:
		roof_zombie_go_home(zombie)


func roof_zombie_go_home(zombie:Zombie000Base):
	print("禁用僵尸移动组件")
	zombie.move_component.disable_component(ComponentNormBase.E_IsEnableFactor.GameMode)
	await get_tree().create_timer(3).timeout
	var tween = zombie.create_tween()
	tween.tween_property(zombie, "position:y", 300, 10.0).as_relative()



## 僵尸进房
func on_zombie_go_home(zombie:Zombie000Base):
	re_main_game()

	main_game_progress = E_MainGameProgress.GAME_OVER
	card_slot_root.visible = false
	if AdventureSession.owns_battle(game_para):
		AdventureSession.battle_failed = true

	## 设置相机可以移动
	camera_2d.process_mode = Node.PROCESS_MODE_ALWAYS
	## 游戏暂停
	TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.GameOver)
	call_deferred("change_zombie_position", zombie)
	## 如果有锤子
	if game_para.is_hammer:
		game_item_manager.gim_other.hammer.set_is_used(false)
	await get_tree().create_timer(1).timeout

	camera_2d.move_to(Vector2(-200, 0), 2)
	SoundManager.play_other_SFX("losemusic")
	await get_tree().create_timer(3).timeout
	SoundManager.play_other_SFX("scream")
	ui_remind_word.zombie_won_word_appear()
	# 失败演出结束后回本局来源地图。
	if AdventureSession.owns_battle(game_para) or not preview_return_scene.is_empty():
		await get_tree().create_timer(1.5).timeout
		if is_inside_tree() and get_tree().current_scene == self:
			if not preview_return_scene.is_empty():
				leave_battle_preview()
			else:
				AdventureSession.finish_defeat()


#region 奖杯
## 接受本轮第一次结束请求，成功返回 true；只在正式战斗且未失败、未过渡时接受。
## [param is_boss_win] 表示实际由额外 Boss 条件结束，不表示关卡是否启用了该选项。
func try_claim_round_end(is_boss_win: bool = false) -> bool:
	return _claim_round_end(is_boss_win, false)

## [param is_boss_win] 记录胜利来源；仅修改器入口可用 [param skip_combat_checks] 跳过清场检查。
func _claim_round_end(is_boss_win: bool, skip_combat_checks: bool) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() \
		or main_game_progress != E_MainGameProgress.MAIN_GAME \
		or _round_end_claimed or _round_transition_pending \
		or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false):
		return false
	if not is_boss_win and not skip_combat_checks and is_instance_valid(zombie_manager) \
			and zombie_manager.has_pending_boss_defeat_presentation():
		return false
	if not skip_combat_checks and AdventureSession.owns_battle(game_para) and not AdventureSession.can_accept_victory():
		return false
	_round_end_claimed = true
	_round_end_by_boss = is_boss_win
	return true


## 只在修改器打开时接受一键通关，仍占用本局唯一的胜利结算入口。
func request_cheat_victory() -> bool:
	if not PVZCheat.is_open() or not _claim_round_end(false, true):
		return false
	main_game_progress = E_MainGameProgress.GAME_OVER
	zombie_manager.zombie_wave_manager.stop_wave_refresh()
	if AdventureSession.owns_battle(game_para):
		# 结算写盘失败时保留现有重试入口，等待期间停止战场动作。
		TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
		_settle_cheat_adventure_victory()
	else:
		SoundManager.play_other_SFX(&"winmusic")
		win_main_game()
	return true


## 结束当前冒险阶段；正式奖励保存成功后直接返回地图。
func _settle_cheat_adventure_victory() -> void:
	if not is_inside_tree() or get_tree().current_scene != self or not AdventureSession.owns_battle(game_para):
		return
	if not AdventureSession.settle_victory(true):
		AdventureSession.prompt_victory_retry(_settle_cheat_adventure_victory)
		return
	if AdventureSession.challenge_state in [AdventureSession.ChallengeState.NORMAL_COMPLETE, AdventureSession.ChallengeState.NIGHTMARE_COMPLETE]:
		AdventureSession.complete_checkpoint_challenge()
	# 同一战场从普通续战时，先前已生成的钱堆也须在一键通关离场前结清。
	drop_item_manager.finish_victory_collection()
	SoundManager.play_other_SFX(&"winmusic")
	AdventureSession.finish_victory()


## 普通胜利请求共用一次性结算入口；[param glo_pos] 为奖杯生成的世界坐标。
## 清场、罐子和脑子条件始终有效，与额外 Boss 胜利选项独立。
## 事件结束战斗统一走本局唯一的胜负判定与结算链，不得绕过奖励事务。
func request_adventure_event_result(result: int) -> void:
	if not AdventureSession.owns_battle(game_para) or main_game_progress != E_MainGameProgress.MAIN_GAME:
		return
	if result == StageEventDefinition.BattleResult.DEFEAT:
		main_game_progress = E_MainGameProgress.GAME_OVER
		zombie_manager.zombie_wave_manager.stop_wave_refresh()
		AdventureSession.finish_defeat()

func create_trophy(glo_pos: Vector2) -> void:
	if is_instance_valid(zombie_manager) and zombie_manager.defer_trophy_for_boss_defeat_presentation(glo_pos):
		return
	if not try_claim_round_end():
		return
	# 普通和带终末入口的噩梦先结算，再决定是否继续同一战场。
	if AdventureSession.owns_battle(game_para) and (AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NORMAL \
			or (AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE \
				and (not AdventureSession.active_stage.terminal_key_id.is_empty() or AdventureSession.is_stage_preview))):
		adventure_continuation.complete_checkpoint(glo_pos)
	else:
		_finish_round_victory(glo_pos)


## [param glo_pos] 为最后一只 Boss 请求的奖杯世界坐标；完成已接受的 Boss 胜利。
## 动画和直接消失由僵王管理器保证只请求一次，此处不重新接受胜利条件。
func complete_boss_victory(glo_pos: Vector2) -> void:
	if not is_inside_tree() or is_queued_for_deletion() \
		or not _round_end_claimed or not _round_end_by_boss or _round_transition_pending \
		or main_game_progress != E_MainGameProgress.GAME_OVER \
		or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false):
		return
	_finish_round_victory(glo_pos)


## 完成已接受的胜利，非末轮直接过渡，末轮生成奖杯；[param glo_pos] 为世界坐标。
func _finish_round_victory(glo_pos: Vector2) -> void:
	print("胜利条件达成，创建奖杯")
	## 如果不是最后一轮游戏，触发下一轮
	if curr_game_round != game_para.game_round:
		_advance_to_next_round()
		return


	print("=======================游戏结束，您获胜了=======================")
	var is_adventure: bool = AdventureSession.owns_battle(game_para) # 冒险需要先保存奖励，再播放结算演出。
	if is_adventure and not AdventureSession.settle_victory():
		main_game_progress = E_MainGameProgress.GAME_OVER
		zombie_manager.zombie_wave_manager.stop_wave_refresh()
		AdventureSession.prompt_victory_retry(_finish_round_victory.bind(glo_pos))
		return
	main_game_progress = E_MainGameProgress.GAME_OVER
	if is_adventure:
		# 续战检查点已演出本阶段的钱币，其余阶段在奖杯入场前演出。
		if not AdventureSession.is_stage_preview and (AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.TERMINAL \
				or (AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE \
					and AdventureSession.active_stage.terminal_key_id.is_empty())):
			var presentation: Tween = drop_item_manager.spawn_first_clear_coins(AdventureSession.active_phase) # 首通钱币落稳后再生成奖杯。
			if presentation != null:
				# 终末允许带着剩余援军结算，演出期间停住战场。
				TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
				await presentation.finished
				TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
				if not is_inside_tree() or is_queued_for_deletion():
					return
		drop_item_manager.spawn_victory_floor_items(AdventureSession.take_victory_floor_items(), glo_pos)
	var trophy := SceneRegistry.TROPHY.instantiate() as Node2D # 本轮唯一奖杯，由已接受的胜利请求创建。
	# 场景指定常亮画布时优先使用，位置仍按战场坐标设置。
	var trophy_parent: CanvasLayer = trophy_layer if is_instance_valid(trophy_layer) else canvas_layer_temp
	trophy_parent.add_child(trophy)
	trophy.global_position = glo_pos
	if trophy.global_position.x >= 750:
		# 右侧奖杯向场内抛出的水平偏移。
		var x_diff = trophy.global_position.x - 700
		throw_to(trophy, trophy.position - Vector2(x_diff + randf_range(-50,50), 0))
	elif trophy.global_position.x <= 50:
		# 左侧奖杯向场内抛出的水平偏移。
		var x_diff = trophy.global_position.x - 100
		throw_to(trophy, trophy.position - Vector2(x_diff + randf_range(-50,50), 0))

	else:
		throw_to(trophy, trophy.position - Vector2(randf_range(-50,50), 0))

## 奖杯抛出
func throw_to(node:Node2D, target_pos: Vector2, duration: float = 1.0):
	var start_pos = node.position
	var peak_pos = start_pos.lerp(target_pos, 0.5)
	peak_pos.y -= 50  # 向上抛

	var tween = create_tween()
	tween.tween_property(node, "position:x", target_pos.x, duration).set_trans(Tween.TRANS_LINEAR)

	tween.parallel().tween_property(node, "position:y", peak_pos.y, duration / 2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "position:y", target_pos.y, duration / 2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(duration / 2)

#endregion


## 当前关卡完成；奖杯点击的延迟回调在失败后到达时不能再登记通关。
func win_main_game():
	# 奖杯按钮等待期间仍可能进房失败，必须在清除暂停因素前拒绝晚到回调。
	if TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false):
		return
	if not preview_return_scene.is_empty():
		leave_battle_preview()
		return
	# 冒险只接受本战斗已判定的末轮奖杯结算，绕开原版关卡存档。
	if AdventureSession.owns_battle(game_para):
		if _round_end_claimed and main_game_progress == E_MainGameProgress.GAME_OVER \
			and curr_game_round == game_para.game_round:
			AdventureSession.finish_victory()
		return

	## 游戏暂停因素、游戏速度
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = Global.time_scale

	update_level_state_data_success()
	## 多轮游戏，重置主游戏数据
	if game_para.game_round != 1:
		re_main_game()
	get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap.get(game_para.game_mode, Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu]))

## [param restart] 为 true 时重新进入同一预览，默认返回地图。
## 统一切场接受目标后才释放暂停，加载失败时当前预览仍可操作。
func leave_battle_preview(restart: bool = false) -> void:
	var target: String = scene_file_path if restart else preview_return_scene # 本次切换的预览或地图。
	if not $SceneTransition.change_scene(target, TreePauseManager.end_tree_pause_clear_all_pause_factors):
		push_warning("预览场景切换请求未被接受：" + target)

#endregion


#region 锤子鼠标交互
## 锤子鼠标进入后，显示鼠标
func mouse_appear_have_hammer():
	if main_game_progress == E_MainGameProgress.MAIN_GAME:
		## 如果有锤子
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## 有锤子时连接该信号
func mouse_disappear_have_hammer():
	## 如果有锤子不显示鼠标（非重新开始、离开游戏）
	if not is_mouse_visibel_on_hammer and main_game_progress == E_MainGameProgress.MAIN_GAME:
		## 如果有锤子
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

## 点击重新开始或主菜单时，修改值，可以一直显示鼠标
func change_is_mouse_visibel_on_hammer(value:bool):
	if game_para.is_hammer:
		is_mouse_visibel_on_hammer = value

#endregion

#region 存档
## 读档系统只能从空白场景读档

## 保存轮末快照；实际由 Boss 提前结束的自然波次按已完成本轮保存，续关不补旧波。
func save_game_main_game():
	# 本轮结束后的快照，加载时直接进入下一轮。
	var save_game_data_main_game:ResourceSaveGameMainGame = ResourceSaveGameMainGame.new()
	save_game_data_main_game.curr_game_round = curr_game_round
	## 植物数据
	save_game_data_main_game.plant_cell_manager_data = plant_cell_manager.get_save_game_data_plant_cell_manager()
	## 僵尸, gema_para 自动更新该值
	save_game_data_main_game.curr_max_wave = zombie_manager.zombie_wave_manager.max_wave
	save_game_data_main_game.curr_wave = zombie_manager.zombie_wave_manager.curr_wave
	if _round_end_by_boss and game_para.monster_mode == ConstLevelData.E_MonsterMode.Norm:
		# 只标准化实际 Boss 胜利的快照，不依据配置或死亡统计推断结束原因。
		save_game_data_main_game.curr_wave = save_game_data_main_game.curr_max_wave - 1
	## 天降阳光
	save_game_data_main_game.day_sun_curr_sun_sum_value = day_suns_manager.curr_sun_sum_value
	## 植物卡槽数据
	save_game_data_main_game.card_manager_data = card_manager.get_save_game_data_card_manager()
	## 小推车数据
	save_game_data_main_game.lawn_mover_manager_data = game_item_manager.gim_lawn_mover.get_save_game_data_lawn_mover_manager()
	# 僵王管理器保留存活实例与整局统计；读档后的待恢复数据也由其统一保存。
	save_game_data_main_game.boss_manager_data = zombie_manager.get_save_game_data_bosses()

	# 当前关卡轮间快照的保存路径。
	var path = game_para.get_save_game_path()
	# 资源保存结果，失败时保留错误码供诊断。
	var err = ResourceSaver.save(save_game_data_main_game, path)
	if err != OK:
		push_error("关卡数据存档失败:%s, 错误代码 %d" % [path, err])
	else:
		print("关卡数据存档成功：", path)
		update_level_state_data_multi_round_data(true)


## 重置当前主游戏 多轮关卡存档,多轮关卡数据
func re_main_game():
	# 冒险和战斗预览不访问原版轮间存档。
	if AdventureSession.owns_battle(game_para) or not preview_return_scene.is_empty():
		return
	## 删除存档(若有存档会删除,没有就跳过)
	game_para.delete_game_data()
	## 更新当前关卡数据
	update_level_state_data_multi_round_data(false)


## 读档
func load_game_main_game() -> bool:
	if game_para.save_game_data_main_game != null:
		curr_game_round = game_para.save_game_data_main_game.curr_game_round
		var save_game_data_main_game:ResourceSaveGameMainGame = game_para.save_game_data_main_game
		## 罐子模式
		if game_para.is_pot_mode:
			if game_para.is_save_plant_on_pot_mode:
				if not plant_cell_manager.load_game_data_plant_cell_manager(save_game_data_main_game.plant_cell_manager_data):
					return false
			elif not board.restore_state(save_game_data_main_game.plant_cell_manager_data.board_state):
				return false
		else:
			if not plant_cell_manager.load_game_data_plant_cell_manager(save_game_data_main_game.plant_cell_manager_data):
				return false
		## 天降阳光
		day_suns_manager.curr_sun_sum_value = save_game_data_main_game.day_sun_curr_sun_sum_value
		## 植物卡槽数据
		card_manager.load_game_data_card_manager(save_game_data_main_game.card_manager_data)
		# 选卡和准备阶段只缓存僵王数据，正式进入 MAIN_GAME 后再恢复角色实例。
		zombie_manager.load_game_data_bosses(save_game_data_main_game.boss_manager_data)
	return true

#endregion
#region 更新全局关卡数据
## 更新当前关卡数据 (完成)
func update_level_state_data_success():
	## 更新全局关卡数据
	var curr_level_state_data:Dictionary = Global.global_game_state.curr_all_level_state_data.get(game_para.save_game_name, {})
	curr_level_state_data["IsSuccess"] = true
	Global.global_game_state.curr_all_level_state_data[game_para.save_game_name] = curr_level_state_data
	Global.save_service.save_now()

## 更新当前关卡数据 (多轮游戏)
func update_level_state_data_multi_round_data(is_have_multi_round_data:=true):
	## 更新全局关卡数据
	var curr_level_state_data:Dictionary = Global.global_game_state.curr_all_level_state_data.get(game_para.save_game_name, {})
	curr_level_state_data["IsHaveMultiRoundSaveGameData"] = is_have_multi_round_data
	curr_level_state_data["CurrGameRound"] = curr_game_round
	Global.global_game_state.curr_all_level_state_data[game_para.save_game_name] = curr_level_state_data
	Global.save_service.save_now()
#endregion
