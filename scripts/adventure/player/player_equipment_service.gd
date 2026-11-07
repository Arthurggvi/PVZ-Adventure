## 仅操作注入的装备状态；不读取全局玩家、不保存、不创建窗口。
extends RefCounted
class_name PlayerEquipmentService

## 本服务绑定的唯一装备域。
var _state: PlayerEquipmentState

## 注入 [param state]，调用方负责档案身份和保存边界。
func _init(state: PlayerEquipmentState) -> void:
	assert(state != null)
	_state = state

## 授予 [param definition_id]，返回新 UID；未知内容或编号耗尽不改变状态。
func grant(definition_id: StringName) -> String:
	var item: EquipmentDefinition = EquipmentCatalog.definition(definition_id) # 按获得时的定义固定期限。
	if item == null or _state.next_id >= PlantCardInstance.MAX_JSON_INTEGER:
		return ""
	var uid: String = "EQ%06d" % _state.next_id # 永不复用的独立装备身份。
	if _state.owned.has(uid):
		return ""
	_state.owned[uid] = str(definition_id)
	if item.lifetime_days > 0:
		_state.expires_at[uid] = int(Time.get_unix_time_from_system()) + item.lifetime_days * EquipmentDefinition.SECONDS_PER_DAY
	_state.next_id += 1
	return uid

## 为旧档中尚无期限的双倍卡补发完整有效期，返回是否需要保存迁移。
func start_legacy_boost_lifetimes() -> bool:
	var changed: bool = false # 已有期限的卡不会因重新加载而续期。
	var now: int = int(Time.get_unix_time_from_system()) # 同次迁移使用统一起点。
	for uid: String in _state.owned: # 旧版收集器保留既有的永久属性。
		if _state.expires_at.has(uid):
			continue
		var item: EquipmentDefinition = EquipmentCatalog.definition(_state.owned[uid]) # 由配置决定有效天数。
		if item != null and item.lifetime_days > 0 and item.slot in [EquipmentDefinition.Slot.EXPERIENCE, EquipmentDefinition.Slot.LOOT]:
			_state.expires_at[uid] = now + item.lifetime_days * EquipmentDefinition.SECONDS_PER_DAY
			changed = true
	return changed

## 装备 [param uid] 并替换同槽引用；不删除持有记录。
func equip(uid: String) -> bool:
	if not _state.owned.has(uid) or _state.is_expired(uid, int(Time.get_unix_time_from_system())):
		return false
	var item: EquipmentDefinition = EquipmentCatalog.definition(_state.owned[uid]) # 服务再次校验内容，不能相信界面。
	if item == null:
		return false
	_state.equipped[EquipmentCatalog.slot_key(item.slot)] = uid
	return true

## 卸下 [param uid]；只接受仍在有效期内的已装配装备。
func unequip(uid: String) -> bool:
	if _state.is_expired(uid, int(Time.get_unix_time_from_system())):
		return false
	return _clear_slot(uid)

## 清理 [param uid] 的槽位引用；由卸下和移除共用。
func _clear_slot(uid: String) -> bool:
	var key: Variant = _state.equipped.find_key(uid) # 每件装备最多占用一个槽。
	return key != null and _state.equipped.erase(key)

## 移除 [param uid] 的持有记录并清理槽位引用，供未来回收业务复用。
func remove(uid: String) -> bool:
	if not _state.owned.has(uid):
		return false
	_clear_slot(uid)
	_state.expires_at.erase(uid)
	return _state.owned.erase(uid)

## 仅允许丢弃已过期的 [param uid]；有效实例与永久装备不会被删除。
func discard_expired(uid: String) -> bool:
	return _state.is_expired(uid, int(Time.get_unix_time_from_system())) and remove(uid)

## 返回独立展示投影；[param slot] 为 -1 时列出全部，否则按槽位过滤。
func rows(slot: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 定义副本与实例身份一起提供给表现层。
	var now: int = int(Time.get_unix_time_from_system()) # 同一次投影使用一致的时间。
	for uid: String in _state.owned: # 字典插入顺序保留获取顺序。
		var item: EquipmentDefinition = EquipmentCatalog.definition(_state.owned[uid]) # 不向外暴露静态资源本体。
		if item != null and (slot < 0 or item.slot == slot):
			var expired: bool = _state.is_expired(uid, now) # 过期仍在库存，但不占用有效装备槽。
			result.append({"uid": uid, "definition": item,
				"expires_at": _state.expires_at.get(uid, 0), "expired": expired,
				"equipped": not expired and _state.equipped.get(EquipmentCatalog.slot_key(item.slot), "") == uid})
	return result
