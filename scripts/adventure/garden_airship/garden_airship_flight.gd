## 花园飞艇的局内视觉时钟。所有装饰共用同一有效秒数，世界、格子和 HUD 坐标沿用正式关卡。
extends Node

## 阴影复用器，只访问本局棋盘与角色。
const GroundContacts := preload("res://scripts/adventure/garden_airship/garden_airship_ground_contacts.gd")
## 车舱支架和平台吊索，端点采样当前甲板实际位姿。
const Rigging := preload("res://scripts/adventure/garden_airship/garden_airship_rigging.gd")
## 天空、远花带与分层云的场景入口。
const Backdrop := preload("res://scripts/adventure/garden_airship_backdrop.gd")
## 本关的风场只消费飞行时钟，不启用额外的帧处理。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 局内的互斥气流事件，不改变战斗相机。
const Atmosphere := preload("res://scripts/adventure/garden_airship/garden_airship_atmosphere.gd")
## 局部环境音频混合，输出到项目现有音效总线。
const FlightAudio := preload("res://scripts/adventure/garden_airship/garden_airship_audio.gd")
## 载具爆炸使用本关共享的战斗风场与音频路由。
const BlastDirector := preload("res://scripts/adventure/garden_airship/garden_airship_blast_director.gd")
## 战斗已有的切场遮幕，只读其忙碌状态。
const BattleTransition := preload("res://scripts/ui/transitions/scene_transition.gd")
## 当前镜头可见船体和近云的最大阵风迟滞，单位为秒。
const WIND_TAIL_SECONDS: float = 5.6
## 船底近云绘制在战斗画布上方、操作与提示层下方。
const ForegroundAir := preload("res://scripts/adventure/garden_airship/garden_airship_foreground_air.gd")
## 固定挂点上的程序化旗面，消费同一个自然飞行时钟和风场。
const FlagMotion := preload("res://scripts/adventure/garden_airship/garden_airship_flag_motion.gd")
## 飞离装饰边缘的环境碎片，在擦身云后方逐渐消隐。
const FallingDebris := preload("res://scripts/adventure/garden_airship/garden_airship_falling_debris.gd")
## 重型弹体的短促喷气声与飞机使用同一合法风声变体。
const PROJECTILE_AIR := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/jet_r5.ogg")

## 自动档在移动端启用低档，低档保留结构、视差和阴影。
@export_enum("自动", "低", "高") var quality_mode: int = 0
## 相对于环境自然秒数的运动倍率，和战斗倍速互相独立。
@export_range(0.0, 2.0, 0.05) var motion_speed: float = 1.0
## 适用于普通角色及实体弹药的晴日 RGB 乘色，状态和透明度由原有组件处理。
@export var daylight_color := Color(0.99, 0.973, 0.95)
## 已声明独占材质的原绘飞艇框架。
@export var ship_frame: Sprite2D
## 当前局的分层天幕。
@export var backdrop: Backdrop
## 当前局的钢索节点。
@export var rigging: Rigging
## 平台后方及贴身空气层，保留原船底擦身云的独立演出。
@export var foreground_air: ForegroundAir
## 本局固定的非交互落物池，和棋盘无依赖。
@export var falling_debris: FallingDebris
## 原生死亡视觉订阅和剥离代理，注入同一个局内风场。
@export var death_presentation: Node
## 原飞行场景显式安装的爆炸能力。独立旧场景没有此节点。
@export var blasts: BlastDirector

## 本关的有效视觉秒数，暂停时冻结，重开归零。
var elapsed_seconds: float = 0.0
## 正式交战中的自然秒数。结束交战时允许已开始的气流回正，再停止计时。
var battle_seconds: float = 0.0
## 供本局各个表现层读取的当前事件风压。
var event_pressure: float:
	get:
		return _atmosphere.pressure
## 带局部螺旋桨动画材质的船身。
var _ship_material: ShaderMaterial
## 船框上次提交的云影，巡航的零值不重复更新。
var _frame_cloud := Vector4.ZERO
## 战斗实体就绪后绑定，随本节点离树释放。
var _contacts: GroundContacts
## 本次战斗独占，所有布料和空气效果共享。
var _wind := Wind.new()
## 各局布料的独立积分相位，和船壳材质共用生命周期。
var _flags := FlagMotion.new()
## 该场战斗唯一的大气姿态和事件时间表。
var _atmosphere := Atmosphere.new()
## 局内音频节点，随 FlightEnvironment 暂停和退出。
var _audio: FlightAudio
## 本关所属的权威战斗，只读入场和交战阶段。
var _game: MainGameManager
## 复用战斗的遮幕状态，局内音频随遮幕淡下并随场景释放。
var _transition: BattleTransition
## 复用设置中的兼容渲染项，并平滑过渡。
var _motion_amount: float = 1.0

## 父节点在入树时完成棋盘安装，表现只消费该战局资源。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_game = get_parent() as MainGameManager # 该节点仅在花园飞艇战斗中挂载。
	if _game == null or _game.board == null or not _game.board.configured:
		set_process(false)
		return
	_ship_material = ship_frame.material as ShaderMaterial
	_transition = _game.get_node_or_null("SceneTransition") as BattleTransition
	rigging.setup(_game.board)
	foreground_air.setup_hull(ship_frame)
	_motion_amount = _motion_target()
	_audio = FlightAudio.new()
	_audio.name = &"FlightAudio"
	_audio.configure(_game.world_audio)
	add_child(_audio)
	if is_instance_valid(blasts):
		blasts.setup(_wind, _game.blast_fx_budget, _game.world_audio as GardenAirshipSpatialAudio, _audio)
	if is_instance_valid(death_presentation):
		death_presentation.setup_wind(_wind)
		death_presentation.setup_blasts(blasts)
	_apply_flight()
	_bind_contacts.call_deferred(_game)

## [param delta] 还原为未乘战斗倍速的步长。主事件从进入正式交战后才开始计时。
func _process(delta: float) -> void:
	var real_step: float = delta / maxf(Engine.time_scale, 0.001) # 游戏倍速不加快虚拟镜头和音效。
	var visual_step: float = real_step * motion_speed # 检查器中的飞行速率只调整环境。
	elapsed_seconds += visual_step
	if _in_combat() or _atmosphere.is_settling(WIND_TAIL_SECONDS):
		battle_seconds += visual_step
	_motion_amount = lerpf(_motion_amount, _motion_target(), 1.0 - exp(-8.0 * real_step))
	_apply_flight(real_step)
	rigging.refresh()
	if _contacts != null:
		_contacts.refresh()

## 只有正常交战允许排定的新事件开始。结算等待仍能看见现有事件收尾。
func _in_combat() -> bool:
	return _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME

## 「禁用特效渲染」也减轻本关横滚、俯仰和近云；无需额外的玩家设置。
func _motion_target() -> float:
	return 0.0 if is_instance_valid(Global.config_service) and Global.config_service.optional_rendering_disabled else 1.0

## [param step] 推进音量的平滑变化，其他表现按共同局内时刻取样。
func _apply_flight(step: float = 0.0) -> void:
	var reduced: bool = quality_mode == 1 or (quality_mode == 0 and OS.has_feature("mobile")) # 自动档沿用移动端策略。
	_atmosphere.advance(battle_seconds, elapsed_seconds, _motion_amount, _in_combat())
	_wind.advance(elapsed_seconds, _atmosphere)
	if is_instance_valid(blasts):
		blasts.set_reduced(reduced or _motion_amount < 0.4)
	backdrop.apply_flight(elapsed_seconds, _atmosphere, Wind.DIRECTION.x, reduced, _wind)
	if backdrop.cloud_shadow != _frame_cloud:
		_frame_cloud = backdrop.cloud_shadow
		_ship_material.set_shader_parameter(&"passing_cloud", _frame_cloud)
	foreground_air.apply_flight(_wind, _atmosphere, reduced)
	var local_wind: float = _wind.strength_at(Wind.REFERENCE_X) # 宽风床的船中取样，与短暂局部掠风分开。
	falling_debris.apply_flight(elapsed_seconds, battle_seconds, _atmosphere, _wind, _motion_amount, reduced)
	var rig_pressure: float = clampf(0.21 * _wind.cruise_load + _atmosphere.pressure_at(0.52)
		+ 0.26 * _wind.near_pressure(Wind.REFERENCE_X), 0.0, 1.0) # 轻微稳态受力，与原阵风共用承重索可动中段。
	rigging.apply_wind(elapsed_seconds, 0.0 if reduced else rig_pressure * _motion_amount)
	if _contacts != null:
		_contacts.apply_cloud_light(backdrop.cloud_shadow)
	# 两组桨盘沿用原局部帧图，按两个整秒回绕。
	_ship_material.set_shader_parameter(&"flight_seconds", fposmod(elapsed_seconds, 2.0))
	var cloth_amount: float = (0.76 if reduced else 1.0) * lerpf(0.34, 1.0, _motion_amount) # 与关卡画质及减弱动效联动。
	_flags.apply(_ship_material, _wind, step, cloth_amount)
	var pan: float = (_atmosphere.phase - 0.5) * 1.2 if _atmosphere.event_kind != Atmosphere.Event.CRUISE else 0.0 # 一般阵风随相对风方向移动。
	pan = lerpf(pan, foreground_air.sweep_pan, smoothstep(0.015, 0.24, foreground_air.sweep_proximity))
	var accents := Vector3(_atmosphere.anticipation, _atmosphere.shear, foreground_air.sweep_proximity) # 由同一时钟驱动的阶段音色及实际云体声像。
	var audible: bool = _transition == null or not _transition.busy # 过渡遮幕结束后恢复音量。
	_audio.apply_flight(step, local_wind, _atmosphere.pressure, _atmosphere.cloud_pass,
		pan, _atmosphere.event_kind, audible, accents, _wind.near_pressure(), _wind.cruise_load)

## [param origin] 是实际近身经过的位置，[param strength] 是单次可见飞越的强度。
func register_flyby(origin: Vector2, strength: float) -> void:
	_wind.disturb(origin.x, strength)

## 令 [param origin] 附近既有的布料、云层和碎屑接收一次视觉风压。[param strength] 使用爆压原有限幅。
func register_pressure_wave(origin: Vector2, strength: float) -> void:
	_wind.disturb_blast(origin.x, strength)

## [param point] 处供已脱离的烟、火星或碎片使用的世界风量，单位为战场像素每秒。
func wind_for_visual(point: Vector2) -> Vector2:
	var smoke_drift: float = lerpf(94.0, 228.0, _wind.strength_at(point.x, 0.04)) # 初生烟与爆心的原有姿态由效果自己持有。
	return Wind.DIRECTION * smoke_drift * _wind.sample_flow_ratio(point.x, 0.04, 0.42)

## 返回当局实际安装的击毁爆炸能力，其他战场和展示实例保留各自声音及火光。
func get_airship_blasts() -> Node:
	return blasts


## 从 [param point] 的既有爆心送少量小残片进入原 2.5D 落物池。
func shed_fragments(point: Vector2) -> void:
	if _motion_amount > 0.4 and quality_mode != 1:
		falling_debris.release_combat(point, elapsed_seconds, _wind)

## [param source_id] 是真实弹体身份，[param point] 是其喷口世界位置，[param height] 供虚拟声场远近取样。
func update_projectile_audio(source_id: int, point: Vector2, height: float) -> void:
	if is_instance_valid(_game.world_audio):
		_game.world_audio.update_loop(source_id, PROJECTILE_AIR, point, -18.5, 1.40, 0.5 + height * 0.012, true, 1)

## [param source_id] 对应的喷气在原弹体爆炸当帧交还音频池。
func stop_projectile_audio(source_id: int) -> void:
	if is_instance_valid(_game.world_audio):
		_game.world_audio.end_loop(source_id)

## 等 [param game] 的子管理器就绪后接入原生影子，不建立全局订阅或持久状态。
func _bind_contacts(game: MainGameManager) -> void:
	if not is_inside_tree() or not is_instance_valid(game):
		return
	_contacts = GroundContacts.new()
	_contacts.setup(game.board, game.zombie_manager, game.bullets, daylight_color)
