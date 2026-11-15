## 胆小菇原生与共享词条的目标登记处；来源互相独立，输出统一去重并随生命周期撤销。
extends Node
class_name AdventureScaredyTraits

## 每个目标至多一个合成节点，光环撤销时可直接找到而不新建。
const NODE_NAME: StringName = &"AdventureScaredyTraits"
## 地格、无效化等通知之外的战斗秒兜底，用于迁格和实时群落变化。
const REFRESH_SECONDS: float = 0.2
## 真正持有本节点的受益者。
var _plant: Plant000Base
## 当次绑定的战场，拒绝跨场景重新使用旧引用。
var _game: MainGameManager
## 只保存本株冻结快照中的已选词条，不混入星级和其他光环。
var _native_rules: Dictionary = {}
## 共生源实例身份到冻结规则，每源移除仅撤销自己的条目。
var _sources: Dictionary[int, Dictionary] = {}
## 实际输出持有独立回收能力，节点先销毁也不会留下卡片减费。
var _output: AdventureScaredyTraitOutput
## 独立计时只监控规则，不驱动植物自身的攻击、成长或生产。
var _refresh_timer: Timer
## 同步重挂引起的多次离树通知合并为一个延后清理。
var _exit_cleanup_pending: bool = false

## 为 [param plant] 安装其自身的冻结 [param events]；非法物种不接入胆小菇书目。
static func install(plant: Plant000Base, events: Array[Dictionary]) -> bool:
	if plant.spawn_species_id() != 14:
		push_error("胆小菇转职事件需要对应的战斗植物")
		return false
	var traits: AdventureScaredyTraits = ensure(plant) # 入树前先挂目标合成器，父节点ready后才输出。
	traits._native_rules = AdventureScaredyTraitRules.from_events(events)
	if traits._native_rules.has("scaredy_symbiosis"):
		var aura: AdventureScaredySymbiosis = AdventureScaredySymbiosis.new() # 只传自身低阶规则，绝不传入汇总结果。
		aura.configure(plant, AdventureScaredyTraitRules.shareable(traits._native_rules))
		plant.add_child(aura)
	traits._refresh()
	return true

## 返回 [param plant] 唯一的目标合成器；普通蘑菇无需拥有卡牌快照也能受益。
static func ensure(plant: Plant000Base) -> AdventureScaredyTraits:
	var existing: AdventureScaredyTraits = plant.get_node_or_null(NodePath(NODE_NAME)) as AdventureScaredyTraits # 多个光环共用一个目标节点。
	if existing != null:
		return existing
	var traits: AdventureScaredyTraits = AdventureScaredyTraits.new() # 先绑定受益植株再入树，来源随后由调用方登记。
	traits.name = NODE_NAME
	traits._plant = plant
	plant.add_child(traits)
	return traits

## 登记 [param source_id] 的 [param rules]；白名单保证异常输入也无法再次传播共生。
func set_source(source_id: int, rules: Dictionary) -> void:
	var incoming: Dictionary = AdventureScaredyTraitRules.shareable(rules) # 从外部来源复制规则，不保存可被改写的引用。
	if _sources.get(source_id, {}) == incoming:
		return
	_sources[source_id] = incoming
	_refresh()

## 仅撤销 [param source_id]，其他来源和本株自有词条继续参与合成。
func remove_source(source_id: int) -> void:
	if _sources.erase(source_id):
		_refresh()

## 植物组件和信号晚于子节点就绪，必须等父节点ready后才改睡眠或攻击。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not is_instance_valid(_plant):
		queue_free()
	elif _plant.is_node_ready():
		_bind()
	else:
		_plant.ready.connect(_bind, CONNECT_ONE_SHOT)

## 每目标只绑定一次，棋盘变化同步刷新，避免依赖下一次轮询才改变群落。
func _bind() -> void:
	_game = Global.main_game
	if not is_instance_valid(_game) or _game.board == null:
		return
	_output = AdventureScaredyTraitOutput.new()
	_output.configure(_plant, _game, get_instance_id())
	_plant.signal_character_death.connect(_clear_output, CONNECT_ONE_SHOT)
	_plant.tree_exiting.connect(_schedule_exit_cleanup)
	_plant.child_entered_tree.connect(_on_child_entered)
	_plant.child_exiting_tree.connect(_on_child_exiting)
	_game.board.plant_relocated.connect(_refresh)
	for cell: PlantCell in _game.board.cells(): # 仅监听结构事件；每次群落仍只查询受益者自己的九宫格。
		cell.signal_plant_create.connect(_refresh.unbind(2))
		cell.signal_plant_free.connect(_refresh.unbind(2))
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = REFRESH_SECONDS
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_refresh()
	_refresh.call_deferred()

## 本节点及植物都要仍然有效；控制器被单独摘除时也必须撤销输出。
func _active() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() \
		and is_instance_valid(_plant) and _plant.is_ancestor_of(self) \
		and MushroomPlantQuery.is_active(_plant, _game)

## 先合成再输出；自有费用已在出生卡费中处理，仅共享费用进入临时卡费链接。
func _refresh() -> void:
	if _output == null:
		return
	if not _active():
		_clear_output()
		return
	var rules: Dictionary = AdventureScaredyTraitRules.merge(_native_rules, _sources) # 相同词条去重，不同词条组合。
	_output.apply(rules, rules.has("scaredy_cost") and not _native_rules.has("scaredy_cost"))

## 本株死亡或无效化时立即撤销输出，规则登记保留到节点正常销毁或恢复。
func _clear_output() -> void:
	if _output != null:
		_output.clear()

## [param child] 是新加入的子节点；无效化不能借共享唤醒或免恐惧重新启用行为。
func _on_child_entered(child: Node) -> void:
	if child is AdventurePlantNullification:
		_clear_output()

## [param child] 无效化解除后等节点完全摘除再重新评估全部来源。
func _on_child_exiting(child: Node) -> void:
	if child is AdventurePlantNullification:
		_refresh.call_deferred()

## 同帧承托重挂保留来源身份，不反复启动植物的行为时钟。
func _enter_tree() -> void:
	if is_instance_valid(_game):
		_resume_monitoring.call_deferred()

## 离树不立即重置词条，延后判定是真正移除还是同步承托重挂。
func _exit_tree() -> void:
	_schedule_exit_cleanup()

## 仅恢复监控计时；已有攻击、成长和产光时钟由原生重挂逻辑处理。
func _resume_monitoring() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if is_instance_valid(_refresh_timer) and _refresh_timer.is_stopped():
		_refresh_timer.start()
	_refresh()

## 静态任务携带输出对象，目标节点已被销毁时仍能回收对应卡片来源。
func _schedule_exit_cleanup() -> void:
	if _exit_cleanup_pending or _output == null:
		return
	_exit_cleanup_pending = true
	AdventureScaredyTraits._finish_exit.call_deferred(weakref(self), _output)

## [param reference] 可已失效；[param output] 仅在真正离场时撤销，不覆盖后来新建的目标来源。
static func _finish_exit(reference: WeakRef, output: AdventureScaredyTraitOutput) -> void:
	var traits: AdventureScaredyTraits = reference.get_ref() as AdventureScaredyTraits # 同步回到当前棋盘则继续原来的来源。
	if is_instance_valid(traits):
		traits._exit_cleanup_pending = false
		if traits._active():
			traits._resume_monitoring()
			return
	output.clear()
