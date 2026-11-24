## 伤害转移的候选来源；资格、位置和护甲仍在每次命中时即时核对。
extends RefCounted
class_name DamageTransferEffect

## 一项护卫来源和它使用的地块宽度。
class Protection:
	## 护卫实例。节点引用不延长其寿命。
	var protector: Zombie000Base
	## 用于同距离判定的护卫身份。
	var protector_id: int
	## 横向一格的距离，单位为世界像素。
	var width: float

## 按光环来源保存的候选。
var _sources: Dictionary[int, Protection] = {}
## 来源变动时更新的遍历数组；连锁伤害可以反复读取它。
var _candidates: Array[Protection] = []
## 标记候选成员是否需要重建。
var _dirty := false


## 为 [param source_id] 登记 [param protector] 和 [param cell_width]，传空引用撤销。
func set_source(source_id: int, protector: Zombie000Base, cell_width: float = 0.0) -> void:
	if not is_instance_valid(protector) or cell_width <= 0.0:
		if _sources.erase(source_id):
			_dirty = not _sources.is_empty()
			if not _dirty:
				# 无来源时结算会直接跳过查询，立即释放最后一批旧候选。
				_candidates.clear()
		return
	var entry: Protection = _sources.get(source_id) # 已建立的来源可原地调整格宽。
	if entry == null:
		entry = Protection.new()
		_sources[source_id] = entry
		_dirty = true
	entry.protector = protector
	entry.protector_id = protector.get_instance_id()
	entry.width = cell_width


## 为 [param victim] 查找范围内最近的存活护卫；无合格候选时返回 null。
func select_protector(victim: Zombie000Base) -> Zombie000Base:
	if _dirty:
		_candidates.assign(_sources.values())
		_dirty = false
	if _candidates.is_empty() or not is_instance_valid(victim) or victim.is_death \
			or victim.is_hypno or victim.lane < 0:
		return null
	var chosen: Zombie000Base = null # 当前最近的有效护卫。
	var chosen_id: int = 0 # 相同距离取较早的实例身份。
	var closest := INF # 当前行距加横距。
	var victim_x: float = victim.global_position.x # 各候选共用本次命中的实时位置。
	var victim_lane: int = victim.lane # 生命回调可换行，每次调用重新读取。
	for entry: Protection in _candidates: # 保存候选来源，护甲及位置每次即时判断。
		var protector: Zombie000Base = entry.protector # 可能在本帧前一击中已失效。
		if not is_instance_valid(protector) or protector == victim or protector.is_death \
				or protector.is_hypno or protector.is_queued_for_deletion() or protector.lane < 0:
			continue
		var lane_distance: int = absi(protector.lane - victim_lane) # 相邻行最多差一。
		if lane_distance > 1:
			continue
		var dx: float = absf(protector.global_position.x - victim_x) # 一格以内才有转伤资格。
		if dx > entry.width:
			continue
		var health := protector.hp_component as HpComponentZombie # 已登记护卫持有生命组件。
		if not is_instance_valid(health) or health.curr_hp_armor1 <= 0:
			continue
		var distance: float = dx + float(lane_distance) * entry.width # 真实格宽统一横纵距离。
		if distance < closest or (is_equal_approx(distance, closest) \
				and (chosen == null or entry.protector_id < chosen_id)):
			chosen = protector
			chosen_id = entry.protector_id
			closest = distance
	return chosen


## 是否存在可能接管当前伤害的来源；实际转移仍由实时资格判断。
func has_sources() -> bool:
	return not _sources.is_empty()
