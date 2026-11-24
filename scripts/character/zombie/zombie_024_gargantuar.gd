## 巨人只管理投掷触发、动画和生成；落点与弹道交给投掷规划器。
extends Zombie000Base
class_name Zombie024Gargantuar

## 用来锁定投掷全程移动及攻击的动画名。
const THROW_ANIMATION := &"Zombie_gargantuar_throw"
## 允许出手的首个零基逻辑列，对应从左数第 4 列。
const FIRST_IMP_THROW_COLUMN: int = 3

## 背负小鬼的身体和灰烬部件，在成功出手时一并隐藏。
@export var body_imp: Array[Node2D]
## 半血投掷一次生成的小鬼数，由等阶技能覆盖。
var throw_imp_count := 1
## 五阶巨人受致死爆炸时仍播放倒地演出。
var preserve_death_animation_after_blast := false
## 背负的小鬼是否已经出手，与升阶下砸生成的小鬼独立。
var is_throw_once := false


## 在正常出战时接入投掷动画的起止事件。
func ready_norm_signal_connect() -> void:
	super()
	$AnimationTree.animation_started.connect(_on_throw_animation_started)
	anim_component.signal_animation_finished.connect(_on_throw_animation_finished)


## 动画状态机查询敌方巨人的半血投掷资格。查询不消耗随机数或投掷次数。
func can_start_imp_throw() -> bool:
	if is_hypno or is_throw_once or not is_instance_valid(hp_component):
		return false
	@warning_ignore("integer_division")
	var half_health: int = hp_component.max_hp / 2 # 保留整数半血门槛，精确半血时不触发。
	var game: MainGameManager = Global.main_game # 本巨人所在的正式战场。
	return hp_component.curr_hp < half_health and _can_release_imps(game) \
		and ImpThrowPlanner.can_throw(game, self)


## [param anim_name] 为开始的动画。投掷全程保持原地并暂停下砸。
func _on_throw_animation_started(anim_name: StringName) -> void:
	if anim_name == THROW_ANIMATION and not is_death:
		move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsCharacter)
		attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)


## [param anim_name] 为播完的动画。投掷收招后恢复寻敌和行走。
func _on_throw_animation_finished(anim_name: StringName) -> void:
	if anim_name == THROW_ANIMATION and not is_death:
		attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)
		move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsCharacter)


## 在半血投掷的动画释放帧复查敌方阵营；整组计划确定后才生成，失败时保留背负小鬼。
func throw_out_imp() -> void:
	if is_hypno or is_throw_once:
		return
	var plans: Array[ImpThrowPlan] = _plan_imp_volley(throw_imp_count, false) # 同组共享中心和飞行时长。
	if plans.is_empty():
		return
	is_throw_once = true # 在生成信号回调前占用一次性投掷，防止同步重入。
	if _spawn_imp_volley(plans) == 0:
		is_throw_once = false
		return
	for part: Node2D in body_imp: # 身体和灰烬中的背负小鬼同时移除。
		part.hide()
	SoundManager.play_other_SFX(&"swing")


## 在保护区外下砸时按当前朝向投掷 [param count] 只同阵营小鬼；短抛落在本行安全地块。
func throw_smash_imps(count: int) -> void:
	_spawn_imp_volley(_plan_imp_volley(count, true))


## 为 [param count] 只小鬼规划一组轨迹；[param allow_short_throw] 区分下砸与半血投掷意图。
func _plan_imp_volley(count: int, allow_short_throw: bool) -> Array[ImpThrowPlan]:
	var game: MainGameManager = Global.main_game # 释放时使用当前战场及其棋盘。
	if count <= 0 or not _can_release_imps(game):
		return []
	return ImpThrowPlanner.plan_volley(game, self, count, allow_short_throw, randf())


## 半血和下砸共用 [param game] 的战斗、行动和列边界门槛，动画释放帧重新检查。
func _can_release_imps(game: MainGameManager) -> bool:
	return not is_idle and not is_death and not is_queued_for_deletion() \
		and is_instance_valid(game) and game.is_ancestor_of(self) \
		and is_instance_valid(game.zombie_manager) and game.zombie_manager.is_game_running() \
		and not is_action_suspended() and not move_component.is_forced_moving() \
		and speed_factor_product() > 0.0 and _is_past_imp_throw_protection(game.board)


## 以 [param board] 中所在行第 4 列的实时左边界判断巨人脚点是否到达可出手范围。
## 第 4 列缺格时使用下一有效列，整行都没有可出手地块时返回 false。
func _is_past_imp_throw_protection(board: BoardRuntime) -> bool:
	if not is_instance_valid(board) or not board.configured:
		return false
	for cell: PlantCell in board.row_cells(lane): # 按逻辑列查找首个有效的可出手地块。
		if not is_instance_valid(cell) or cell.row_col.y < FIRST_IMP_THROW_COLUMN \
				or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
			continue
		return global_position.x >= cell.get_global_rect().position.x
	return false


## 通过生成管理器创建 [param plans] 中的实体，返回成功数；同组小鬼继承释放时的阵营和生成来源。
func _spawn_imp_volley(plans: Array[ImpThrowPlan]) -> int:
	if plans.is_empty():
		return 0
	var game: MainGameManager = Global.main_game # 计划与生成在同一个同步释放回调中执行。
	var manager: ZombieManager = game.zombie_manager # 所有小鬼继续经过唯一的生成登记入口。
	var row: ZombieRow = manager.all_zombie_rows[lane] # 攻击行不因落点格子而改变。
	var chill: Timer = all_timer[E_TimerType.IceDecelerate] # 继承普通寒冷减速的剩余时间。
	var chill_seconds: float = chill.time_left if is_instance_valid(chill) else 0.0 # 未减速时为零。
	var parameters: Dictionary = { # 模式、阵营、波次和刷新来源与父巨人保持一致。
		E_ZInitAttr.CharacterInitType: E_CharacterInitType.IsNorm,
		E_ZInitAttr.Lane: lane,
		E_ZInitAttr.CurrWave: curr_wave,
		E_ZInitAttr.IsMiniZombie: is_mini_zombie,
		E_ZInitAttr.IsPotZombie: is_pot_zombie,
		E_ZInitAttr.ParticipatesNaturalRefresh: participates_natural_refresh,
		E_ZInitAttr.StartsHypnotized: is_hypno,
	}
	var created: int = 0 # 部分创建失败也不重复派生已经登记的小鬼。
	for plan: ImpThrowPlan in plans: # 同步生成回调可能结束战斗，每只创建前再次确认存活状态。
		if is_death or is_queued_for_deletion() or not manager.is_game_running():
			break
		if not plan.is_valid():
			continue
		var imp: Zombie000Base = manager.create_norm_zombie(CharacterRegistry.ZombieType.Z025Imp,
			row, parameters, plan.spawn_position, _initialize_thrown_imp.bind(plan, chill_seconds),
			inherited_child_modifier()) # 沿用子代修饰器、计数和死亡清理。
		if is_instance_valid(imp):
			created += 1
	return created


## 在 [param imp] 入树前保存 [param plan] 和 [param chill_seconds] 秒减速，不访问未就绪的组件。
func _initialize_thrown_imp(imp: Zombie025Imp, plan: ImpThrowPlan, chill_seconds: float) -> void:
	imp.initialize_throw(plan, chill_seconds)


## 五阶巨人的致死爆炸保留倒地动画，受击和击杀归因仍走统一入口。
func _preserves_blast_death_animation() -> bool:
	return preserve_death_animation_after_blast


## 压扁地刺时免疫其反击。
func be_caltrop() -> void:
	pass


## 由死亡动画调用，播放巨人倒地音效。
func play_gargantuar_death_sfx() -> void:
	SoundManager.play_character_SFX(&"gargantudeath")
