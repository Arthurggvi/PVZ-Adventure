## 黑将军骨架、动作和演出。实战与展示共用同一套动画、拖影、烟带和关键帧特效。
extends Node2D
class_name BlackGeneralVisual

## 举旗时通知调用者释放技能；战斗效果由调用者决定。
signal flag_raised
## 传送离场的消失帧。
signal teleport_disappeared
## 传送入场的现身帧。
signal teleport_appeared

## 冲锋步频随冲锋位移一起减半。
const CHARGE_ANIMATION_SPEED: float = 0.5
## 二阶段护甲目录。
const P2_DIR := "res://assets/adventure/zombies/black_general/parts/phase2/"
## 一阶段护甲目录。
const BASE_DIR := "res://assets/adventure/zombies/black_general/parts/armor/"
## 骨架节点到可换色护甲贴图的映射。
const MAP := {
	"Zombie_football_upperbody": "chest", "Zombie_football_upperbody2": "abdomen",
	"Zombie_football_lowerbody": "waist", "Zombie_football_leftarm_upper": "shoulder_l",
	"Zombie_football_rightarm_upper": "shoulder_r", "Zombie_football_leftarm_lower": "forearm_l",
	"Zombie_football_rightarm_lower": "forearm_r",
}
## 举旗关键帧从脚下涌起的原有黑焰。
const FLAG_FLAME = preload("res://scripts/character/zombie_boss/002_black_general/black_general_flag_flame.gd")
## 二阶段冲锋剪影，场外可使用角色的展示模式。
const SILHOUETTE_SCENE: PackedScene = preload("res://scenes/character/zombie_boss/black_general_charge_silhouette.tscn")
## 蓄力连踩使用原有践踏音效，间隔以未乘角色速度的游戏秒计。
const STOMP_SOUND: AudioStream = preload("res://assets/audio/SFX/zombie/gargantuar_thump.ogg")
## 连续践踏之间的游戏秒数。
const STOMP_INTERVAL: float = 0.22
## 本体拖影比转阶段分身拖影更实。
const CHARGE_TRAIL_OPACITY: float = 0.74
## 本体每两次落步震动之间的冲锋秒数。
const CHARGE_SHAKE_INTERVAL: float = 0.34
## 从起跑到停止线的距离比例，用于布置三个剪影。
const SILHOUETTE_PATH_FRACTIONS := [0.22, 0.50, 0.78]

## 实战和图鉴共用的时间轴播放器。
@onready var player: AnimationPlayer = $AnimationPlayer
## 护甲、披风和战旗的骨架根节点。
@onready var _parts: Node2D = $Body/BodyCorrect
## 当前是否使用二阶段外观。
var _phase2 := false
## 提供世界坐标和绘制层级的动作主体。
var _actor: Node2D
## 一次性拖影、烟带和冲击圈的宿主。
var _motion_host: Node2D
## 举旗黑焰和常驻剪影的宿主。
var _ground_host: Node2D
## 接受震幅和时长的镜头回调，未绑定时不震动。
var _shake_camera: Callable
## 本体下一次采样拖影的世界横坐标。
var _next_trail_x: float = 0.0
## 当前正在沿冲锋路线伸展的烟带。
var _charge_wake: BlackGeneralChargeWake
## 到下一次落步震动的冲锋秒数。
var _shake_wait: float = 0.0
## 二阶段沿路线尚未越过的剪影世界横坐标。
var _silhouette_marks: Array[float] = []
## 剪影在战斗中的行号，-1 时采用展示模式。
var _charge_lane: int = -1
## 蓄力专用音轨，离开蓄力即可停止重复践踏。
var _stomp_player: AudioStreamPlayer
## 距下次践踏的游戏秒数。
var _stomp_wait: float = 0.0

## 默认应用一阶段美术。
func _ready() -> void:
	set_phase2(false)

## [param actor] 提供脚底坐标和绘制深度，[param motion_host]、[param ground_host] 持有对应特效。[br]
## [param shake_camera] 接收演出产生的镜头震动，可绑定战斗镜头或独立舞台镜头。
func bind_effects(actor: Node2D, motion_host: Node2D, ground_host: Node2D, shake_camera: Callable) -> void:
	_actor = actor
	_motion_host = motion_host
	_ground_host = ground_host
	_shake_camera = shake_camera

## 播放 [param action]，沿用实战步频和角色受控速度倍率；蓄力动作同步启动践踏音轨。
func play_action(action: StringName) -> void:
	if not player.has_animation(action):
		push_error("BlackGeneralVisual: missing action %s" % action)
		return
	stop_windup_sound()
	if action == &"windup" and is_instance_valid(_actor):
		if _stomp_player == null:
			_stomp_player = AudioStreamPlayer.new()
			_stomp_player.stream = STOMP_SOUND
			_stomp_player.bus = &"SFX"
			add_child(_stomp_player)
		_stomp_wait = STOMP_INTERVAL
		_stomp_player.play()
	$Body.modulate.a = 1.0
	player.play(action, -1.0, CHARGE_ANIMATION_SPEED if action == &"charge" else 1.0)

## 中断展示中的传送，恢复身体和特效节点的待机状态。
func reset_to_idle() -> void:
	$Body.show()
	$Body.scale = Vector2.ONE
	$TeleportBlink.hide()
	$TeleportRipple.hide()
	play_action(&"idle")

## [param enabled] 切换为二阶段护甲和黑焰，保持当前动画姿势。
func set_phase2(enabled: bool) -> void:
	_phase2 = enabled
	for native: String in MAP: # 逐个替换与骨架绑定的护甲。
		var key: String = MAP[native] # 护甲贴图名。
		var sprite := _parts.get_node(native + "_Art") as Sprite2D # 原骨架上的护甲覆盖层。
		sprite.texture = load((P2_DIR if enabled else BASE_DIR) + key + ".png")
	for native: String in ["Zombie_football_leftleg_upper", "Zombie_football_rightleg_upper",
			"Zombie_football_leftleg_lower", "Zombie_football_rightleg_lower"]: # 上下腿使用已有换色版本。
		var suffix := "_phase2" if enabled else "" # 一阶段沿用未带后缀的纹理。
		var texture_path := "res://assets/adventure/zombies/black_general/generated_native/" + native + suffix + ".png" # 骨架原生贴图路径。
		(_parts.get_node(native) as Sprite2D).texture = load(texture_path)
	(_parts.get_node("Zombie_football_helmet_Art") as Sprite2D).texture = load(P2_DIR + "helmet_full.png" if enabled else BASE_DIR + "helmet.png")
	(_parts.get_node("Anim_head1_Art") as Sprite2D).texture = load((P2_DIR if enabled else BASE_DIR) + "head.png")
	var smoke := _parts.get_node("Zombie_football_upperbody/BlackSmokeBack") as AnimatedSprite2D # 身后持续的二阶段黑焰。
	smoke.visible = enabled
	if enabled:
		smoke.play(&"loop")
	else:
		smoke.stop()

## 用 [param delta] 推进蓄力踏地声；已播完蓄力但仍等待战场时，也可继续按原间隔播放。
func advance_windup_sound(delta: float) -> void:
	if not is_instance_valid(_stomp_player):
		return
	_stomp_wait -= delta
	if _stomp_wait <= 0.0:
		_stomp_player.play()
		_stomp_wait += STOMP_INTERVAL

## 中断蓄力时立刻切断原音轨。
func stop_windup_sound() -> void:
	if is_instance_valid(_stomp_player):
		_stomp_player.stop()

## 在当前主体脚下播放实战举旗的黑焰。
func play_flag_flame() -> void:
	FLAG_FLAME.new().ignite(_ground_host, _actor.global_position, _actor.z_index + 1)

## 以主体当前位置开始冲锋演出。[param stop_x] 为世界停止线，[param lane] 为实战行号或 -1（展示）。
func begin_charge_effects(stop_x: float, lane: int = -1) -> void:
	retire_charge_effects()
	_next_trail_x = _actor.global_position.x
	_shake_wait = 0.0
	_charge_lane = lane
	if _phase2 and stop_x < _next_trail_x:
		for fraction: float in SILHOUETTE_PATH_FRACTIONS: # 沿实际路线分布落点。
			_silhouette_marks.append(lerpf(_next_trail_x, stop_x, fraction))

## 移动前按 [param spacing]（世界像素）采样真实骨架姿势。
func sample_charge_trail(spacing: float) -> void:
	if _actor.global_position.x <= _next_trail_x:
		BlackGeneralChargeTrail.spawn(self, _motion_host, _actor.z_index - 1, CHARGE_TRAIL_OPACITY)
		_next_trail_x = _actor.global_position.x - spacing

## 从 [param feet] 到主体当前位置铺开烟带；[param step] 为已乘角色速度的冲锋秒数。
func advance_charge_effects(feet: Vector2, step: float) -> void:
	if _actor.global_position.x >= feet.x:
		return
	if _charge_wake == null:
		_charge_wake = BlackGeneralChargeWake.spawn(_motion_host, feet, _actor.z_index - 2, 1.0)
		BlackGeneralShadowBurst.erupt(_motion_host, feet, _actor.z_index - 1, 0.82)
	_charge_wake.follow(_actor.global_position.x)
	_shake_wait -= step
	if _shake_wait <= 0.0 and _shake_camera.is_valid():
		_shake_camera.call(Vector2(4.0, 7.0), 0.24)
		_shake_wait += CHARGE_SHAKE_INTERVAL
	while not _silhouette_marks.is_empty() and _actor.global_position.x <= _silhouette_marks[0]:
		var x: float = _silhouette_marks.pop_front() # 每个落点只生成一次，即使本帧越过多个。
		_place_silhouette(x)

## [param x] 是剪影的精确世界横坐标。展示模式沿用原设施美术及定格演出。
func _place_silhouette(x: float) -> void:
	var silhouette := SILHOUETTE_SCENE.instantiate() as BlackGeneralChargeSilhouette # 实战和展示共用的剪影场景。
	if _charge_lane < 0:
		silhouette.character_init_type = Character000Base.E_CharacterInitType.IsShow
		silhouette.z_index = _actor.z_index - 6
	else:
		silhouette.lane = _charge_lane
		silhouette.z_index = _charge_lane * 50 + 34
	silhouette.position = _ground_host.to_local(Vector2(x, _actor.global_position.y))
	_ground_host.add_child(silhouette)
	silhouette.imprint(self, _actor.global_position)

## 真实走过路线后触发急停的黑焰冲击和震动，再把烟带交还给其淡出演出。
func finish_charge_effects() -> void:
	if is_instance_valid(_charge_wake):
		BlackGeneralShadowBurst.erupt(_motion_host, _actor.global_position, _actor.z_index + 1, 1.20)
		if _shake_camera.is_valid():
			_shake_camera.call(Vector2(6.0, 10.0), 0.36)
	retire_charge_effects()

## 取消剩余落点，让已经铺开的烟带在原地自然耗散。
func retire_charge_effects() -> void:
	_silhouette_marks.clear()
	if is_instance_valid(_charge_wake) and _charge_wake.is_inside_tree():
		_charge_wake.retire(1.44)
	_charge_wake = null

## 动画关键帧通知举旗。
func _emit_flag_raised() -> void:
	flag_raised.emit()

## 动画关键帧通知传送消失。
func _emit_teleport_disappeared() -> void:
	teleport_disappeared.emit()

## 动画关键帧通知传送现身。
func _emit_teleport_appeared() -> void:
	teleport_appeared.emit()
