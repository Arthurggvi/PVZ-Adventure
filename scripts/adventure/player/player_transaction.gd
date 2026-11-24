## 角色操作的档案事务边界；服务只改内存，本层负责身份核验、持久化与失败回滚。
extends RefCounted
class_name PlayerTransaction

## 可由 UI 和获取来源调用的有限命令。
enum Action { EQUIP, UNEQUIP, GRANT, DISCARD_EXPIRED, GRANT_NUMBERED }
## 阻止保存回调间接重入装备事务。
static var _committing: bool = false

## 对 [param expected] 执行 [param action]；[param value] 为装备 UID 或授予定义 ID。
## 授予编号装备时，[param edition_uid] 必须是定义已登记的发行编号。
## 仅操作当前已加载档案；返回错误文字，成功返回空字符串。发奖入口与 UI 共用保存边界。
static func commit(expected: AdventureState, action: Action, value: String, edition_uid: int = 0) -> String:
	if _committing:
		return "正在保存角色，请稍候。"
	if expected == null or Global.global_game_state.adventure_state != expected \
			or not Global.save_service.is_current_profile_loaded():
		return "玩家档案已变化，请重新打开角色。"
	if AdventureSession.owns_battle(Global.game_para):
		return "请返回地图后调整角色装备。"
	if action == Action.GRANT_NUMBERED and not ProfileEquipmentBinding.allows(StringName(value), edition_uid, expected.equipment.profile_uid):
		return "该编号已绑定指定存档。"
	_committing = true
	var before: Dictionary = expected.equipment.to_dict() # 槽位、持有记录、发行编号和下一个装备 UID 一起恢复。
	var service := PlayerEquipmentService.new(expected.equipment) # 每次绑定权威状态，不持有跨档服务。
	var success: bool = false # 非法动作不能触发保存。
	match action:
		Action.EQUIP:
			success = service.equip(value)
		Action.UNEQUIP:
			success = service.unequip(value)
		Action.GRANT:
			success = not service.grant(StringName(value)).is_empty()
		Action.DISCARD_EXPIRED:
			success = service.discard_expired(value)
		Action.GRANT_NUMBERED:
			success = not service.grant_numbered(StringName(value), edition_uid).is_empty()
	var issue: String = "" if success else "装备不存在或当前操作无效。" # 界面只呈现业务结果。
	if not success and action == Action.GRANT_NUMBERED and service.owns_numbered(StringName(value), edition_uid):
		issue = "当前存档已持有这件编号装备（UID #%d）。" % edition_uid
	if success and not Global.save_service.save_now():
		expected.equipment.owned.assign(before.owned)
		expected.equipment.equipped.assign(before.equipped)
		expected.equipment.expires_at.assign(before.expires_at)
		expected.equipment.edition_uids.assign(before.get("edition_uids", {}))
		expected.equipment.next_id = int(before.next_id)
		issue = "保存失败，装备变更已撤销，请重试。"
	_committing = false
	if issue.is_empty():
		Global.player_changed.emit()
	return issue
