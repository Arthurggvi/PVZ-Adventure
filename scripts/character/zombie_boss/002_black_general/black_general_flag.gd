## 黑将军令旗：生命与受击来自设施基类，格挡由可复用光环持有。
extends EnemyStructureBase
class_name BlackGeneralFlag

## 光环对象随旗帜释放，死亡时提前清理，避免帧末残留。
var aura: ZombieBlockAura
## 与黑将军共用黑焰帧，场景中降低了大小与透明度。
@onready var _black_flame: AnimatedSprite2D = $Body/BlackFlame

## [param manager] 当前战场；[param amount] 当前阶段格挡值，在入树后调用。
func activate(manager: ZombieManager, amount: int) -> void:
	aura = ZombieBlockAura.new()
	add_child(aura)
	aura.setup(manager, amount)

## 二阶段令旗点燃黑焰，并将格挡更新为 [param amount]。
func enter_phase_two(amount: int) -> void:
	aura.set_amount(amount)
	_black_flame.show()
	_black_flame.play(&"loop")

## 先撤销光环，再发送死亡与释放节点。
func character_death() -> void:
	if is_instance_valid(aura):
		aura.clear()
	super.character_death()
