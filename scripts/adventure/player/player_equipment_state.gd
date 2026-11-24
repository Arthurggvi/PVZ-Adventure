## 装备持有与槽位引用；与普通道具数量库存独立，仍属于同一 AdventureState。
extends RefCounted
class_name PlayerEquipmentState

## 当前档案的稳定 UID，由读档方注入；装备序列化不单独保存该身份。
var profile_uid: String = ""
## 装备 UID 到定义 ID；同款也拥有独立身份。
var owned: Dictionary[String, String] = {}
## 限时实例的 UID 到绝对 Unix 到期秒；缺项表示永久，包括旧档中的永久版。
var expires_at: Dictionary[String, int] = {}
## 编号型装备的档案内 UID 到发行编号；普通装备没有条目。
var edition_uids: Dictionary[String, int] = {}
## 槽位稳定键到已持有装备 UID；空槽不保存。
var equipped: Dictionary[String, String] = {}
## 下一 UID 编号，删除装备不回退。
var next_id: int = 1

## 返回独立序列化数据，不暴露运行态容器。
func to_dict() -> Dictionary:
	var data: Dictionary = {"owned": owned.duplicate(), "equipped": equipped.duplicate(),
		"next_id": next_id, "expires_at": expires_at.duplicate()} # 保留普通装备的存档格式。
	if not edition_uids.is_empty():
		data["edition_uids"] = edition_uids.duplicate()
	return data

## [param uid] 的期限是否已到达 [param now]（Unix 秒）；永久实例永不过期。
func is_expired(uid: String, now: int) -> bool:
	var deadline: int = expires_at.get(uid, 0) # 缺少时间戳的实例视为永久。
	return deadline > 0 and now >= deadline

## 从 [param data] 严格恢复装备；损坏引用、重复占槽、未知内容一律拒绝。
static func from_dict(data: Variant) -> PlayerEquipmentState:
	if not data is Dictionary or not data.get("owned") is Dictionary \
			or not data.get("equipped") is Dictionary or not PlantCardInstance.is_positive_integer(data.get("next_id")):
		return null
	var editions: Variant = data.get("edition_uids", {}) # 旧档没有编号字段，按空字典恢复。
	if not editions is Dictionary:
		return null
	var result := PlayerEquipmentState.new() # 恢复期间不修改调用方的存档对象。
	result.next_id = int(data.next_id)
	var seen_editions: Dictionary = {} # 每款装备已恢复的发行编号集合。
	for uid: Variant in data.owned: # UID 数值必须小于下一可分配编号。
		if not uid is String or not uid.begins_with("EQ"):
			return null
		var number: int = uid.substr(2).to_int() # 后续格式回比拒绝非规范字符串。
		if number < 1 or number >= result.next_id or uid != "EQ%06d" % number or not data.owned[uid] is String:
			return null
		var definition_id: String = data.owned[uid] # 内容 ID 决定是否要求发行编号。
		var item: EquipmentDefinition = EquipmentCatalog.definition(definition_id) # 拒绝已不存在或无效的定义。
		if item == null:
			return null
		result.owned[uid] = definition_id
		if item.edition_inscriptions.is_empty():
			continue
		var edition_uid: Variant = editions.get(uid) # 编号型装备必须对应合法发行编号。
		if not PlantCardInstance.is_positive_integer(edition_uid) or not item.edition_inscriptions.has(int(edition_uid)):
			return null
		var serial: int = int(edition_uid) # 统一 JSON 读回的整数表示。
		var seen: Dictionary = seen_editions.get(definition_id, {}) # 同款发行编号不能重复持有。
		if seen.has(serial):
			return null
		seen[serial] = true
		seen_editions[definition_id] = seen
		result.edition_uids[uid] = serial
	if result.edition_uids.size() != editions.size():
		return null # 多余记录引用了不存在的装备或普通装备。
	var deadlines: Variant = data.get("expires_at", {}) # 旧档没有期限字段。
	if not deadlines is Dictionary:
		return null
	for uid: Variant in deadlines: # 到期时间必须引用仍然持有、支持期限的装备。
		if not uid is String or not result.owned.has(uid) or not PlantCardInstance.is_positive_integer(deadlines[uid]):
			return null
		var item: EquipmentDefinition = EquipmentCatalog.definition(result.owned[uid]) # 持有记录已经通过内容校验。
		if not item.supports_lifetime():
			return null
		result.expires_at[uid] = int(deadlines[uid])
	for key: Variant in data.equipped: # 槽位只能引用合法、已拥有且适配的装备。
		var uid: Variant = data.equipped[key] # 保存值必须是字符串，不隐式转换。
		if not key is String or not uid is String or not result.owned.has(uid):
			return null
		var item: EquipmentDefinition = EquipmentCatalog.definition(result.owned[uid]) # 已验证的装备定义。
		if EquipmentCatalog.slot_key(item.slot) != key:
			return null
		result.equipped[key] = uid
	return result
