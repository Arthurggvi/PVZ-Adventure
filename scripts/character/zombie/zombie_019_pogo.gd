## 持杆时按落地节拍选择前进、原地蓄跳或越过植物，失去跳杆后步行啃食。
extends Zombie000Base
class_name Zombie019Pogo

## 初代每跳 80 个 10 毫秒逻辑刻。
const BOUNCE_SECONDS := 0.8
## 跨越开始 10 个逻辑刻后撞上高坚果。
const BONK_SECONDS := 0.1
## 弹簧压缩从落地前 7 个逻辑刻开始，随后播放至最后一帧。
const SPRING_START_SECONDS := 0.73
## 落地前 5 个逻辑刻播放跳杆音效。
const SPRING_SOUND_SECONDS := 0.75
## 原始 40 帧/秒相对导入动画 12 帧/秒的倍率。
const SPRING_ANIM_RATE := 40.0 / 12.0
## 越过目标中心后继续前进的距离，按本项目格宽折算。
const VAULT_CLEARANCE := 24.0
## 跳杆底端的贴地高度，抵消本体场景的初始偏移。
const STICK_GROUND_OFFSET := 22.0

## 脑子前卸掉跳杆的世界坐标，仅我是僵尸模式使用。
@export var eat_brain_glo_pos_x_in_zombie_mode: float = 50.0

## 供动画树和土豆雷识别持杆状态。
var is_pogo := true
## 额外升阶指定的跨越格数，0 使用目标植物的位置。
var big_jump_cells := 0
## [param before_x] 和 [param after_x] 分别为跨越起点和落点的世界坐标。
signal signal_big_jump_landed(before_x: float, after_x: float)

## 弹跳阶段分别为常规前进、原地蓄跳、向前越过植物。
enum Bounce { Travel, Windup, Vault }

## 当前弹跳阶段。
var _bounce := Bounce.Travel
## 当前弹跳已经过的游戏秒数。
var _bounce_elapsed := 0.0
## 落地压缩动画自上一跳触地前开始后已经过的游戏秒数。
var _spring_elapsed := 1.0
## 越过植物的起点世界坐标。
var _vault_start_x := 0.0
## 本次越过植物的有符号水平距离，单位为世界像素。
var _vault_distance := 0.0
## 跨越路线上的高坚果，移除后可以继续跨越。
var _blocking_nut: Plant024TallNut
## 失去跳杆后尚需落下的高度，单位为本地像素。
var _height := 0.0
## 步行动画所使用的美术原点。
@onready var _grounded_body_position: Vector2 = $Body/BodyCorrect.position
## 前方植物检测区，过滤同行可跨越目标。
@onready var detect_component_pogo: DetectComponent = $DetectComponentPogo
## 随弹跳改变高度的美术节点，受击框和影子留在地面。
@onready var body_correct: Node2D = $Body/BodyCorrect
## 弹簧动画通过时间定位采样，步行和啃食仍由动画树推进。
@onready var _animation_tree: AnimationTree = $AnimationTree
## 跳杆压缩动作的最后一帧。
@onready var _spring_last_frame: float = $AnimationPlayer.get_animation(&"Zombie_pogo_pogo").length

## 初始化持杆战斗状态并错开同批僵尸的弹跳节拍。
func ready_norm() -> void:
	super()
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	_bounce_elapsed = randf_range(0.0, BOUNCE_SECONDS)

## 预览采用原版弹跳末帧的站姿。
func ready_show() -> void:
	super()
	_update_bounce_visual()

## 掉头时立即卸掉跳杆，避免无头僵尸继续弹跳。
func ready_norm_signal_connect() -> void:
	super()
	hp_stage_change_component.signal_hp_stage_change.connect(_on_hp_stage_changed)

## [param delta] 是本帧的游戏秒数，应用寒冷、黄油和升阶速度倍率。
func _process(delta: float) -> void:
	if is_show or is_death:
		return
	# elapsed 是角色速度修正后的时间，停顿状态下为零。
	var elapsed: float = delta * move_component.curr_speed_product
	if not is_pogo:
		if _height > 0.0:
			_height = move_toward(_height, 0.0, elapsed * 200.0)
			body_correct.position.y = _grounded_body_position.y - _height
		return
	if is_zombie_mode and global_position.x < eat_brain_glo_pos_x_in_zombie_mode:
		loss_iron_item()
		return
	if elapsed <= 0.0:
		return

	# 上一帧和本帧的弹跳时间，用来处理一次性的压缩、音效及水平移动。
	var before: float = _bounce_elapsed
	_bounce_elapsed = minf(before + elapsed, BOUNCE_SECONDS)
	_spring_elapsed += elapsed
	if before < SPRING_START_SECONDS and _bounce_elapsed >= SPRING_START_SECONDS:
		_spring_elapsed = _bounce_elapsed - SPRING_START_SECONDS
	if before < SPRING_SOUND_SECONDS and _bounce_elapsed >= SPRING_SOUND_SECONDS:
		SoundManager.play_character_SFX(&"pogo_zombie")
	if _bounce == Bounce.Vault:
		# 高坚果被铲除或死亡时解除阻挡。新进入检测区的高坚果同样有效。
		var blocked: bool = (
			is_instance_valid(_blocking_nut)
			and not _blocking_nut.is_death
			and not _blocking_nut.is_queued_for_deletion()
			and _bounce_elapsed >= BONK_SECONDS
		)
		# 撞击帧最多走到预定撞击时刻，避免低帧率下穿过高坚果。
		var travel_end: float = maxf(before, minf(_bounce_elapsed, BONK_SECONDS)) if blocked else _bounce_elapsed
		var move_x: float = _vault_distance * (travel_end - before) / BOUNCE_SECONDS # 本帧跨越位移。
		position.x += move_x
		move_component.move_y_correct(-move_x)
		if blocked:
			_update_bounce_visual()
			SoundManager.play_other_SFX(&"bonk")
			_drop_broken_stick()
			loss_iron_item()
			return

	if _bounce_elapsed >= BOUNCE_SECONDS:
		_finish_bounce()
	_update_bounce_visual()

## 完成一跳后按当前植物位置决定下一跳，原地蓄跳仅需一次。
func _finish_bounce() -> void:
	if _bounce == Bounce.Vault:
		signal_big_jump_landed.emit(_vault_start_x, global_position.x)
	_bounce_elapsed = 0.0
	# target 是检测区内离僵尸最近的同行植物，已越过的植物不再参与。
	var target: Plant000Base
	if not is_hypno and not move_component.is_fleeing():
		# enemy 是前方检测区内可交互的存活角色。
		for enemy: Character000Base in detect_component_pogo.get_all_enemy_can_be_attacked():
			if (
				enemy is Plant000Base
				and enemy.global_position.x <= global_position.x
				and (target == null or enemy.global_position.x > target.global_position.x)
			):
				target = enemy as Plant000Base
	if target == null:
		_bounce = Bounce.Travel
		move_component.update_only_move_speed()
	elif _bounce == Bounce.Windup:
		_start_vault(target)
	else:
		_bounce = Bounce.Windup
		move_component.update_only_move_speed(0.0)

## [param target] 是本次要越过的植物，以其世界坐标决定普通落点。
func _start_vault(target: Plant000Base) -> void:
	_bounce = Bounce.Vault
	_vault_start_x = global_position.x
	_vault_distance = target.global_position.x - VAULT_CLEARANCE * absf(global_scale.x) - _vault_start_x
	_blocking_nut = target as Plant024TallNut
	if big_jump_cells > 0 and is_instance_valid(Global.main_game):
		# 以当前位置最近的种植格计算对应地图的列距。
		var cell: PlantCell = Global.main_game.board.nearest_cell(global_position, lane)
		if cell != null:
			_vault_distance = -Global.main_game.board.local_pitch(cell).x * float(big_jump_cells)

## 按初代的曲线改变高度，并在每次触地时采样跳杆压缩动作。
func _update_bounce_visual() -> void:
	# height 是当前阶段的最高点，按本项目美术的 0.8 倍比例折算。
	var height: float = 32.0
	match _bounce:
		Bounce.Windup:
			height = 40.0
		Bounce.Vault:
			height = 72.0
	# phase 是三角形弹跳曲线，再用反二次曲线在顶点放慢。
	var phase: float = 1.0 - absf(2.0 * _bounce_elapsed / BOUNCE_SECONDS - 1.0)
	_height = STICK_GROUND_OFFSET + height * phase * (2.0 - phase)
	body_correct.position.y = _grounded_body_position.y - _height
	_animation_tree.set("parameters/StateMachine/PogoPose/Seek/seek_request",
			minf(_spring_elapsed * SPRING_ANIM_RATE, _spring_last_frame))

## [param plant] 是阻跳范围内的高坚果，仅在本次跨越时记录。
func jump_be_stop(plant: Plant000Base) -> void:
	if is_pogo and _bounce == Bounce.Vault and plant.global_position.x <= global_position.x:
		_blocking_nut = plant as Plant024TallNut

## 复制当前跳杆零件作为撞击掉落物，主动画立即切换为步行。
func _drop_broken_stick() -> void:
	# 掉落物独立于僵尸的身体和动画树。
	var stick: Node2D = iron_node.duplicate(0) as Node2D
	get_parent().add_child(stick)
	stick.global_transform = iron_node.global_transform
	stick.show()
	# 补间将跳杆翻落至地面，然后淡出。
	var drop: Tween = stick.create_tween()
	drop.set_parallel().tween_property(stick, ^"global_position:y", global_position.y, 0.25)
	drop.tween_property(stick, ^"rotation", stick.rotation - 1.4, 0.25)
	drop.chain().tween_property(stick, ^"modulate:a", 0.0, 0.25)
	drop.chain().tween_callback(stick.queue_free)

## 卸掉跳杆并恢复行走、啃食及土豆雷的正常判定。
func loss_iron_item() -> void:
	if not is_pogo:
		return
	super()
	is_pogo = false
	$Body/BodyCorrect/Stick1.hide()
	$Body/BodyCorrect/Stick2.hide()
	$Body/BodyCorrect/Hand3.hide()
	detect_component_pogo.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	if is_death:
		_height = 0.0
		body_correct.position = _grounded_body_position
	else:
		move_component.update_move_mode(MoveComponent.E_MoveMode.Ground)
		move_component.update_only_move_speed()
		attack_component.enable_component(ComponentNormBase.E_IsEnableFactor.Character)

## [param stage] 为身体受损阶段，1 表示掉头。
func _on_hp_stage_changed(stage: int) -> void:
	if stage == 1:
		loss_iron_item()

## 死亡时终止跳跃，并在地面播放死亡动作。
func character_death() -> void:
	super()
	loss_iron_item()
	body_correct.position = _grounded_body_position

## 持杆时冰冻只造成减速。
## [param time] 为冻结秒数，[param new_time_ice_end_decelerate] 为后续减速秒数。
func be_ice_freeze(time: float, new_time_ice_end_decelerate: float) -> void:
	if is_pogo:
		be_ice_decelerate(time + new_time_ice_end_decelerate)
	else:
		super(time, new_time_ice_end_decelerate)

## [param butter_time] 为停顿秒数，持杆时先落回地面再停顿。
func be_butter(butter_time: float = 4.0) -> void:
	if is_pogo and not is_death:
		_height = STICK_GROUND_OFFSET
		body_correct.position.y = _grounded_body_position.y - _height
	super(butter_time)

## 恐惧合成朝向后终止已锁定的向前跨越，改用普通移动真正向反方向逃跑。
func refresh_flee_direction() -> void:
	super()
	if is_pogo and is_instance_valid(move_component) and move_component.is_fleeing():
		_bounce = Bounce.Travel
		_blocking_nut = null
		move_component.update_only_move_speed()

## 被魅惑后掉头弹跳，终止已经锁定的跨越路线。
func be_hypno() -> void:
	super()
	if is_pogo:
		_bounce = Bounce.Travel
		_blocking_nut = null
		move_component.update_only_move_speed()
