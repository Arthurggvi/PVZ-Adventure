## 单次结算群组的实际承伤资格；由调用者创建并共享，不读取全局帧号或保留跨帧状态。
extends RefCounted
class_name CombatHitScope

## 本群组已经消费的角色实例ID；不持有角色引用，不延长实体生命。
var _claimed: Dictionary[int, bool] = {}

## 为真正承受伤害的 [param target] 原子登记一次资格；重复、死亡或待删除目标返回 false。
## 保护者转移必须先完成，再调用此处；调用方须在受击事件和扣血之前检查结果。
func try_claim(target: Character000Base) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
		return false
	var identity: int = target.get_instance_id() # 同一实际实体只能消费一次，与接触盒和原受保护者无关。
	if _claimed.has(identity):
		return false
	_claimed[identity] = true
	return true
