## 寒冰菇的单次引信，统一触发原生特效和战场结算。
extends BombComponentBase
class_name BombComponentIce

## 原生全场冻结特效。
@onready var bomb_effect: BombEffectBase = $BombEffect

## 原生完全冻结秒数。
@export var time_ice:float = 3
## 原生解冻后的减速秒数。
@export var time_decelerate: float = 5

## 独立出战卡 UID，仅用于本卡和其他卡的冷却结算。
var _card_uid: String
## 出生时冻结的动态转职事件。
var _events: Array[Dictionary] = []

## 保存 [param uid] 及其 [param events]，供原生引爆唯一消费。
func configure_promotions(uid: String, events: Array[Dictionary]) -> void:
	_card_uid = uid
	_events = events.duplicate(true)

## 播放原生冻结特效。
func _start_bomb_fx() -> void:
	bomb_effect.activate_bomb_effect()

## 正式战场转职由同一次引爆结算；其余仍派发原生全场冻结。
func _bomb_all_enemy() -> void:
	if not _events.is_empty() and AdventureIceShroomCast.try_cast(owner as Plant015IceShroom,
			_card_uid, _events, time_ice, time_decelerate):
		return
	EventBus.push_event("ice_all_zombie", [time_ice, time_decelerate])
