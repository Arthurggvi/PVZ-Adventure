## 寒冰菇沿用原生引信，并在出生时保存本卡的转职规则。
extends Plant000Base
class_name Plant015IceShroom

## 原生引爆组件，动画与亡语共用同一次引爆。
@onready var bomb_component: BombComponentIce = $BombComponent

## 将出战卡 [param uid] 的 [param events] 在入树前交给原生引爆组件。
func configure_promotions(uid: String, events: Array[Dictionary]) -> void:
	($BombComponent as BombComponentIce).configure_promotions(uid, events)

## 死亡时由原生组件决定是否补引爆。
func death_language() -> void:
	bomb_component.judge_death_bomb()

