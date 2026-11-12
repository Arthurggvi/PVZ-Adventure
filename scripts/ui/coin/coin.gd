## 金币掉落物：拾取后把 [member coin_value] 加到玩家金币上。
## 抛出、落地、超时与收集表现全部继承自 [BattlePickup]。
extends BattlePickup
class_name Coin

## 单枚金币的价值。
@export var coin_value := 50

## 首通钱堆的持久领取 ID，空值表示普通金币。
var first_clear_claim_id := ""
## 此枚首通钱币在钱堆存档中的面额键。
var first_clear_denomination := ""

## 拾取入账：先扣除首通钱堆中的对应余量，再更新全局钱包。
func _grant() -> bool:
	if coin_value < 1 or Global.global_game_state.coin_value > PlantCardInstance.MAX_JSON_INTEGER - coin_value:
		return false
	if not first_clear_claim_id.is_empty() and not AdventureRewardService.take_first_clear_coin(
			_owner_state, first_clear_claim_id, first_clear_denomination):
		return false
	Global.global_game_state.coin_value += coin_value
	return true
