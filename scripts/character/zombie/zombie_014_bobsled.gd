## 雪橇由四名队员推动。车体护甲耗尽时拆成独立队员，整队被消灭时一起离场。
extends Zombie000Base
class_name Zombie014Bobsled

## 初代推行 500 个 10 毫秒逻辑刻后上车。
const PUSH_SECONDS := 5.0
## 上车动作原始帧率为 20，项目导入帧率为 12。
const BOARD_ANIM_SPEED := 20.0 / 12.0
## 推行动作原始帧率为 30，项目导入帧率为 12。
const PUSH_ANIM_SPEED := 30.0 / 12.0
## 离开冰道后每个 10 毫秒逻辑刻损伤车体 6 点。
const ICE_DAMAGE_INTERVAL := 0.01
## 单个离冰逻辑刻对雪橇护甲的伤害。
const ICE_DAMAGE := 6
## 雪橇向前滑出并散队的持续时间，单位为秒。
const CRASH_SECONDS := 1.5
## 推行时四名队员的高度差，按导入素材比例折算。
const PUSH_OFFSETS := [8.0, -7.2, 5.6, -7.2]
## 上车后四名队员在车厢内的本地高度。
const SEATED_Y := -14.4

## 无冰时的耐久消耗周期倍率，0 表示该升阶在无冰地面仍能行驶。
var ice_absence_lifespan_multiplier := 1.0
## 尚未结算的离冰时间，单位为游戏秒。
var _off_ice_seconds := 0.0
## 推行动作已经过的游戏秒数。
var _push_elapsed := 0.0
## 是否已开始上车动作。
var _boarding := false
## 是否已安排车体损毁后的拆队操作。
var _breaking := false

## 雪橇前板，使用防具血量阶段替换纹理。
@onready var zombie_bobsled_1: Sprite2D = $ZombieBobsled1
## 雪橇后板，上车后绘制在所有队员后方。
@onready var sled_inside: Sprite2D = $ZombieBobsledInside
## 从前到后的四名队员美术节点，拆队时保留各自的横坐标。
@onready var all_zombie_bobsled_single_body: Array[BodyCharacter] = [$Body, $Body2, $Body3, $Body4]
## 四名队员的动画播放器，按车内位置排列。
@onready var all_anim_player: Array[AnimationPlayer] = [
	$Body/AnimationPlayer, $Body2/AnimationPlayer, $Body3/AnimationPlayer, $Body4/AnimationPlayer
]

## 按同一线速度推进推行和乘坐阶段，车上的队员无法啃食植物。
func ready_norm() -> void:
	super()
	move_child(shadow, 0)
	move_child(sled_inside, zombie_bobsled_1.get_index())
	# i 从第二名队员开始，领头队员复用角色已有的影子。
	for i in range(1, all_zombie_bobsled_single_body.size()):
		# passenger_shadow 贴在这名推车队员的脚下，上车时随领队影子隐藏。
		var passenger_shadow := Sprite2D.new()
		passenger_shadow.texture = shadow.texture
		passenger_shadow.position.x = all_zombie_bobsled_single_body[i].position.x
		shadow.add_child(passenger_shadow)
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	hp_component.signal_armor1_death.connect(_queue_crash)
	_play_crew(&"Zombie_bobsled_push", PUSH_ANIM_SPEED)

## 展示时使用原版的单人乘坐剪影和两层雪橇。
func ready_show() -> void:
	super()
	_play_crew(&"Zombie_bobsled_jump", BOARD_ANIM_SPEED)
	_set_boarding_pose(1.0)
	# player 是每名队员的播放器，停在上车动作的最后一帧。
	for player: AnimationPlayer in all_anim_player:
		player.seek(player.current_animation_length, true)
		player.pause()
	$Body2.hide()
	$Body3.hide()
	$Body4.hide()

## [param animation] 为队员动作名，[param rate] 为相对导入帧率的倍率。
func _play_crew(animation: StringName, rate: float) -> void:
	# player 是当前队员的动画播放器，四人同步上车。
	for player: AnimationPlayer in all_anim_player:
		player.play(animation, 0.0, rate)

## [param delta] 为本帧游戏秒数，用于上车和冰道检查。
func _process(delta: float) -> void:
	if is_show or is_death or _breaking:
		return
	if not _boarding:
		_push_elapsed += delta
		if _push_elapsed >= PUSH_SECONDS:
			_boarding = true
			shadow.hide()
			_play_crew(&"Zombie_bobsled_jump", BOARD_ANIM_SPEED)
	if _boarding:
		# player 的播放位置也是前后板切换图层的时间基准。
		var player: AnimationPlayer = all_anim_player[0]
		_set_boarding_pose(player.current_animation_position / player.current_animation_length
				if player.is_playing() else 1.0)
	_check_ice(delta)

## [param progress] 为上车动作的进度，动作过半时所有队员已经在车厢内。
func _set_boarding_pose(progress: float) -> void:
	# i 是从领头到末尾的队员索引，对应不同的起跳高度。
	for i in range(all_zombie_bobsled_single_body.size()):
		all_zombie_bobsled_single_body[i].position.y = lerpf(PUSH_OFFSETS[i], SEATED_Y, progress)
	if progress >= 0.5 and sled_inside.get_index() != 0:
		shadow.hide()
		move_child(sled_inside, 0)
		move_child(zombie_bobsled_1, -1)

## [param delta] 为本帧游戏秒数；保持同一行的冰道并结算离冰车体磨损。
func _check_ice(delta: float) -> void:
	if not is_instance_valid(Global.main_game) or lane < 0:
		return
	# roads 按行保存有效冰道，各段可能由不同冰车留下。
	var roads: Array = Global.main_game.zombie_manager.all_ice_roads
	if lane >= roads.size():
		return
	# on_ice 表示领头队员仍在任一冰道的左端内，冰道右侧延伸到入场区。
	var on_ice := false
	# road 为当前行的一段冰道。
	for road: IceRoad in roads[lane]:
		if is_instance_valid(road) and not road.is_queued_for_deletion():
			road.extend_remaining_time(5.0)
			on_ice = on_ice or (road.left_x < road.texture_rect.global_position.x
					and global_position.x - 34.0 * absf(global_scale.x) >= road.left_x)
	if on_ice:
		_off_ice_seconds = 0.0
		return
	if ice_absence_lifespan_multiplier <= 0.0:
		return
	# interval 为应用升阶倍率后的离冰磨损间隔。
	var interval: float = ICE_DAMAGE_INTERVAL * ice_absence_lifespan_multiplier
	_off_ice_seconds += delta
	# ticks 为累积到本帧的完整逻辑刻数。
	var ticks: int = floori(_off_ice_seconds / interval)
	if ticks > 0:
		_off_ice_seconds -= ticks * interval
		hp_component.apply_unblocked_loss(mini(hp_component.curr_hp_armor1, ticks * ICE_DAMAGE),
				BulletRegistry.AttackMode.Real, true, false)

## 车体护甲归零后安排拆队，等待触发该信号的一次攻击完整结算。
func _queue_crash() -> void:
	if _breaking or is_death:
		return
	_breaking = true
	_crash.call_deferred()

## 生成四名下车队员并交接自然波次登记。致死攻击期间取消拆队。
func _crash() -> void:
	if is_death or is_queued_for_deletion() or not is_instance_valid(Global.main_game):
		return
	# manager 是管理本场雪橇和下车队员的僵尸管理器。
	var manager: ZombieManager = Global.main_game.zombie_manager
	if not manager.is_game_running() or lane < 0 or lane >= manager.all_zombie_rows.size():
		return
	# row 提供当前行的出生基准，使队员按正常地面或屋顶斜面落位。
	var row: ZombieRow = manager.all_zombie_rows[lane]
	# init 保存队员共有的行号、波次以及自然刷新归属。
	var init: Dictionary = {
		E_ZInitAttr.CharacterInitType: E_CharacterInitType.IsNorm,
		E_ZInitAttr.Lane: lane,
		E_ZInitAttr.CurrWave: curr_wave,
		E_ZInitAttr.ParticipatesNaturalRefresh: participates_natural_refresh,
	}
	# crew 将接管雪橇在本波的剩余血量统计。
	var crew: Array[Zombie000Base] = []
	# i 是队员索引，只有领头队员继承雪橇实际承受的本体伤害。
	for i in range(all_zombie_bobsled_single_body.size()):
		# member_position 保留队员相对雪橇的横向排布，纵坐标使用行基准。
		var member_position := Vector2(all_zombie_bobsled_single_body[i].global_position.x,
				row.zombie_create_position.global_position.y)
		# member 是拆队后正常登记、可独立行动的僵尸。
		var member: Zombie000Base = manager.create_norm_zombie(CharacterRegistry.ZombieType.Z1001BobsledSingle,
				row, init, member_position, Callable(), inherited_child_modifier())
		if not is_instance_valid(member):
			continue
		crew.append(member)
		_begin_member_crash(member)
	manager.zombie_wave_manager.replace_bobsled_with_crew(self, crew)
	if not crew.is_empty() and hp_component.curr_hp < hp_component.max_hp:
		# leader 继承车体护甲被打穿后进入本体的生命差额。
		var leader: Zombie000Base = crew[0]
		leader.hp_component.curr_hp = hp_component.curr_hp
		leader.hp_stage_change_component.judge_body_change(hp_component.curr_hp)
	_slide_wreck(row)
	queue_free()

## [param member] 在撞车后先踉跄前行，随后恢复啃食与地面受击。
func _begin_member_crash(member: Zombie000Base) -> void:
	member.curr_be_attack_status = E_BeAttackStatusZombie.IsJump
	member.attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Jump)
	# timer 受关卡暂停控制，超时前队员可能已经被范围伤害消灭。
	var timer: SceneTreeTimer = get_tree().create_timer(CRASH_SECONDS, false)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(member) and not member.is_death and not member.is_queued_for_deletion():
			member.curr_be_attack_status = E_BeAttackStatusZombie.IsNorm
			member.attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Jump)
	)

## [param row] 承载残骸的战斗行；残骸先向前滑动，最后 0.3 秒淡出。
func _slide_wreck(row: ZombieRow) -> void:
	# wreck 继承最后一阶段的雪橇纹理及屏幕位置。
	var wreck: Sprite2D = zombie_bobsled_1.duplicate() as Sprite2D
	row.add_child(wreck)
	wreck.global_transform = zombie_bobsled_1.global_transform
	# slide 控制残骸的惯性位移与淡出。
	var slide: Tween = wreck.create_tween().set_parallel()
	slide.tween_property(wreck, ^"position:x", wreck.position.x - 40.0, CRASH_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	slide.tween_property(wreck, ^"modulate:a", 0.0, 0.3).set_delay(CRASH_SECONDS - 0.3)
	slide.chain().tween_callback(wreck.queue_free)

## 车上尚未单独登记的三名乘员生命，仅用于自然波次的血量统计。
func passenger_wave_health() -> int:
	return 0 if is_death else hp_component.max_hp * (all_zombie_bobsled_single_body.size() - 1)

## 整队死亡时计入乘员剩余生命，爆炸灰烬由现有组件单独播放。
func character_death() -> void:
	# passengers 是死亡信号修改状态前尚未扣除的乘员生命。
	var passengers: int = passenger_wave_health()
	super()
	signal_zombie_hp_loss.emit(passengers, curr_wave)
	queue_free()

## 雪橇上的队员免疫寒冷。
## [param _time] 为减速秒数。
func be_ice_decelerate(_time: float) -> void:
	pass

## [param _time] 为冻结秒数，[param _new_time_ice_end_decelerate] 为解冻后的减速秒数。
func be_ice_freeze(_time: float, _new_time_ice_end_decelerate: float) -> void:
	pass

## [param _butter_time] 为黄油停顿秒数，乘坐阶段不受黄油影响。
func be_butter(_butter_time: float = 4.0) -> void:
	pass

## 车上成员不接受魅惑，散队后各自按普通僵尸处理。
func be_hypno() -> void:
	pass
