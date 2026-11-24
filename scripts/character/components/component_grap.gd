## 缠绕水草的抓取和拖拽表现。挂到目标身体后随目标释放。
extends Node2D
class_name GrapComponent

## 从抓住到开始向下拉的时间，单位秒。
const HOLD_SECONDS: float = 0.5
## 开始下沉后到完成处决的时间，单位秒。
const SINK_SECONDS: float = 0.5
## 初代拖拽每百分之一秒下沉一个像素，持续 0.5 秒。
const SINK_PIXELS: float = 50.0
## 原素材以 12 帧每秒封装，初代抓取时按 24 帧每秒播放。
const GRAB_SPEED: float = 2.0

## 用初代贴图逐帧播放藤蔓，播完后保留最后的缠绕姿态。
@onready var anim_tanglekelp_grab: AnimationPlayer = $Anim_Tanglekelp_grab

## 缠住 [param zombie] 并结算下沉；[param on_kill] 只在本次实际处决时收到死者与处决前本体生命。
## 目标已被拖拽、死亡或无法播放水面抓取时返回 false，且不接管该目标。
func grab_zombie(zombie: Zombie000Base, on_kill: Callable = Callable()) -> bool:
	if not is_instance_valid(zombie) or zombie.is_death or zombie.is_queued_for_deletion() \
			or zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsDraggedUnder \
			or not is_instance_valid(zombie.swim_box_component):
		return false
	var art_origin: Node2D = zombie.body.get_node(^"BodyCorrect") # 僵尸原版分件的局部绘制原点。
	var grab_offset := Vector2(-28, 23) # 从普通泳圈僵尸分件原点到藤蔓原点的偏移。
	var splash_x: float = -13.0 # 两次水花落在目标正面的局部 X。
	if zombie is Zombie012Snorkle:
		grab_offset = Vector2(-58, 63)
		splash_x -= 37.0
	elif zombie is Zombie015Dolphinrider and zombie.is_ride:
		grab_offset = Vector2(-105, 45)
		splash_x -= 55.0
	reparent(zombie.body, false)
	position = art_origin.position + grab_offset
	zombie.begin_pool_grab()
	zombie.swim_box_component.clip_at_waterline(true)
	show()
	anim_tanglekelp_grab.play(&"Tanglekelp_grab", -1.0, GRAB_SPEED)
	anim_tanglekelp_grab.advance(0.0)
	SoundManager.play_other_SFX(&"floop")
	_spawn_target_splash(zombie, splash_x)

	var timeline: Tween = create_tween() # 随目标和战斗暂停一起停止。
	timeline.tween_interval(HOLD_SECONDS)
	timeline.tween_callback(_start_sinking.bind(zombie, splash_x))
	timeline.tween_property(zombie.body, ^"pose_position:y", SINK_PIXELS, SINK_SECONDS).as_relative()
	timeline.tween_callback(_finish_grab.bind(zombie, on_kill))
	return true

## 停住 [param zombie] 的身体动画并让藤蔓、白浪随身体一同没入水中。
## [param splash_x] 为本次下沉水花相对脚点的局部 X。
func _start_sinking(zombie: Zombie000Base, splash_x: float) -> void:
	zombie.anim_component.stop_anim()
	zombie.shadow.hide()
	zombie.swim_box_component.clip_at_waterline(false)
	_spawn_target_splash(zombie, splash_x)

## 在 [param zombie] 身前的水面生成水花。[param splash_x] 为相对角色的局部 X。
func _spawn_target_splash(zombie: Zombie000Base, splash_x: float) -> void:
	var waterline_y: float = zombie.swim_box_component.waterline_offset # 与裁切使用同一条水线。
	var splash_position: Vector2 = zombie.shadow.to_global(Vector2(splash_x, waterline_y + 4.0)) # 独立于身体位移的水花坐标。
	Splash.spawn(zombie.get_parent() as CanvasItem, splash_position, 0.8, &"plant_water", zombie.z_index + 1)

## 结算 [param zombie] 的原有死亡信号与掉落，再由 [param on_kill] 兑现本击奖励。
func _finish_grab(zombie: Zombie000Base, on_kill: Callable) -> void:
	if not zombie.is_death and not zombie.hp_component.is_death:
		var health: int = zombie.hp_component.curr_hp # 在真实处决信号把生命置零前采样。
		zombie.character_death_not_disappear()
		if zombie.is_death and on_kill.is_valid():
			on_kill.call(zombie, health)
	zombie.queue_free()

