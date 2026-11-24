extends FixedBattleCardSlots
## 出战卡槽
class_name CardSlotBattleCoin
## 赌狗小游戏金币卡槽

@onready var curr_coin_value: Label = $CoinLabelControl/CurrCoinValue

@onready var label_info: Label = $CoinLabelControl/LabelInfo
@onready var next_wave_timer: Timer = $NextWaveTimer

## 当前波次
var curr_wave:int=1
## 当前波点击卡片次数
var curr_wave_card_max:int=1
## 当前波剩余卡片次数
var curr_wave_card:int=1
## 当前雪人逃跑概率
var curr_p:float=0.1

var is_next_wave_refresh:=false
var is_end_wave:=false

func _ready() -> void:
	update_label_info()
	Global.main_game.p_yeti_run = curr_p
	Global.global_game_state.coin_value_changed.connect(func(_new_value: int): curr_coin_value.text = str(Global.global_game_state.coin_value))

func _process(_delta: float) -> void:
	if curr_wave_card <= 0 and not is_end_wave:
		for z:Zombie020Yeti in Global.main_game.zombie_manager.all_zombies_1d:
			if not z.is_run_end and not z.is_death:
				return

		print("雪人都跑路了或者死亡了")
		next_wave()


func update_label_info():
	if is_end_wave:
		label_info.text = "当前波次:"+"最后一搏"+"\n当前波次卡片:"+str(curr_wave_card)+"\n雪人逃跑概率:"+str(curr_p)
	else:
		label_info.text = "当前波次:"+str(curr_wave)+"\n当前波次卡片:"+str(curr_wave_card)+"\n雪人逃跑概率:"+str(curr_p)

## 初始化金币显示并创建 [param capacity] 个出战占位，返回占位列表。
func init_card_slot_battle(capacity: int) -> Array[Control]:
	curr_coin_value.text = str(Global.global_game_state.coin_value)
	return _initialize_slots(capacity)

## 切换为战斗交互并连接成功使用结算；僵王不能进入金币卡槽。
func main_game_refresh_card():
	for card: Card in curr_cards: # 当前槽位中待启用战斗交互的卡片。
		if not AllCards.is_battle_card(card.card_reference) or card.card_reference.card_type == ResourceCardReference.CardType.ZombieBoss:
			card.set_card_disable()
			continue
		card.card_context = Card.CardContext.Battle
		card.judge_sun_enough(int(Global.global_game_state.coin_value / 10.0))
		if not card.signal_card_use_end.is_connected(card_use_end):
			card.signal_card_use_end.connect(card_use_end)

## [param card] 成功使用后扣除金币与本波次数，保留金币卡槽的专用结算规则。
func card_use_end(card:Card):
	## 减少阳光，卡片冷却
	Global.global_game_state.coin_value = Global.global_game_state.coin_value - card.sun_cost * 10
	#card.card_cool()
	curr_coin_value.text = str(Global.global_game_state.coin_value)
	card.judge_sun_enough(int(Global.global_game_state.coin_value / 10.0))
	curr_wave_card -= 1
	if curr_wave_card == 0:
		card.set_card_disable()
		if not is_end_wave:
			next_wave_timer.start()
	else:
		card.set_card_cool_time_start_cool(0)

	update_label_info()

func next_wave():
	print("刷新下一波")
	curr_wave += 1
	if curr_wave == 10:
		is_end_wave = true
	curr_wave_card_max += 1
	curr_wave_card = curr_wave_card_max
	if curr_p<=0.2:
		curr_p += 0.1
	elif curr_p<=0.4:
		curr_p += 0.05
	elif curr_p<=0.5:
		curr_p += 0

	Global.main_game.p_yeti_run = curr_p
	next_wave_timer.stop()
	curr_cards[0].set_card_cool_time_start_cool(0)
	EventBus.push_event("replenish_lawn_mover")
	update_label_info()
	if curr_wave == 10:
		EventBus.push_event("end_wave_zombie")

func _on_next_wave_timer_timeout() -> void:
	next_wave()
	print("时间到,刷新下一波")

## 每秒触发刷新小推车
func _on_replenish_lawn_mover_timer_timeout() -> void:
	EventBus.push_event("replenish_lawn_mover")
