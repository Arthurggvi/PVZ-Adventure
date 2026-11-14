## 单次结算群组的实际承伤资格；由调用者创建并共享，不读取全局帧号或保留跨帧状态。
extends RefCounted
class_name CombatHitScope

## 最终致死伤害的语义来源；持续缠怨属于普通伤害，不沿用施加它的冥弹类型。
enum DeathCause { NORMAL, FIRE, HADES }
## 当前结算群组的伤害来源，跟随代伤转移到最终承伤者。
var death_cause: DeathCause = DeathCause.NORMAL
## 本群组已经消费的角色实例ID；不持有角色引用，不延长实体生命。
var _claimed: Dictionary[int, bool] = {}
## 可选的致死前观察口，只接收实际承伤角色。
var before_death: Callable

## 返回携带 [param cause] 的独立命中群组；调用方决定是否共享多目标去重。
static func for_cause(cause: DeathCause) -> CombatHitScope:
	var scope := CombatHitScope.new() # 死因只属于本次结算，不写入仍存活的目标。
	scope.death_cause = cause
	return scope

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

## [param hp] 是最终承伤组件；[param amount] 是护甲分流后即将扣除的本体伤害。
## 默认无需采集；跨越原生死亡阈值才观察，调用先于死亡和掉落。
func before_body_loss(hp: HpComponentZombie, amount: int) -> void:
	if amount > 0 and hp.curr_hp > hp.death_hp and hp.curr_hp - amount <= hp.death_hp and before_death.is_valid():
		before_death.call(hp.owner_character)
