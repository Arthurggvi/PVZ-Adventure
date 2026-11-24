## 铁桶护卫的局部减伤与转伤。周期复查位置，出生时只判断刚加入的僵尸。
extends AdventureZombieTierAbility
class_name AdventureZombieTierField

## 位置变化的复查间隔，单位为游戏秒。
const INTERVAL := 0.12

## 提供保护的僵尸。
var _source: Zombie000Base
## 光环所属战场。
var _manager: ZombieManager
## 邻居获得的减伤比例。
var _neighbor_dr := 0.0
## 来源获得的减伤比例。
var _self_dr := 0.0
## 是否为邻居登记转移伤害资格。
var _redirect := false
## 已应用来源的目标。节点引用不延长目标寿命。
var _tracked: Dictionary[int, Zombie000Base] = {}
## 单次刷新中仍在范围内的目标，复用容器以减少分配。
var _eligible: Dictionary[int, bool] = {}
## 上次应用的格宽，单位为世界像素。
var _last_width := 0.0


## 注册 [param source] 的保护光环。[param manager] 为所属战场，[param rule] 提供减伤和转伤参数。
func setup(source: Zombie000Base, manager: ZombieManager, rule: Dictionary) -> void:
	bind_tier(source)
	_source = source
	_manager = manager
	_neighbor_dr = float(rule.get("reduction", 0.0))
	_self_dr = float(rule.get("self_reduction", _neighbor_dr))
	_redirect = bool(rule.get("redirect", false))
	_manager.signal_zombie_created.connect(_on_spawned)
	_source.signal_character_death.connect(clear)
	_source.signal_character_be_hypno.connect(clear)
	_tier_state_changed(tier_enabled())


## 给刚完成战场登记的 [param zombie] 补上保护。现有目标由周期复查更新。
func _on_spawned(zombie: Zombie000Base) -> void:
	if not tier_enabled() or not _source_active() or zombie.is_death or zombie.is_hypno \
			or absi(zombie.lane - _source.lane) > 1:
		return
	# 已初始化光环沿用最近一次邻域复查采用的范围。
	if _last_width > 0.0 and absf(zombie.global_position.x - _source.global_position.x) <= _last_width:
		_apply(zombie, _last_width)


## 检查来源仍属于当前战场，阻止离场或场景切换时重新挂上光环。
func _source_active() -> bool:
	return is_instance_valid(_source) and is_instance_valid(_manager) \
		and _source.is_inside_tree() and not _source.is_queued_for_deletion() \
		and is_instance_valid(_manager.main_game) and _manager.main_game == Global.main_game \
		and _manager.main_game.is_inside_tree() and not _manager.main_game.is_queued_for_deletion() \
		and _manager.main_game.is_ancestor_of(_source) and not _source.is_death and not _source.is_hypno


## 为新进入的 [param ally] 写入来源，转伤以 [param width] 世界像素作为一格。
func _apply(ally: Zombie000Base, width: float) -> void:
	var id: int = ally.get_instance_id() # 光环内按角色实例去重。
	if _tracked.has(id):
		return
	_tracked[id] = ally
	ally.hp_component.damage_reduction.set_source(get_instance_id(),
		_self_dr if ally == _source else _neighbor_dr)
	if _redirect and ally != _source:
		ally.hp_component.damage_transfer.set_source(get_instance_id(), _source, width)


## 对位置变化增删来源，避免每次复查都重新分配转伤记录。
func _refresh() -> void:
	if not _source_active():
		clear()
		return
	if not tier_enabled() or _manager.main_game.board == null:
		_remove_all_sources()
		return
	var width: float = _manager.main_game.board.cell_width_at(_source.global_position, _source.lane) # 当前格宽。
	if width <= 0.0:
		_remove_all_sources()
		return
	_eligible.clear()
	var allies: Array[Zombie000Base] = AdventureZombieTierNeighbors.nearby_allies(_manager, _source, width, 1) # 本次邻居。
	allies.append(_source)
	for ally: Zombie000Base in allies: # 本次仍可受保护的存活角色。
		var id: int = ally.get_instance_id() # 供清理离开范围的旧目标。
		_eligible[id] = true
		if _redirect and width != _last_width and ally != _source and _tracked.has(id):
			ally.hp_component.damage_transfer.set_source(get_instance_id(), _source, width)
		_apply(ally, width)
	_last_width = width
	for id: int in _tracked.keys(): # 快照支持在循环中撤销过期引用。
		if not _eligible.has(id):
			_remove(id)


## 注销 [param id] 的来源，允许目标已经释放。
func _remove(id: int) -> void:
	var zombie: Variant = _tracked.get(id) # 排队销毁后的节点引用可能失效。
	if is_instance_valid(zombie) and is_instance_valid(zombie.hp_component):
		zombie.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
		if _redirect:
			zombie.hp_component.damage_transfer.set_source(get_instance_id(), null)
	_tracked.erase(id)


## 离场时注销周期、出生侦听和保护来源。
func clear() -> void:
	if is_instance_valid(_manager):
		if is_instance_valid(_manager.periodic_updates):
			_manager.periodic_updates.cancel(_refresh)
		if _manager.signal_zombie_created.is_connected(_on_spawned):
			_manager.signal_zombie_created.disconnect(_on_spawned)
	_remove_all_sources()


## 撤销当前保护，不解除出生信号，供沉默和离场共同使用。
func _remove_all_sources() -> void:
	for id: int in _tracked.keys(): # 复制键以允许逐项清除。
		_remove(id)
	_last_width = 0.0
	_eligible.clear()


## [param active] 恢复时立即查询范围，沉默时撤销当前来源及周期。
func _tier_state_changed(active: bool) -> void:
	if active:
		_refresh()
		if _source_active() and is_instance_valid(_manager.periodic_updates):
			_manager.periodic_updates.schedule(_refresh, INTERVAL)
	else:
		if is_instance_valid(_manager) and is_instance_valid(_manager.periodic_updates):
			_manager.periodic_updates.cancel(_refresh)
		_remove_all_sources()


## 换行迁移保留同一光环实例，离开战场时清理。
func _exit_tree() -> void:
	if is_instance_valid(_source) and _source.is_changing_lane:
		return
	clear()
