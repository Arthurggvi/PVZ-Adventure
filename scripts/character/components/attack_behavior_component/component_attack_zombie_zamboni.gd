## 造冰车逐帧检查车头覆盖的格子，碾压同一格的植物和承载物。
extends AttackComponentBase
class_name AttackComponentZombieZamboni

## 原版在爆炸植物和主动触发的倭瓜面前继续行驶。
const CRUSH_EXEMPT := [
	CharacterRegistry.PlantType.P003CherryBomb, CharacterRegistry.PlantType.P018Squash,
	CharacterRegistry.PlantType.P020TangleKelp, CharacterRegistry.PlantType.P021Jalapeno,
	CharacterRegistry.PlantType.P028Blover,
]

## [param _delta] 为本次物理步长；碾压按重叠判定，与步长无关。
func _physics_process(_delta: float) -> void:
	if not is_enabling or owner.is_death or owner.is_action_suspended():
		return
	# targets 是车头范围内可攻击的同行角色，地刺优先扎破轮胎。
	var targets: Array[Character000Base] = detect_component.get_all_enemy_can_be_attacked()
	# target 是一次重叠查询得到的候选。
	for target: Character000Base in targets:
		if target is Plant022Caltrop or target is Plant047SpikeRock:
			target.be_flattened_from_enemy(owner)
			return
	# target 为本次撞到的角色，植物的外层和底座随格一起压扁。
	for target: Character000Base in targets:
		if is_instance_valid(target) and not target.is_death and target is Plant000Base \
				and not target.is_queued_for_deletion() and _can_crush(target):
			_crush_cell(target.plant_cell)
	if is_instance_valid(detect_component.brain) and not detect_component.brain.is_death:
		detect_component.brain.be_flattened()

## [param plant] 为车头覆盖的植物，休眠的冰菇和毁灭菇也可被压扁。
func _can_crush(plant: Plant000Base) -> bool:
	if plant.plant_type in [CharacterRegistry.PlantType.P015IceShroom, CharacterRegistry.PlantType.P016DoomShroom]:
		return plant.is_sleeping
	return plant.plant_type not in CRUSH_EXEMPT

## [param cell] 为受碾压的格子，压扁后植物会自行清理占位。
func _crush_cell(cell: PlantCell) -> void:
	if not is_instance_valid(cell):
		return
	# plant 是该格当前某一层的植物。
	for plant: Plant000Base in cell.plant_in_cell.values():
		if is_instance_valid(plant) and not plant.is_death and not plant.is_queued_for_deletion():
			plant.be_flattened_from_enemy(owner)

## 车头的检测信号不切换普通僵尸的停步啃食状态。
func attack_start() -> void:
	pass

## 驶离目标时继续行驶。
func attack_end() -> void:
	pass

## [param _speed_product] 为角色速度倍率，车轮重叠判定本身没有攻击间隔。
func owner_update_speed(_speed_product: float) -> void:
	pass
