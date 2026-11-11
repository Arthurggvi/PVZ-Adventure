extends FixedBattleCardSlots
## 出战卡槽
class_name CardSlotBattle

## Fired once after a successful normal battle-card placement has paid its cost.
signal signal_card_committed(card: Card, consumed_resonance_free: bool)

@onready var curr_sun_value: Label = $SunLabelControl/CurrSunValue
@onready var marker_2d_sun_target: Marker2D = %Marker2DSunTarget

## 本局默认关闭的无冷却开关，开启时跳过用卡后的冷却。
var _cheat_no_cooldown := false

## 阳光值
var sun_value:
	set(value):
		sun_value = value
		curr_sun_value.text = str(value)

		for card in curr_cards:
			card.judge_sun_enough(value)

func _ready() -> void:
	Global.config_service.signal_change_disappear_spare_card_placeholder.connect(judge_disappear_add_card_bar)
	EventBus.subscribe("test_change_sun_value", func(value): sun_value = value)
	EventBus.subscribe("add_sun_value", func(value): sun_value+=value)
	EventBus.subscribe("update_card_purple_sun_cost", update_card_purple_sun_cost)


## 设置 [param sun] 初始阳光并按 [param capacity] 初始化出战卡槽，返回占位列表。
func init_card_slot_battle(capacity: int, sun: int) -> Array[Control]:
	self.sun_value = sun
	var slots: Array[Control] = _initialize_slots(capacity) # 基类按关卡配置创建占位。
	## 更新阳光收集位置
	EventBus.push_event("update_marker_2d_sun_target", marker_2d_sun_target)

	return slots

## 正式战斗时切换卡片上下文、检查费用并连接一次成功结算信号。
func main_game_refresh_card():
	update_card_purple_sun_cost()
	for card: Card in curr_cards: # 当前槽位中待启用战斗交互的卡片。
		if not AllCards.is_battle_card(card.card_reference):
			card.set_card_disable()
			continue
		card.card_context = Card.CardContext.Battle
		card.judge_sun_enough(sun_value)
		if not card.signal_card_use_end.is_connected(card_use_end):
			card.signal_card_use_end.connect(card_use_end)
	judge_disappear_add_card_bar()

## 下一轮重选前恢复选择上下文和冷却，解除本轮的使用结算。
func start_next_game_card_slot_battle_update():
	for card: Card in curr_cards: # 本轮保留、待恢复选卡交互的卡片。
		card.card_context = Card.CardContext.Selection
		## 卡牌冷却结束,可以点击
		card.set_card_cool_end()
		card.card_ready()
		if card.signal_card_use_end.is_connected(card_use_end):
			card.signal_card_use_end.disconnect(card_use_end)

## [param enabled] 为 true 时立即清空出战卡的剩余冷却，并重新检查费用与使用条件。
## 关闭时从下次用卡开始恢复正常计时。
func set_cheat_no_cooldown(enabled: bool) -> void:
	_cheat_no_cooldown = enabled
	if not enabled:
		return
	for card: Card in curr_cards: # 只刷新已经进入战斗交互的卡牌。
		if card.card_context == Card.CardContext.Battle:
			card.set_card_cool_end()
			card.judge_sun_enough(sun_value)

## [param card] 成功使用后扣除当前阳光价格，并根据无冷却开关决定是否开始计时。
func card_use_end(card:Card):
	sun_value = sun_value - card.sun_cost
	if not _cheat_no_cooldown:
		card.card_cool()
	if AdventureSession.owns_battle(Global.game_para):
		var consumed_free: bool = card.consume_adventure_cost_effects()
		card.judge_sun_enough(sun_value)
		signal_card_committed.emit(card, consumed_free)

#region 控制台相关
## 是否显示多余卡槽
func judge_disappear_add_card_bar():
	var hide_spare: bool = Global.main_game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and Global.config_service.disappear_spare_card_Placeholder # 选卡时展示配置容量。
	_set_spare_slots_hidden(hide_spare)

#endregion

## 植物数量变化一帧后刷新植物紫卡价格，普通僵尸及僵王不查询植物计数。
func update_card_purple_sun_cost():
	await get_tree().process_frame
	# 本次仍在槽中的卡片。
	for card: Card in curr_cards:
		if card.card_reference.card_type != ResourceCardReference.CardType.Plant:
			continue
		# 紫卡的植物内容编号，用于查询本关同种植物数量。
		var plant_type: int = card.card_reference.content_id
		if card.is_purple_card:
			var count: int = int(Global.main_game.plant_cell_manager.curr_plant_num.get(plant_type, 0))
			card.set_sun_surcharge(50 * maxi(0, count))
			card.judge_sun_enough(sun_value)
