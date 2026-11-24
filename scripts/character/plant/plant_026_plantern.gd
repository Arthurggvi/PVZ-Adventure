extends Plant000Base
class_name Plant026Plantern

## 随待机动画移动的灯罩精灵，提供局部照明的真实投光位置。
@onready var lantern_face: Sprite2D = $Body/BodyCorrect/Anim_face

func ready_norm():
	super()
	_refresh_pot_reveal([])

## 移到 [param destination] 后，透视效果跟随新的相邻格。
func update_battle_cell(destination: PlantCell) -> void:
	var previous: Array[PlantCell] = plant_cell.get_plant_cell_surrounding() # 原照亮范围用于只撤销真正移出的罐子。
	super(destination)
	_refresh_pot_reveal(previous)

## 将 [param previous] 的照明登记移交到当前范围，重叠部分不重复触发罐子动画。
func _refresh_pot_reveal(previous: Array[PlantCell]) -> void:
	var nearby: Array[PlantCell] = plant_cell.get_plant_cell_surrounding() # 按当前棋盘拓扑取相邻格。
	for cell: PlantCell in previous: # 移出范围时只移除本株的照明来源。
		if cell not in nearby and is_instance_valid(cell.pot):
			cell.pot.erase_plant_can_look_pot(self)
	for cell: PlantCell in nearby: # 新照亮的罐子仍由原生入口控制透明状态。
		if is_instance_valid(cell.pot):
			cell.pot.add_plant_can_look_pot(self)
