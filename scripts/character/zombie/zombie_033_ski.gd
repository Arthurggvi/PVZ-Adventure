## 滑雪僵尸：保留普通啃咬和阵营规则，由借冰与飞行组件共同维护滑雪过程。
extends Zombie000Base
class_name Zombie033Ski

## 飞行组件独占空中轨迹、风力改道和落地恢复，根类只转发查询。
@onready var flight_component: SkiFlight = $SkiFlight
## 借冰组件负责识别冻结植物和推动中的冰块，以及平地的移动速度。
@onready var leap_component: SkiLeap = $SkiLeap
## 受击、退场和处决可能连续触发；生命结束只能结算一次。
var _death_processed: bool = false

## 先提供现成图片中的头部锚点，再执行原僵尸初始化；展示实例不启动战斗行为。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()
	if character_init_type != E_CharacterInitType.IsNorm:
		return
	flight_component.configure(self)
	leap_component.configure(self, flight_component)

## 滑雪僵尸不进入完全冰封；原寒冷入口会将冰封请求折算为冰冻减速。
func can_cold_freeze() -> bool:
	return false

## Only the genuine flight interval rejects incoming control; ordinary ground behavior is unchanged.
func can_receive_control_effects() -> bool:
	return not is_native_airborne()

## Reject ice-charge accumulation as well as freezing and cold slowdown in flight.
func can_receive_cold() -> bool:
	return not is_native_airborne()

## 普通索敌与风力只读取真实飞行状态，滑行和落地恢复期间仍属于地面单位。
func is_native_airborne() -> bool:
	return is_instance_valid(flight_component) and flight_component.is_airborne()

## [param cells] 为三叶草既定吹退格数；仅接管其针对空中单位的那一次吹风。
## 返回 false 时保留基类既有地面处理，避免普通吹退被滑雪行为吞掉。
func handle_blover_wind(cells: int, flying: bool) -> bool:
	if not flying or not is_native_airborne():
		return false
	return flight_component.redirect_wind(cells)

## 原包提供带头倒地的完整动作；爆炸致死也使用它，另叠掉头会产生重复头部。
func _preserves_blast_death_animation() -> bool:
	return true

## 先锁住移动与攻击，再取消借冰和空中状态，最后让原生死亡信号播放完整倒地。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	attack_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	leap_component.finish_life()
	flight_component.finish_life()
	super()

## 大蒜换行会短暂移出场景树；只在真正退场时释放行为，不打断同一角色的换行。
func _exit_tree() -> void:
	if is_changing_lane:
		return
	if is_instance_valid(leap_component):
		leap_component.finish_life()
	if is_instance_valid(flight_component):
		flight_component.finish_life()
