## 金币掉落物：拾取后把 [member coin_value] 加到玩家金币上。
## 抛出、落地、超时与收集表现全部继承自 [BattlePickup]。
extends BattlePickup
class_name Coin

## 单枚金币的价值。
@export var coin_value := 50

## 拾取入账：金币直接加到全局金币。
func _grant() -> bool:
	if coin_value < 1 or Global.global_game_state.coin_value > PlantCardInstance.MAX_JSON_INTEGER - coin_value:
		return false
	Global.global_game_state.coin_value += coin_value
	return true
