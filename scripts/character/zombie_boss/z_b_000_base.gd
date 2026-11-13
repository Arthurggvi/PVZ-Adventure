## 僵王共用登场定位、换行、负面效果免疫、死亡与奖杯请求。
extends Character000Base
class_name ZB000Base

## 由死亡动画或直接消失接口请求奖励，是否允许生成由关卡管理器判断。
signal signal_trophy_requested(global_pos: Vector2)
## 状态进入完成后通知检测器重新索敌；状态内单独修改受击开关时也应发出此信号。
## 由具体僵王及其状态机发送、检测组件监听，基类只声明共用接口。
@warning_ignore("unused_signal")
signal signal_status_update

## Single Boss phase state; all Bosses share this threshold and transition event.
## HUD listens to this signal; behavior trees and rewards remain independent.
signal signal_boss_phase_changed(phase: int)

@export_group("Boss HUD")
@export var boss_display_name: String = "Boss"
@export var boss_portrait_texture: Texture2D
@export_range(0.05, 0.95, 0.05) var phase_two_threshold_ratio: float = 0.5
## 默认包含阈值；严格低于半血的 Boss 可在场景中关闭。
@export var phase_two_threshold_inclusive: bool = true
@export_group("")
## 默认在血量触发转阶段时播放；有独立现身演出的 Boss 可绑定自己的动画关键帧。
@export var play_phase_roar_on_threshold: bool = true

var boss_phase: int = 1
var _phase_restore_silent: bool = false

## 本体相邻两行之间的相对层级差，给各自的部件和演出留出空间。
const BOSS_ROW_Z_STEP := 50.0
## 第一路本体相对 ZombieBossRoot 的渲染层级。
const BOSS_FIRST_ROW_Z := 40

## 已选定但尚未到达的零起始行号，-1 表示没有预占目标行。
var boss_target_lane: int = -1
## 入场与换行共用的世界横坐标，INF 表示尚未由战场定位。
var boss_home_x: float = INF

## 请求奖杯时使用的世界位置标记；缺失时回退到角色根节点位置。
@onready var trophy_spawn_point: Marker2D = get_node_or_null("%TrophySpawnPoint") as Marker2D
## 是否已经启动死亡淡出，防止重复创建补间或重复安排释放。
var _is_fading := false


## [param manager] 所属战场；[param spawn_lane] 为零起始行号，-1 使用场地中路。
## 返回相对 ZombieBossRoot 的默认出生点，位于该行最右格外侧。
func get_default_boss_spawn_position(manager: ZombieManager, spawn_lane: int = -1) -> Vector2:
	# 场地的实际行数，允许没有战场网格的直接预览。
	var row_count: int = manager.all_zombie_rows.size()
	if row_count == 0:
		return Vector2.ZERO
	# 单独登场沿用原先的中路位置。
	var row_index: int = spawn_lane if spawn_lane >= 0 else floori(row_count / 2.0)
	# 行的出怪标记提供脚底高度和缺少植物格时的备用横坐标。
	var feet: Vector2 = manager.all_zombie_rows[row_index].zombie_create_position.global_position
	# 从植物网格的右边缘推算传送入口，沿用黑将军和白爵士原有偏移。
	var cells: Array[PlantCell] = manager.main_game.board.row_cells(row_index) # 当前行实际地块。
	var edge: float = -INF # 不规则排列按当前世界右缘选取。
	for cell: PlantCell in cells: # 保留原版四分之一格的出场空隙。
		edge = maxf(edge, cell.global_position.x + cell.size.x * 1.25)
	if is_finite(edge):
		feet.x = edge
	return manager.zombie_boss_root.to_local(feet)


## 返回本体根节点到脚底的本地纵向偏移，单位像素。
func get_boss_feet_offset_y() -> float:
	return 0.0


## [param manager] 所属战场；[param spawn_position] 为僵王根容器下的本地坐标。[br]
## [param home_local_x] 为还原的本地待机横坐标，INF 时使用本次出生点的横坐标。
## 定位本体并同步逻辑行及渲染层级，可在入树前调用。
func place_boss_at_spawn(manager: ZombieManager, spawn_position: Vector2, home_local_x: float = INF) -> void:
	position = spawn_position
	# 博士的机甲素材在场景内有纵向偏移，按脚底而非根节点找行。
	var feet: Vector2 = manager.zombie_boss_root.to_global(spawn_position + Vector2(0.0, get_boss_feet_offset_y()))
	lane = manager.get_boss_lane_at_y(feet.y)
	# 读档时恢复原来的待机线，避免在冲锋途中存档后把场内位置当成待机点。
	var home_x: float = home_local_x if is_finite(home_local_x) else spawn_position.x
	boss_home_x = manager.zombie_boss_root.to_global(Vector2(home_x, spawn_position.y)).x
	set_boss_depth(lane)


## [param row] 零起始行号，换行过程中可传入两行之间的连续值。
func set_boss_depth(row: float) -> void:
	z_index = BOSS_FIRST_ROW_Z + roundi(maxf(0.0, row) * BOSS_ROW_Z_STEP)


## [param manager] 所属战场；[param distance] 本帧移动的世界像素数。
## 向预占行移动并更新图层，抵达后提交逻辑行、释放预占并返回 true。
func advance_boss_lane_change(manager: ZombieManager, distance: float) -> bool:
	# 预占行右侧的待机点，脚底高度来自该行出怪标记。
	var destination := Vector2(boss_home_x, manager.all_zombie_rows[boss_target_lane].zombie_create_position.global_position.y)
	global_position = global_position.move_toward(destination, distance)
	if not global_position.is_equal_approx(destination):
		# 到达之前保留原逻辑行，图层沿运动方向平滑跨越两行之间的层级。
		var start_y: float = manager.all_zombie_rows[lane].zombie_create_position.global_position.y
		if not is_equal_approx(start_y, destination.y):
			# 从原行到目标行的纵向进度，限制在 0 至 1。
			var progress: float = clampf(inverse_lerp(start_y, destination.y, global_position.y), 0.0, 1.0)
			set_boss_depth(lerpf(float(lane), float(boss_target_lane), progress))
		return false
	lane = boss_target_lane
	boss_target_lane = -1
	set_boss_depth(lane)
	signal_status_update.emit()
	return true


## Attach once to the existing HpComponent emission. No extra per-Boss health observer.
func ready_norm_signal_connect() -> void:
	super.ready_norm_signal_connect()
	hp_component.signal_hp_loss.connect(_on_shared_boss_hp_loss)


## Remaining HP crosses 50% once, including the exact threshold; visual phase is monotonic.
func _on_shared_boss_hp_loss(remaining_hp: int, _is_drop: bool) -> void:
	if boss_phase >= 2 or remaining_hp <= 0 or hp_component.max_hp <= 0:
		return
	if float(remaining_hp) / float(hp_component.max_hp) > phase_two_threshold_ratio:
		return
	if not phase_two_threshold_inclusive and float(remaining_hp) / float(hp_component.max_hp) >= phase_two_threshold_ratio:
		return
	boss_phase = 2
	body.set_boss_phase_pulse(true)
	_apply_boss_visual_phase(2, not _phase_restore_silent)
	# Snapshot restore initializes phase before HUD binds; never replay transition SFX.
	if not _phase_restore_silent:
		signal_boss_phase_changed.emit(2)


## Game-save HP restoration must set visual phase without replaying SFX or phase animation.
func restore_boss_hp(remaining_hp: int) -> void:
	if not is_node_ready() or hp_component.max_hp <= 0:
		return
	_phase_restore_silent = true
	hp_component.apply_unblocked_loss(hp_component.max_hp - clampi(remaining_hp, 1, hp_component.max_hp),
		BulletRegistry.AttackMode.Norm, false, false, false)
	_phase_restore_silent = false


## Boss-specific art adapters may override this; Doctor retains its HP-damage pipeline.
func _apply_boss_visual_phase(_phase: int, _animated: bool) -> void:
	pass


## 只读检查普通伤害、冰冻和辣椒共用的受击资格，不扣血、不修改状态或发出信号。[br]
## 存活的正常出战实例仍在树中、未排队删除且受击组件有效并启用时返回 true，否则返回 false。[br]
## 保留拒绝条件的短路顺序，确认 [member hurt_box_component] 有效后才读取其启用状态。
func _can_receive_damage() -> bool:
	if is_death or character_init_type != E_CharacterInitType.IsNorm \
		or not is_inside_tree() or is_queued_for_deletion() \
		or not is_instance_valid(hurt_box_component) or not hurt_box_component.is_enabling:
		return false
	return true


## 所有普通与特殊植物伤害共用的最后检查，防止动画关键帧或旧碰撞结果绕过受击窗口。[br]
## [param attack_value] 本次伤害；[param bullet_mode] 伤害类型。[br]
## [param is_drop] 是否允许掉落表现；[param trigger_be_attack_SFX] 是否播放受击音效。
## 致死伤害仅通过血量组件启动僵王死亡状态机，不套用普通僵尸的直接删除逻辑。
## [param bonus_damage] 同次命中的附伤；[param bonus_cap] 为劣化放大后的附伤上限，-1 不限制。
func be_attacked_bullet(attack_value: int, bullet_mode: BulletRegistry.AttackMode = BulletRegistry.AttackMode.Norm,
		is_drop: bool = true, trigger_be_attack_SFX := true, bonus_damage: int = 0, bonus_cap: int = -1):
	if not _can_receive_damage():
		return
	super.be_attacked_bullet(attack_value, bullet_mode, is_drop, trigger_be_attack_SFX, bonus_damage, bonus_cap)


## 先发出原有死亡信号供管理器扣数，再关闭受击；重复调用不重复触发亡语或计数。
func character_death() -> void:
	if is_death:
		return
	super.character_death()
	body.set_boss_phase_pulse(false)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	prepare_death_animation()


## 正常出战实例扣尽生命并登记击杀，不等待死亡演出；已死亡实例不重复扣血或计数。[br]
## 释放前通过 [method request_trophy] 请求奖励，关卡仍检查胜利条件、全部僵王死亡及重复请求。
## 死亡演出中的实例也可调用此接口，立即请求结算并移除；已排队释放时不再处理。
func character_death_disappear() -> void:
	if is_queued_for_deletion():
		return
	if not is_death:
		hp_component.Hp_loss_death(false)
	# 请求必须先于 queue_free，角色进入待删除状态后奖杯入口会拒绝请求。
	request_trophy()
	queue_free()


## 死亡演出只保留初始随机速度，后续回调不能覆盖演出速度。
func prepare_death_animation() -> void:
	# 死亡演出保留的初始随机速度倍率；无配置时使用 1，非法值会回退为 1。
	var death_speed: float = influence_speed_factors.get(E_Influence_Speed_Factor.InitRandomSpeed, 1.0)
	# 编辑器误设零速度时仍允许死亡演出完成，不改全局时间倍率。
	if not is_finite(death_speed) or death_speed <= 0:
		death_speed = 1.0
	influence_speed_factors.clear()
	influence_speed_factors[E_Influence_Speed_Factor.InitRandomSpeed] = death_speed
	signal_update_speed.emit(death_speed)


## [param value] 速度倍率；除个体初始随机速度外，只接收 1 及以上的倍率。[br]
## [param factor] 本次速度来源；死亡后冻结速度配置，保留死亡演出设定。
func update_speed_factor(value: float, factor: E_Influence_Speed_Factor) -> void:
	if not is_death and (factor == E_Influence_Speed_Factor.InitRandomSpeed or value >= 1.0):
		super.update_speed_factor(value, factor)


## [param _time] 攻击附带的减速时长，Boss 免疫减速及其冰色表现。
func be_ice_decelerate(_time: float) -> void:
	pass


## [param _time] 冰冻时长；[param _new_time_ice_end_decelerate] 解冻后的减速时长。
## Boss 免疫两种控制，只在受击窗口内结算冰菇原有的 20 点真实伤害。
func be_ice_freeze(_time: float, _new_time_ice_end_decelerate: float) -> void:
	if _can_receive_damage():
		hp_component.Hp_loss(20, BulletRegistry.AttackMode.Real, true, false)


## Boss 免疫魅惑，保持原阵营和朝向。
func be_hypno() -> void:
	pass


## 任意行的火爆辣椒均可命中，伤害仍受 Boss 受击窗口约束。[br]
## [param attack_value] 本次辣椒伤害；致死时由血量组件触发僵王死亡流程，不直接删除或播放普通僵尸灰烬。
func be_jalapeno(attack_value: int) -> void:
	if not _can_receive_damage():
		return
	hp_component.Hp_loss(attack_value, BulletRegistry.AttackMode.Penetration, false, false)


## 死亡动画和直接消失共用请求入口，不直接创建奖杯；存活、展示和正在卸载的角色不能请求奖励。
func request_trophy() -> void:
	if not is_death or character_init_type != E_CharacterInitType.IsNorm \
		or not is_inside_tree() or is_queued_for_deletion():
		return
	# 本次奖杯请求使用的全局坐标，优先取奖杯生成标记的位置。
	var spawn_position := trophy_spawn_point.global_position if is_instance_valid(trophy_spawn_point) else global_position
	signal_trophy_requested.emit(spawn_position)


## 正常死亡状态完成后沿用一秒淡出；直接消失使用 [method character_death_disappear]。
func _fade_and_remove() -> void:
	if _is_fading or not is_inside_tree() or is_queued_for_deletion():
		return
	_is_fading = true
	# 本次死亡淡出补间，在一秒内降低角色透明度，然后释放角色节点。
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)


## 原生寒冷免疫同时约束冻结值；不得经独立移速来源绕过物种规则。
func can_receive_cold() -> bool:
	return false
