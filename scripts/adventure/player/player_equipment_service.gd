## 仅操作注入的装备状态；不读取全局玩家、不保存、不创建窗口。
extends RefCounted
class_name PlayerEquipmentService

## 本服务绑定的唯一装备域。
var _state: PlayerEquipmentState

## 注入 [param state]，调用方负责档案身份和保存边界。
func _init(state: PlayerEquipmentState) -> void:
	assert(state != null)
	_state = state

## 授予普通装备 [param definition_id]，返回新 UID；未知内容、编号型装备或 UID 耗尽时返回空字符串。
func grant(definition_id: StringName) -> String:
	var item: EquipmentDefinition = EquipmentCatalog.definition(definition_id) # 按获得时的定义固定期限。
	if item == null or not item.edition_inscriptions.is_empty():
		return ""
	return _grant_instance(item)

## 授予 [param definition_id] 已发行的 [param edition_uid]；仅接受获准持有且尚未持有的正整数编号。
## 返回独立的装备 UID；无效请求或 UID 耗尽时返回空字符串，不改变状态。
func grant_numbered(definition_id: StringName, edition_uid: Variant) -> String:
	var item: EquipmentDefinition = EquipmentCatalog.definition(definition_id) # 发行编号由内容定义明列。
	if item == null or not PlantCardInstance.is_positive_integer(edition_uid) \
			or not item.edition_inscriptions.has(int(edition_uid)):
		return ""
	var number: int = int(edition_uid) # JSON 中的整数可能以浮点数读回。
	if not ProfileEquipmentBinding.allows(definition_id, number, _state.profile_uid) \
			or owns_numbered(definition_id, number):
		return ""
	var uid: String = _grant_instance(item) # 装配仍使用档案内的独立 UID。
	if not uid.is_empty():
		_state.edition_uids[uid] = number
	return uid

## 返回当前档案是否持有 [param definition_id] 的发行编号 [param edition_uid]。
func owns_numbered(definition_id: StringName, edition_uid: int) -> bool:
	for owned_uid: String in _state.edition_uids: # 编号只在同款装备内判重，内部装备 UID 不参与比较。
		if _state.owned.get(owned_uid, "") == str(definition_id) and _state.edition_uids[owned_uid] == edition_uid:
			return true
	return false

## 根据已加载的档案身份补发专属编号，并移除其他档案的专属实例；返回是否需要保存迁移。
func reconcile_bound_items() -> bool:
	return ProfileEquipmentBinding.reconcile(_state, grant_numbered, remove)

## 按 [param item] 创建独立装备实例；返回装备 UID 并递增序号，耗尽或碰撞时返回空字符串。
func _grant_instance(item: EquipmentDefinition) -> String:
	if _state.next_id >= PlantCardInstance.MAX_JSON_INTEGER:
		return ""
	var uid: String = "EQ%06d" % _state.next_id # 永不复用的独立装备身份。
	if _state.owned.has(uid):
		return ""
	_state.owned[uid] = str(item.id)
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

## 装备当前档案获准使用的 [param uid] 并替换同槽引用；不删除持有记录。
func equip(uid: String) -> bool:
	if not _state.owned.has(uid) or _state.is_expired(uid, int(Time.get_unix_time_from_system())):
		return false
	var item: EquipmentDefinition = EquipmentCatalog.definition(_state.owned[uid]) # 服务再次校验内容，不能相信界面。
	if item == null or not _can_use(item.id, uid):
		return false
	_state.equipped[EquipmentCatalog.slot_key(item.slot)] = uid
	return true

## 返回 [param slot] 上属于当前档案且未过期的装备定义副本；无有效装配时返回 null。
func equipped_definition(slot: int) -> EquipmentDefinition:
	var uid: String = _state.equipped.get(EquipmentCatalog.slot_key(slot), "") # 只查当前槽位，避免读取背包内其他美术。
	if uid.is_empty() or _state.is_expired(uid, int(Time.get_unix_time_from_system())):
		return null
	var item: EquipmentDefinition = EquipmentCatalog.definition(_state.owned.get(uid, "")) # 校验实例仍由当前档案持有。
	return item if item != null and item.slot == slot and _can_use(item.id, uid) else null

## 按装备 [param definition_id] 和实例 [param uid] 检查当前档案是否获准持有该编号。
func _can_use(definition_id: StringName, uid: String) -> bool:
	return ProfileEquipmentBinding.allows(definition_id, _state.edition_uids.get(uid, 0), _state.profile_uid)

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
	_state.edition_uids.erase(uid)
	return _state.owned.erase(uid)

## 仅允许丢弃已过期的 [param uid]；有效实例与永久装备不会被删除。
func discard_expired(uid: String) -> bool:
	return _state.is_expired(uid, int(Time.get_unix_time_from_system())) and remove(uid)

## 返回当前档案获准持有的装备投影；[param slot] 为 -1 时列出全部槽位，否则按槽位过滤。
func rows(slot: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 定义副本与实例身份一起提供给表现层。
	var now: int = int(Time.get_unix_time_from_system()) # 同一次投影使用一致的时间。
	for uid: String in _state.owned: # 字典插入顺序保留获取顺序。
		var item: EquipmentDefinition = EquipmentCatalog.definition(_state.owned[uid]) # 不向外暴露静态资源本体。
		if item != null and (slot < 0 or item.slot == slot) and _can_use(item.id, uid):
			var expired: bool = _state.is_expired(uid, now) # 过期仍在库存，但不占用有效装备槽。
			var row: Dictionary = {"uid": uid, "definition": item,
				"expires_at": _state.expires_at.get(uid, 0), "expired": expired,
				"equipped": not expired and _state.equipped.get(EquipmentCatalog.slot_key(item.slot), "") == uid} # 每件装备独占一行。
			if _state.edition_uids.has(uid):
				var number: int = _state.edition_uids[uid] # 收藏编号与档案内装备 UID 相互独立。
				row["edition_uid"] = number
				row["inscription"] = item.edition_inscriptions.get(number, "")
			result.append(row)
	return result
