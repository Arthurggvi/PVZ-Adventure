## 黑将军令旗：生命与受击来自设施基类，格挡由可复用光环持有。
extends EnemyStructureBase
class_name BlackGeneralFlag

## 光环对象随旗帜释放，死亡时提前清理，避免帧末残留。
var aura: ZombieBlockAura

## [param manager] 当前战场；[param amount] 当前阶段格挡值，在入树后调用。
func activate(manager: ZombieManager, amount: int) -> void:
	aura = ZombieBlockAura.new()
	add_child(aura)
	aura.setup(manager, amount)

## 先撤销光环，再发送死亡与释放节点。
func character_death() -> void:
	if is_instance_valid(aura):
		aura.clear()
	super.character_death()
