## 咖啡豆先冻结实际作用计划，再由原生动画兑现唤醒；书籍效果和卡片冷却同步结算。
extends Plant000Base
class_name Plant036CoffeeBean

## 最近一次纯查询准备的计划，提交后不再换目标。
var _coffee_plan: CoffeeBeanUsePlan
## 本实例的同步提交门禁，原生动画不能重复支付代价。
var _coffee_committed: bool = false
## 只有实际授盾或复生成功才产生本次卡片冷却扩展。
var _coffee_cooldown_extra: float = 0.0
## 预置与原生转化仅恢复中心唤醒，不把其误认成新一次玩家使用。
var _native_wake_only: bool = false

## [param origin] 区分正式使用与原生预置、转化；查询不消费生命或尸体。
func prepare_placement_action(origin: PlantCell.PlacementOrigin = PlantCell.PlacementOrigin.Player) -> bool:
	if _coffee_committed:
		return true
	_native_wake_only = origin == PlantCell.PlacementOrigin.LevelSetup \
		or (origin == PlantCell.PlacementOrigin.Transformation and plant_spawn_profile == null)
	if _native_wake_only:
		return true
	if placement_use_context == null:
		placement_use_context = PlantPlacementUseContext.new()
	_coffee_plan = CoffeeBeanUsePlan.prepare(plant_cell,
		AdventureCoffeePromotionRules.from_profile(plant_spawn_profile), placement_use_context)
	return _coffee_plan.has_effect()

## 占位与支撑关系完成后同步执行一次；原生预置等全批创建结束后只冻结唤醒目标。
func commit_placement_action() -> void:
	if _coffee_committed:
		return
	if _native_wake_only:
		_coffee_committed = true
		_schedule_native_wakeup()
		return
	if _coffee_plan != null:
		_coffee_committed = true
		_coffee_cooldown_extra = _coffee_plan.commit()

## 返回本次已完成作用的额外冷却，交给手持卡唯一结算入口消费。
func placement_cooldown_extension() -> float:
	return _coffee_cooldown_extra

## [param state] 只恢复已有状态；完整读档事务结束后才收集原生中心目标，不重新支付或施效。
func load_game_data_plant(state: Dictionary) -> void:
	super.load_game_data_plant(state)
	_schedule_native_wakeup()

## 冻结调度时的战场、空间和阶段；延后收集不会把旧事务改认成新阶段。
func _schedule_native_wakeup() -> void:
	var game: MainGameManager = Global.main_game # 节点弱引用交给延后任务，不延长战场生命周期。
	if not is_instance_valid(game) or not is_instance_valid(plant_cell):
		return
	var phase: StagePhaseDefinition = AdventureSession.get_active_phase(game.game_para) # 普通轮次仍共享 null 阶段身份。
	_restore_native_wakeup.call_deferred(weakref(game), plant_cell.board, phase)

## [param game_ref]、[param board]、[param phase] 必须仍为原身份；完整事务已结束时仅冻结存活中心目标。
func _restore_native_wakeup(game_ref: WeakRef, board: BoardRuntime, phase: StagePhaseDefinition) -> void:
	if _coffee_plan != null or is_death or is_queued_for_deletion() or not is_inside_tree():
		return
	_coffee_plan = CoffeeBeanUsePlan.prepare_native_wakeup(plant_cell,
		game_ref.get_ref() as MainGameManager, board, phase)
	_coffee_committed = true

## 原生动画只兑现已经冻结的目标；既不重新付血，也不按当前格子换人。
func awake_up_plant() -> void:
	if _coffee_committed and _coffee_plan != null:
		_coffee_plan.finish_wakeup()
