## 集中维护仅限指定玩家档案持有的装备发行编号，并协调登录时的持有记录。
extends RefCounted
class_name ProfileEquipmentBinding

## 装备定义 ID 到发行编号与唯一档案 UID 的对应关系；未登记的编号可在任意档案授予。
const _OWNERS: Dictionary = {
	&"valhalla_temple_light": {
		1: "48d6de114f75ab8854007ab782ddd1a6c995a93ab82991ed89fb2ae52a767dbf",
		3: "312237aa10b3a45d554f5c703490a0ebd2f3ba636ec42a365770e2d8ef7a5849",
		4: "d8b2df2113b03b433f879822b32bc1a28a3c6d67f87937dfb6cb629eeaf4bbb4",
	},
	&"beloved_badge": {1: "cc7cc6007bf4626f8d7aa705f397c9897f80c84517d20a5978e337ce58e43ccc"},
}

## 返回档案 [param profile_uid] 是否可持有装备 [param definition_id] 的 [param edition_uid]；0 表示普通装备。
static func allows(definition_id: StringName, edition_uid: int, profile_uid: String) -> bool:
	var editions: Dictionary = _OWNERS.get(definition_id, {}) # 同款装备可为不同发行编号指定不同档案。
	var owner: String = editions.get(edition_uid, "") # 空值表示此编号无档案限制。
	return owner.is_empty() or owner == profile_uid

## 调整 [param state] 的专属装备；[param grant] 按定义 ID 和发行编号返回新 UID，[param remove] 按装备 UID 移除并清槽。
## 返回是否修改了装备状态，调用方据此保存迁移。
static func reconcile(state: PlayerEquipmentState, grant: Callable, remove: Callable) -> bool:
	var changed: bool = false # 只有新增或移除实例时才需要保存装备迁移。
	for uid: String in state.edition_uids.keys(): # 使用 UID 快照，以便移除时安全修改编号表。
		var definition_id: StringName = StringName(state.owned[uid]) # 已通过存档校验的实例定义。
		if not allows(definition_id, state.edition_uids[uid], state.profile_uid) and remove.call(uid):
			changed = true
	for definition_id: StringName in _OWNERS: # 检查当前档案是否有应自动授予的发行编号。
		var editions: Dictionary = _OWNERS[definition_id] # 此款装备的专属发行编号。
		for edition_uid: int in editions: # 可为同一档案补发多款装备或不同编号。
			if editions[edition_uid] == state.profile_uid:
				var granted_uid: String = grant.call(definition_id, edition_uid) # 发放服务会跳过已持有的编号。
				changed = changed or not granted_uid.is_empty()
	return changed
