## 黑将军动作执行器：行为选择、冲锋伤害与令旗光环分别封装。
extends ZB000Base
class_name ZB002BlackGeneral

## 令旗战斗实体，纯展示资源继续独立复用。
const FLAG_SCENE: PackedScene = preload("res://scenes/character/zombie_boss/black_general_flag_entity.tscn")
## 转场本体优先从第 3 路出击，内部行号从 0 开始。
const PHASE_CHARGE_LANE: int = 2
## 转场全明星出场顺序，每组内同时召唤。
const PHASE_SUMMON_ROWS := [[0, 4], [1, 3], [2]]
## 动作执行状态；转阶段与死亡抢占普通动作，不依赖异步等待链。
enum State { ENTER, OPENING, IDLE, RAISE, WINDUP, CHARGE, STOP,
	CHANGE_LANE, PHASE_RAISE, PHASE_CHARGE_OUT, PHASE_CHARGE_IN,
	PHASE_OUT, PHASE_IN, PHASE_FINISH, DYING }
## 场景可覆盖的技能数值。
@export var config: BlackGeneralConfig = BlackGeneralConfig.new()
## 已接入的纯视觉角色。
@onready var visual: BlackGeneralVisual = $Body/BlackGeneralVisual
## 只负责动作选择的行为树实例。
var behavior := BlackGeneralBehaviorTree.new()
## 本次冲锋的移动与命中历史。
var charge := BlackGeneralCharge.new()
## 当前动作状态。
var state: State = State.ENTER
## 当前普通动作，结束后反馈行为树。
var _action: BlackGeneralBehaviorTree.Action = BlackGeneralBehaviorTree.Action.NONE
## 固定所属关卡，防止切场后回调访问新关卡。
var _game: MainGameManager
## 转阶段动作是否仍在进行，期间保持无敌。
var _transitioning: bool = false
## 本次举旗释放门闩，防止动画事件被重复发送。
var _released: bool = false
## 自己生成的令旗；死亡/离树时清理，不删除别的 Boss 的设施。
var _flags: Array[BlackGeneralFlag] = []
## 角色动画与位移共同使用的速度倍率。
var _speed: float = 1.0
## 转场举旗后下一批全明星的索引；-1 表示没有待召唤的组。
var _phase_summon_group: int = -1
## 从转场举旗关键帧起经过的战斗秒数。
var _phase_summon_elapsed: float = 0.0
## 全明星按默认入场速度走一格所需的秒数。
var _phase_summon_interval: float = 0.0
## 转场蓄力动画已播完，等最后一组全明星出场再起跑。
var _waiting_for_phase_summons: bool = false
## 等待起跑或正在扫掠的转场残影。
var _charge_shadows: Array[BlackGeneralChargeShadow] = []

## 入树时连接已接入的动画事件，定位在管理器登记结束后进行。
func ready_norm() -> void:
	super.ready_norm()
	visual.player.animation_finished.connect(_on_animation_finished)
	visual.flag_raised.connect(_on_flag_raised)
	visual.teleport_appeared.connect(_on_teleport_appeared)
	signal_update_speed.connect(_on_speed_changed)
	_set_invulnerable(true)
	_start_battle.call_deferred()

## 展示场景只播放待机，不生成援军或设施。
func ready_show() -> void:
	super.ready_show()
	visual.play_action(&"idle")
	set_physics_process(false)

## 绑定真正持有角色的关卡并从已分配的出生点传送登场。
func _start_battle() -> void:
	var ancestor: Node = get_parent() # 沿祖先定位，不使用切换后的全局场景。
	while ancestor != null and not ancestor is MainGameManager:
		ancestor = ancestor.get_parent()
	_game = ancestor as MainGameManager
	if not _battle_active() or _game.plant_cell_manager.all_plant_cells.is_empty():
		return
	if not is_finite(boss_home_x):
		place_boss_at_spawn(_game.zombie_manager, get_default_boss_spawn_position(_game.zombie_manager))
	if lane < 0 or lane >= _game.plant_cell_manager.all_plant_cells.size():
		return
	var row: Array = _game.plant_cell_manager.all_plant_cells[lane] # 初始行的场地范围。
	if row.size() < 2:
		return
	visual.bind_effects(self, self, _game, _shake_battle_camera)
	signal_status_update.emit()
	state = State.ENTER
	visual.play_action(&"teleport_in")

## 返回角色仍可执行战斗副作用的资格，不允许跨场景或结束后生成。
func _battle_active() -> bool:
	return is_instance_valid(_game) and not _game.is_queued_for_deletion() \
		and _game.is_ancestor_of(self) and _game.zombie_manager.is_game_running() \
		and not is_death and not is_queued_for_deletion()

## [param delta] 物理秒数；移动和行动等待受角色速度影响，插旗冷却按战斗时间计。
func _physics_process(delta: float) -> void:
	if not _battle_active():
		visual.retire_charge_effects()
		_clear_charge_shadows()
		return
	behavior.advance_flag_cooldown(delta)
	var step: float = delta * _speed # 经角色控制效果缩放的逻辑时间。
	if step <= 0.0:
		return
	if _phase_summon_group >= 0:
		_advance_phase_summons(step)
	_advance_charge_shadows(step)
	match state:
		State.IDLE:
			var next: BlackGeneralBehaviorTree.Action = behavior.tick(step, false, _has_flag()) # 下一叶节点。
			if next != BlackGeneralBehaviorTree.Action.NONE:
				_begin_action(next)
		State.CHARGE:
			_advance_charge(step)
		State.CHANGE_LANE:
			if advance_boss_lane_change(_game.zombie_manager, config.lane_change_speed * step):
				_finish_action()

## [param next] 已由行为树选择的普通动作；施法只在举旗关键帧执行一次。
func _begin_action(next: BlackGeneralBehaviorTree.Action) -> void:
	_action = next
	match next:
		BlackGeneralBehaviorTree.Action.CHANGE_LANE:
			boss_target_lane = _game.zombie_manager.choose_boss_lane(self)
			state = State.CHANGE_LANE
			visual.play_action(&"run")
		BlackGeneralBehaviorTree.Action.CHARGE:
			_begin_windup()
		_:
			state = State.RAISE
			_play_raise()

## 重置释放门闩，让每次举旗的关键帧各触发一次表现和技能。
func _play_raise() -> void:
	_released = false
	visual.play_action(&"raise")

## 每个普通动作只在正常结束时反馈，阶段中断不执行旧技能尾部。
func _finish_action() -> void:
	behavior.complete(_action, _action_interval())
	state = State.IDLE
	visual.play_action(&"idle")

## 返回当前阶段的动作等待秒数，入场、转阶段和普通动作完成后统一取值。
func _action_interval() -> float:
	return config.phase_two_action_interval if boss_phase >= 2 else config.phase_one_action_interval

## [param phase] 阶段编号；[param animated] 为 false 时只恢复外观，不重放阶段召唤。
func _apply_boss_visual_phase(phase: int, animated: bool) -> void:
	if phase != 2 or not is_instance_valid(visual):
		return
	if not animated:
		_enter_phase_two_look()
		return
	boss_target_lane = -1
	charge.cancel()
	visual.retire_charge_effects()
	_transitioning = true
	_set_invulnerable(true)
	state = State.PHASE_RAISE
	# 半血可能发生在普通举旗中，重播以确保阶段召唤关键帧不会被跳过。
	visual.player.stop()
	_play_raise()

## 在转场传送切换模型时，同步点燃仍存活的令旗。
func _enter_phase_two_look() -> void:
	visual.set_phase2(true)
	for flag: BlackGeneralFlag in _flags: # 只升级本体召出的存活令旗。
		if is_instance_valid(flag) and not flag.is_death and not flag.is_queued_for_deletion():
			flag.enter_phase_two(config.phase_two_block)

## 播放蓄力动作，等动画和转场召唤结束后起跑。
func _begin_windup() -> void:
	_waiting_for_phase_summons = false
	state = State.WINDUP
	visual.play_action(&"windup")

## 蓄力结束后开始本体冲锋，二阶段沿实际路线布置剪影落点。
func _begin_charge() -> void:
	charge.begin(0 if _transitioning or boss_phase >= 2 else config.phase_one_kill_limit)
	state = State.CHARGE
	var stop_x: float = charge.stop_line(_game.plant_cell_manager.all_plant_cells[lane]) # 本路冲锋的左侧边界。
	visual.begin_charge_effects(stop_x, lane)
	visual.play_action(&"charge")
	if _transitioning:
		_begin_charge_shadows()

## 用 [param step] 结算实战扫掠，并将实际位移交给共用演出组件。
func _advance_charge(step: float) -> void:
	visual.sample_charge_trail(_cell_width())
	var feet: Vector2 = global_position # 记录移动前的起点，用于在实际扫过的范围上铺开烟带。
	var completed: bool = charge.advance(self, _game.plant_cell_manager.all_plant_cells[lane], step) # 伤害可能同步触发阶段中断。
	if state != State.CHARGE or is_death:
		return
	visual.advance_charge_effects(feet)
	if completed:
		visual.finish_charge_effects()
		state = State.STOP
		visual.play_action(&"charge_stop")

## 将演出的 [param amplitude]（像素）与 [param duration]（秒）转发给战场镜头。
func _shake_battle_camera(amplitude: Vector2, duration: float) -> void:
	EventBus.push_event(MainGameCamera.SHAKE_EVENT, [amplitude, duration])

## 启动各路影子；若本体转去其他路，则由该路原定的影子补上中路。
func _begin_charge_shadows() -> void:
	if config.charge_speed <= 0.0:
		return
	var interval: float = _cell_width() / config.charge_speed # 本体和上一组各领先约一格。
	var row_count: int = _game.zombie_manager.all_zombie_rows.size() # 过滤非五路场地的无效行。
	var center_lane: int = mini(PHASE_CHARGE_LANE, row_count - 1) # 本体原定的冲锋行。
	for group_index: int in range(BlackGeneralChargeShadow.ROWS.size()): # 依次启动内侧组与外侧组。
		for planned_row: int in BlackGeneralChargeShadow.ROWS[group_index]: # 同组的残影使用同一个延迟。
			if planned_row == center_lane or planned_row >= row_count:
				continue
			var row: int = center_lane if planned_row == lane else planned_row # 换位后每路仍最多一影。
			var charge_shadow := BlackGeneralChargeShadow.new() # 该行的冲锋与命中独立结算。
			charge_shadow.setup(self, row, Vector2(boss_home_x, _row_y(row)), (group_index + 1) * interval)
			_charge_shadows.append(charge_shadow)

## 用 [param step] 推进各路残影，扫到各自停止线后转入纯视觉退场。
func _advance_charge_shadows(step: float) -> void:
	for index: int in range(_charge_shadows.size() - 1, -1, -1): # 倒序删除已经结束的残影。
		var charge_shadow: BlackGeneralChargeShadow = _charge_shadows[index] # 当前行的冲锋实例。
		if charge_shadow.advance(self, _game.plant_cell_manager.all_plant_cells[charge_shadow.lane], step):
			_charge_shadows.remove_at(index)
			charge_shadow.finish()

## 战斗结束时停止仍待命或正在冲锋的残影，已有拖尾自行淡出。
func _clear_charge_shadows() -> void:
	for charge_shadow: BlackGeneralChargeShadow in _charge_shadows: # 清理未到达终点的实例。
		charge_shadow.cancel()
	_charge_shadows.clear()

## 举旗后用 [param step] 推进各组出怪，到时立即生成整组。
func _advance_phase_summons(step: float) -> void:
	_phase_summon_elapsed += step
	while _phase_summon_group < PHASE_SUMMON_ROWS.size() \
		and _phase_summon_elapsed >= _phase_summon_group * _phase_summon_interval:
		for row: int in PHASE_SUMMON_ROWS[_phase_summon_group]: # 组内同时入场的全明星。
			_summon(CharacterRegistry.ZombieType.Z026AllStar, row, &"base")
		_phase_summon_group += 1
	if _phase_summon_group == PHASE_SUMMON_ROWS.size():
		_phase_summon_group = -1
		if state == State.WINDUP and _waiting_for_phase_summons:
			_waiting_for_phase_summons = false
			_begin_charge()

## 二阶段传送真正现身时播放龙咆哮；初次登场和静默恢复不触发。
func _on_teleport_appeared() -> void:
	if state == State.PHASE_IN and _battle_active():
		SoundManager.play_boss_phase_roar()

## 举旗关键帧的唯一效果释放入口。
func _on_flag_raised() -> void:
	if not _battle_active() or _released or state not in [State.OPENING, State.RAISE, State.PHASE_RAISE, State.PHASE_FINISH]:
		return
	_released = true
	visual.play_flag_flame()
	match state:
		State.OPENING:
			SoundManager.play_boss_phase_roar()
			for row: int in [1, 3]: # 策划第 2、4 路，内部使用零起始。
				_summon(CharacterRegistry.ZombieType.Z026AllStar, row, &"base")
		State.PHASE_RAISE:
			SoundManager.play_boss_phase_roar()
			var entry_speed: float = MoveComponent.DEFAULT_ORI_SPEED * Zombie026AllStar.CHARGE_SPEED # 基础全明星的无减速入场速度。
			_phase_summon_interval = _cell_width() / entry_speed
			_phase_summon_group = 0
			_phase_summon_elapsed = 0.0
			_advance_phase_summons(0.0)
		State.RAISE:
			match _action:
				BlackGeneralBehaviorTree.Action.PLANT_FLAG:
					_plant_flag()
				BlackGeneralBehaviorTree.Action.COMMAND:
					_command()
				BlackGeneralBehaviorTree.Action.LEAD:
					SoundManager.play_boss_phase_roar()
					_summon(CharacterRegistry.ZombieType.Z008Football, lane, &"elite", global_position.x - _cell_width())

## [param animation] 已结束的动画；状态与动画双重匹配，迟到回调不能推进新动作。
func _on_animation_finished(animation: StringName) -> void:
	if state == State.DYING:
		if animation == &"teleport_out":
			request_trophy()
			queue_free()
		return
	if not _battle_active():
		return
	match state:
		State.ENTER:
			if animation == &"teleport_in":
				state = State.OPENING
				_play_raise()
		State.OPENING, State.PHASE_FINISH:
			if animation == &"raise":
				_transitioning = false
				_set_invulnerable(false)
				behavior.reset(_action_interval())
				state = State.IDLE
				visual.play_action(&"idle")
		State.RAISE:
			if animation == &"raise":
				_finish_action()
		State.PHASE_RAISE:
			if animation == &"raise":
				# 预占实际冲锋行，让其他 Boss 在传送演出期间也能避让。
				var preferred: int = mini(PHASE_CHARGE_LANE, _game.zombie_manager.all_zombie_rows.size() - 1)
				boss_target_lane = _game.zombie_manager.choose_boss_lane(self, preferred, true)
				state = State.PHASE_CHARGE_OUT
				visual.play_action(&"teleport_out")
		State.PHASE_CHARGE_OUT:
			if animation == &"teleport_out":
				_enter_phase_two_look()
				lane = boss_target_lane
				boss_target_lane = -1
				_return_to_home()
				state = State.PHASE_CHARGE_IN
				visual.play_action(&"teleport_in")
		State.PHASE_CHARGE_IN:
			if animation == &"teleport_in":
				_begin_windup()
		State.WINDUP:
			if animation == &"windup":
				if _phase_summon_group >= 0:
					_waiting_for_phase_summons = true
				else:
					_begin_charge()
		State.STOP:
			if animation == &"charge_stop":
				if _transitioning:
					state = State.PHASE_OUT
					visual.play_action(&"teleport_out")
				else:
					_finish_action()
		State.PHASE_OUT:
			if animation == &"teleport_out":
				if retreat_after_phase_two:
					_clear_charge_shadows()
					queue_free()
					return
				_return_to_home()
				state = State.PHASE_IN
				visual.play_action(&"teleport_in")
		State.PHASE_IN:
			if animation == &"teleport_in":
				state = State.PHASE_FINISH
				_play_raise()

## 返回本关卡是否存在存活令旗，同场多个黑将军也不会重复插旗。
func _has_flag() -> bool:
	for structure: Node in get_tree().get_nodes_in_group(EnemyStructureBase.GROUP): # 场内设施。
		if structure is BlackGeneralFlag and _game.is_ancestor_of(structure) \
			and not structure.is_death and not structure.is_queued_for_deletion():
			return true
	return false

## 在前方一格生成令旗并立即启用当前阶段格挡。
func _plant_flag() -> void:
	if _has_flag():
		return
	var flag: BlackGeneralFlag = FLAG_SCENE.instantiate() # 本次令旗实体。
	flag.lane = lane
	flag.z_index = lane * 50 + 35
	(flag.get_node("HpComponent") as HpComponent).max_hp = config.flag_health
	_game.add_child(flag)
	flag.global_position = global_position - Vector2(_cell_width(), 0.0)
	_flags.append(flag)
	flag.tree_exiting.connect(_forget_flag.bind(flag.get_instance_id()))
	flag.activate(_game.zombie_manager, config.phase_one_block)
	if boss_phase >= 2:
		flag.enter_phase_two(config.phase_two_block)
	behavior.mark_flag_planted(config.flag_cooldown)

## [param instance_id] 已销毁令旗的编号；移除失效引用，避免后续阶段升级访问已释放节点。
func _forget_flag(instance_id: int) -> void:
	for index: int in range(_flags.size() - 1, -1, -1): # 倒序移除不会影响未访问条目。
		if not is_instance_valid(_flags[index]) or _flags[index].get_instance_id() == instance_id:
			_flags.remove_at(index)

## 号令交由正式旗帜波入口播报和出怪；二阶段全批为 veteran（二阶）。
func _command() -> void:
	if config.command_types.is_empty():
		return
	var types: Array[CharacterRegistry.ZombieType] = [] # 按配置抽取整批援军的物种。
	var count: int = _game.zombie_manager.all_zombie_rows.size() * config.command_per_lane # 保留原号令的援军总数。
	for index: int in range(count): # 每名援军各抽取一次。
		types.append(config.command_types.pick_random())
	SoundManager.play_boss_phase_roar()
	_game.zombie_manager.zombie_wave_manager.spawn_support_flag_wave(self, types,
		encounter_summon_tier(&"veteran" if boss_phase >= 2 else &"base"))

## [param type] 物种；[param row] 零起始行；[param tier] 等阶；[param x] 可选世界横坐标。
func _summon(type: CharacterRegistry.ZombieType, row: int, tier: StringName, x: float = INF) -> void:
	if not _battle_active() or row < 0 or row >= _game.zombie_manager.all_zombie_rows.size():
		return
	var zombie: Zombie000Base = _game.zombie_manager.zombie_wave_manager.zombie_wave_create_manager.wave_create_zombie(
		type, row, -1, Callable(), false, AdventureZombieTierBinding.new(encounter_summon_tier(tier))) # 统一登记与等阶初始化。
	if is_instance_valid(zombie) and is_finite(x):
		zombie.global_position.x = x

## 返回本行格宽，召唤与插旗共享前方一格定义。
func _cell_width() -> float:
	return _game.board.cell_width_at(global_position, lane)


## [param row] 零起始行号，返回脚底世界纵坐标。
func _row_y(row: int) -> float:
	return _game.zombie_manager.all_zombie_rows[row].zombie_create_position.global_position.y

## 传送回当前行右端，重置渲染层级并通知重新索敌。
func _return_to_home() -> void:
	global_position = Vector2(boss_home_x, _row_y(lane))
	set_boss_depth(lane)
	signal_status_update.emit()

## [param enabled] 入场/阶段无敌，不覆盖死亡或其他组件禁用原因。
func _set_invulnerable(enabled: bool) -> void:
	# 生命入口也关闭伤害，防止旧碰撞缓存或魅惑僵尸的啃食回调绕过受击框。
	hp_component.damage_immune = enabled
	hurt_box_component.change_is_enabling(not enabled, ComponentNormBase.E_IsEnableFactor.Character)
	signal_status_update.emit()

## [param speed] 当前角色速度乘积，供位移与冷却同步动画。
func _on_speed_changed(speed: float) -> void:
	_speed = maxf(0.0, speed)

## 死亡抢占任意动作，清理冲锋与旗帜后传送退场，完成动画才请求结算。
func character_death() -> void:
	if is_death:
		return
	state = State.DYING
	charge.cancel()
	visual.retire_charge_effects()
	_clear_charge_shadows()
	_clear_flags()
	super.character_death()
	visual.play_action(&"teleport_out")
	EventBus.push_event("canvas_layer_effect_once", [CanvasLayerEffect.E_CanvasLayerEffectType.Doom, 0.65])
	SoundManager.play_character_SFX(&"bossexplosion")
	SoundManager.play_boss_phase_roar()

## 卸载与死亡共用幂等清理，不让脱离 Boss 的旗帜继续提供减伤。
func _clear_flags() -> void:
	for flag: BlackGeneralFlag in _flags: # 仅销毁本角色生成的令旗。
		if is_instance_valid(flag) and not flag.is_queued_for_deletion():
			if is_instance_valid(flag.aura):
				flag.aura.clear()
			flag.queue_free()
	_flags.clear()

## 场景卸载取消未完成冲锋和设施，不触发胜负或召唤。
func _exit_tree() -> void:
	charge.cancel()
	_clear_flags()
