## 初始园丁的卡槽刷新技能，沿用卡牌的冷却和可用性判定。
extends CharacterSkillEffect

## [param context] 必须属于可以施放技能的战斗且已装配卡槽。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active() and is_instance_valid(context.game.card_slot_root)

## 结束 [param context] 当前出战卡槽里的剩余冷却；至少刷新一张卡才提交施放。
func execute(context: CharacterSkillContext) -> bool:
	var refreshed: bool = false # 记录本次是否实际结束了卡牌冷却。
	for card: Card in context.game.card_slot_root.curr_cards: # 只遍历战斗快捷键使用的当前槽位名单。
		if not is_instance_valid(card) or card.is_queued_for_deletion() or card.card_context != Card.CardContext.Battle:
			continue
		if card.adventure_multiply_remaining_cooldown(0.0):
			refreshed = true
	return refreshed
