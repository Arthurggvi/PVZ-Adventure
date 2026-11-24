## 阳光菇的成功用卡与成熟回馈结算；复用现有提交链，不创建额外运行时管理器。
## 续种状态由各自的出战卡实例持有，普通到噩梦续战保持，离开战斗随卡释放。
extends RefCounted
class_name AdventureSunShroomCardEffects

## [param card] 已完成成功种植、扣费和冷却启动；[param slots] 是该卡所属的普通出战卡槽。
## [param consumed_followup] 为 true 时本次已消费续种，不能再次发放同一奖励。[br]
## 只修改实际提交的卡实例，同种植物的其他 UID 卡不共享优惠或冷却。
static func on_card_committed(card: Card, consumed_followup: bool, slots: CardSlotBattle) -> void:
	if consumed_followup or not is_instance_valid(card) or card.is_queued_for_deletion() \
			or not is_instance_valid(slots) or not slots.curr_cards.has(card):
		return
	if card.card_reference == null or card.card_reference.card_type != ResourceCardReference.CardType.Plant \
			or card.card_reference.content_id != CharacterRegistry.PlantType.P010SunShroom \
			or card.plant_spawn_profile == null:
		return
	var snapshot: Dictionary = card.plant_spawn_profile.snapshot() # 实际使用的冻结卡牌配方。
	var book: Dictionary = AdventurePromotionCatalog.definition(str(snapshot.get("promotion_2", ""))) # 二转书声明续种力度。
	for effect: Dictionary in book.get("effects", []): # 代谢的另一项效果由植株出生时应用。
		if effect.get("kind") != "card_followup_discount":
			continue
		var discount: int = int(effect.get("discount", 0)) # 下一次成功种植的固定阳光减免。
		if discount > 0:
			card.set_card_cool_end()
			card.arm_next_planting_discount_followup(discount)
			card.judge_sun_enough(slots.sun_value)
		return


## 将 [param slots] 中所有卡牌的当前剩余冷却减半，包含成熟阳光菇自己的来源卡。[br]
## 已就绪卡保持就绪；连续成熟逐次相乘，不改基础时长、遮罩最大值或关卡事件倍率。
static func halve_remaining_cooldowns(slots: CardSlotBattle) -> void:
	if not is_instance_valid(slots):
		return
	for card: Card in slots.curr_cards: # 所有独立出战卡都享受本次成熟收益，不按物种筛选。
		if is_instance_valid(card) and not card.is_queued_for_deletion():
			card.adventure_multiply_remaining_cooldown(0.5)
