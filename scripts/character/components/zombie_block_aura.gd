## 事件驱动的全场僵尸格挡光环；施加者死亡、魅惑与离树时立即撤销来源。
extends Node
class_name ZombieBlockAura

## 光环所属战场管理器，不通过全局查找后来的关卡。
var _manager: ZombieManager
## 当前格挡值；阶段变化可原地更新所有已覆盖对象。
var _amount: int = 0
var _stackable := false
## 目标实例 ID 到弱引用，不延长角色生命周期。
var _targets: Dictionary[int, WeakRef] = {}

## [param manager] 所属战场；[param amount] 格挡数值。只初始化一次。
func setup(manager: ZombieManager, amount: int, stackable: bool = false) -> void:
	_manager = manager
	_amount = amount
	_stackable = stackable
	_manager.signal_zombie_created.connect(_apply)
	_manager.signal_living_bosses_changed.connect(_refresh_bosses)
	for zombie: Zombie000Base in manager.all_zombies_1d: # 初始存活僵尸快照来源。
		_apply(zombie)
	_refresh_bosses()

## [param amount] 新阶段格挡值，不叠加同一面旗的旧效果。
func set_amount(amount: int) -> void:
	_amount = amount
	for target_id: int in _targets.keys(): # 施加中的目标编号。
		var target: Character000Base = _targets[target_id].get_ref() as Character000Base # 可已释放。
		if is_instance_valid(target):
			_set_block(target, amount)

## 只处理管理器登记的存活 Boss，旗帜自身不会获得格挡。
func _refresh_bosses() -> void:
	for boss: ZB000Base in _manager.get_living_bosses(): # 当前存活 Boss 快照。
		_apply(boss)

## [param target] 新生成或已存活的角色；魅惑角色和死亡角色不参与。
func _apply(target: Character000Base) -> void:
	if not is_instance_valid(target) or target.is_death or target.is_hypno or target.is_queued_for_deletion():
		return
	var target_id: int = target.get_instance_id() # 来源内去重用的角色编号。
	if _targets.has(target_id):
		return
	_targets[target_id] = weakref(target)
	_set_block(target, _amount)
	target.signal_character_death.connect(_remove.bind(target_id))
	target.signal_character_be_hypno.connect(_remove.bind(target_id))
	target.tree_exiting.connect(_on_target_tree_exiting.bind(target_id))

## [param target_id] 离树目标；换行 reparent 也发出离树，延迟到迁移完成才判断真实移除。
func _on_target_tree_exiting(target_id: int) -> void:
	_reconcile_departure.call_deferred(target_id)

## [param target_id] 待复核对象；同一关卡内换父节点仍保留光环与染色。
func _reconcile_departure(target_id: int) -> void:
	if not _targets.has(target_id):
		return
	var target: Character000Base = _targets[target_id].get_ref() as Character000Base # 可能已完成销毁。
	if not is_instance_valid(target) or not is_instance_valid(_manager) \
		or not is_instance_valid(_manager.main_game) or not _manager.main_game.is_ancestor_of(target):
		_remove(target_id)

## [param target_id] 需要移除光环的目标；重复通知无副作用。
func _remove(target_id: int) -> void:
	if not _targets.has(target_id):
		return
	var target: Character000Base = _targets[target_id].get_ref() as Character000Base # 弱引用可能已失效。
	if is_instance_valid(target) and is_instance_valid(target.hp_component):
		_set_block(target, 0)
	_targets.erase(target_id)

## 停止监听并撤销全部来源；允许死亡与离树重复调用。
func clear() -> void:
	if is_instance_valid(_manager):
		if _manager.signal_zombie_created.is_connected(_apply):
			_manager.signal_zombie_created.disconnect(_apply)
		if _manager.signal_living_bosses_changed.is_connected(_refresh_bosses):
			_manager.signal_living_bosses_changed.disconnect(_refresh_bosses)
	for target_id: int in _targets.keys(): # 使用键快照以允许逐个删除。
		_remove(target_id)

func _set_block(target: Character000Base, amount: int) -> void:
	if _stackable:
		target.hp_component.damage_block.set_stackable_source(get_instance_id(), amount)
	else:
		target.hp_component.damage_block.set_source(get_instance_id(), amount)

## 场景卸载不留下任何目标染色或减伤。
func _exit_tree() -> void:
	clear()
