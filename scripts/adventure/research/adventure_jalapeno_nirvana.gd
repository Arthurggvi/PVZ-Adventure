## 涅槃的支援结算，以独立爆炸身份授予和撤销伤害免疫。
extends RefCounted
class_name AdventureJalapenoNirvana

## 治疗 [param cells] 内的友军，每株至多恢复 [param damage] 点，并清除登记负面。
## [param source_id] 是本次爆炸身份；[param protected] 记录本次授予的无敌组件。
## [param active] 在每株净化前后检查战斗，防止同步回调终止战斗后继续授予无敌。
static func apply(cells: Array[PlantCell], damage: int, source_id: int, protected: Array[HpComponent], active: Callable) -> void:
	for cell: PlantCell in cells: # 现有格子可包含承托、普通占位及伴生植物。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		for plant: Plant000Base in cell.living_plants(): # 多格同株以生命组件去重。
			if not active.call():
				return
			if not is_instance_valid(plant) or plant.is_death or plant.is_hypno or plant.is_queued_for_deletion():
				continue
			var hp: HpComponent = plant.hp_component # 复用生命组件的治疗与多来源无敌。
			if not is_instance_valid(hp) or protected.has(hp):
				continue
			AdventurePlantNegativeEffects.purge(plant)
			if not active.call():
				return
			protected.append(hp)
			hp.set_immunity_source(source_id, true)
			hp.heal(damage)

## 从 [param protected] 撤销 [param source_id] 的无敌并清空记录，其他来源继续生效。
static func release(source_id: int, protected: Array[HpComponent]) -> void:
	for hp: HpComponent in protected: # 死亡或卸载的组件无需额外操作。
		if is_instance_valid(hp):
			hp.set_immunity_source(source_id, false)
	protected.clear()
