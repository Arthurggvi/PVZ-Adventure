extends Plant000Base
class_name Plant016DoomShroom

@onready var bomb_component: BombComponentBase = %BombComponent

func ready_norm_signal_connect():
	super()
	bomb_component.signal_bomb_once.connect(_create_crater_at_current_cell)

## 引爆时读取当前占格，手套换格后坑洞也应出现在新位置。
func _create_crater_at_current_cell() -> void:
	plant_cell.create_crater()


## 亡语
func death_language():
	bomb_component.judge_death_bomb()
