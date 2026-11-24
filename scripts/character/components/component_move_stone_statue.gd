## 石像使用普通地面定位组件，但拒绝所有外部位移与恐惧转向。
extends MoveComponent
class_name MoveComponentStoneStatue

## 石壳固定在出生格；关闭普通移动并不足以阻止独立的击退与抛起通道。
## [param _blover_airborne] 是父类的三叶草载具例外标志，石像在两种情况下均拒绝位移。
func can_receive_forced_displacement(_blover_airborne: bool = false) -> bool:
	return false

## [param _source_id] 和 [param _enabled] 为恐惧来源开关；石像不逃跑也不改变朝向。
func set_flee_source(_source_id: int, _enabled: bool) -> void:
	pass

## 石像不会攀爬出生格上的梯子；破壳后的新普僵使用原移动组件。
func start_ladder() -> void:
	pass
