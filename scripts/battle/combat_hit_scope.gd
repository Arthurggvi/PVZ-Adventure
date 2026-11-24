## 单次攻击归因与可选的实际承伤资格；调用者决定同次攻击中哪些命中需要去重。
extends RefCounted
class_name CombatHitScope

## 最终致死伤害的语义来源；持续缠怨属于普通伤害，不沿用施加它的冥弹类型。
enum DeathCause { NORMAL, FIRE, HADES }
## 伤害对植物的表现类别；直接伤害包括啃食、寻常弹体和数值伤害。
enum PlantImpact { DIRECT, EXPLOSION, CRUSH }
## 可归因的真实攻击者编号；节点离场后允许伤害继续结算。
var attacker_id: int = 0
## 仅植物读取的受击类别。
var plant_impact: PlantImpact = PlantImpact.DIRECT
## 单纯伤害归因可以在一轮多目标爆炸中共享，各原定目标的伤害仍各结算一次。
var _claim_once: bool = true
## 当前结算群组的伤害来源，跟随代伤转移到最终承伤者。
var death_cause: DeathCause = DeathCause.NORMAL
## 僵王在易伤、格挡和减伤结算后的本次最大承伤，-1 保持原有结算。
var boss_damage_cap: int = -1
## 本群组已经消费的角色实例ID；不持有角色引用，不延长实体生命。
var _claimed: Dictionary[int, bool] = {}
## 可选的致死前观察口，只接收实际承伤角色。
var before_death: Callable

## 返回携带 [param cause] 的独立命中群组；调用方决定是否共享多目标去重。
static func for_cause(cause: DeathCause) -> CombatHitScope:
	var scope := CombatHitScope.new() # 死因只属于本次结算，不写入仍存活的目标。
	scope.death_cause = cause
	return scope

## 保存 [param attacker] 和 [param impact]；多目标的原定命中资格由调用方负责。
static func for_plant_attack(attacker: Character000Base, impact: PlantImpact = PlantImpact.DIRECT) -> CombatHitScope:
	var scope := CombatHitScope.new() # 攻击归因独立于既有的实际承伤者去重群组。
	scope.attacker_id = attacker.get_instance_id() if is_instance_valid(attacker) else 0
	scope.plant_impact = impact
	scope._claim_once = false
	return scope

## 为真正承受伤害的 [param target] 核对资格；去重群组拒绝重复，所有路径拒绝死亡及待删除目标。
## 保护者转移必须先完成，再调用此处；调用方须在受击事件和扣血之前检查结果。
func try_claim(target: Character000Base) -> bool:
	if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
		return false
	if not _claim_once:
		return true
	var identity: int = target.get_instance_id() # 同一实际实体只能消费一次，与接触盒和原受保护者无关。
	if _claimed.has(identity):
		return false
	_claimed[identity] = true
	return true

## [param hp] 是最终承伤组件；[param amount] 是护甲分流后即将扣除的本体伤害。
## 默认无需采集；跨越原生死亡阈值才观察，调用先于死亡和掉落。
func before_body_loss(hp: HpComponentZombie, amount: int) -> void:
	if not before_death.is_null() and hp.would_die_from_damage(amount) and before_death.is_valid():
		before_death.call(hp.owner_character)
