## 金币掉落物：拾取后把 [member coin_value] 加到玩家金币上。
## 普通掉落继承 [BattlePickup] 的抛物线，首通奖励使用从上方落下的演出。
extends BattlePickup
class_name Coin

## 从屏幕上方加速落向落点的时间（真实秒）。
const SKY_FALL_SECONDS := 0.54
## 初次接触落点后轻弹上升的时间（真实秒）。
const SKY_REBOUND_UP_SECONDS := 0.08
## 从回弹最高点到最终停稳的时间（真实秒）。
const SKY_REBOUND_DOWN_SECONDS := 0.12

## 单枚金币的价值。
@export var coin_value := 50

## 首通钱堆的持久领取 ID，空值表示普通金币。
var first_clear_claim_id := ""
## 此枚首通钱币在钱堆存档中的面额键。
var first_clear_denomination := ""

## 从当前位置落到 [param landing]，在 [param rebound] 处轻弹后停稳；两点均为父节点局部坐标。
## [param delay] 为入场前等待的真实秒数，返回包含该延迟的演出总秒数。
## 暂停战斗时继续演出，停稳后恢复待机，供手动或奖杯拾取。
func fall_from_sky(landing: Vector2, rebound: Vector2, delay: float) -> float:
	var resting_scale: Vector2 = scale # 停稳后的显示比例。
	var resting_rotation: float = rotation # 停稳后恢复的初始角度（弧度）。
	var tilt: float = randf_range(-0.38, 0.38) # 进场时的倾斜角（弧度）。
	is_anim = false
	scale = resting_scale * 0.85
	rotation = resting_rotation + tilt
	tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	tween.tween_interval(delay)
	if not launch_sound.is_empty():
		tween.tween_callback(SoundManager.play_other_SFX.bind(launch_sound))
	tween.tween_property(self, ^"position", landing, SKY_FALL_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, ^"rotation", resting_rotation - tilt * 0.4, SKY_FALL_SECONDS)
	tween.parallel().tween_property(self, ^"scale", resting_scale, SKY_FALL_SECONDS)
	if not landing_sound.is_empty():
		tween.tween_callback(SoundManager.play_other_SFX.bind(landing_sound))
	tween.tween_property(self, ^"position", rebound, SKY_REBOUND_UP_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, ^"scale", resting_scale * Vector2(1.08, 0.92), SKY_REBOUND_UP_SECONDS)
	tween.tween_property(self, ^"position", landing, SKY_REBOUND_DOWN_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, ^"rotation", resting_rotation, SKY_REBOUND_DOWN_SECONDS)
	tween.parallel().tween_property(self, ^"scale", resting_scale, SKY_REBOUND_DOWN_SECONDS)
	tween.tween_callback(_finish_sky_drop)
	return delay + SKY_FALL_SECONDS + SKY_REBOUND_UP_SECONDS + SKY_REBOUND_DOWN_SECONDS

## 结束掉落补间并开启钱币场景自带的待机动画。
func _finish_sky_drop() -> void:
	tween = null
	is_anim = true

## 拾取入账：先扣除首通钱堆中的对应余量，再更新全局钱包。
func _grant() -> bool:
	if coin_value < 1 or Global.global_game_state.coin_value > PlantCardInstance.MAX_JSON_INTEGER - coin_value:
		return false
	if not first_clear_claim_id.is_empty() and not AdventureRewardService.take_first_clear_coin(
			_owner_state, first_clear_claim_id, first_clear_denomination):
		return false
	Global.global_game_state.coin_value += coin_value
	return true
