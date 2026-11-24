## 预选卡先冻结真实身份，再按预算放置；免槽卡与普通卡共用同一完整路径。
extends RefCounted
class_name CardPreselectedSetup

## [param battle] 为真实出战卡栏，[param candidates] 提供对应候选身份。
## [param references] 保持冻结卡组的原顺序，[param place_card] 接收卡片和已确认的显示位。
static func populate(battle: CardSlotBattle, candidates: CardSlotCandidate,
		references: Array[ResourceCardReference], place_card: Callable) -> void:
	for index: int in range(references.size()): # 原下标用于绑定冻结 UID，失败卡不能让后续身份错位。
		var reference: ResourceCardReference = references[index] # 一条引用对应一张实际卡片。
		if not AllCards.is_battle_card(reference):
			push_error("CardSlotNorm：预选卡必须是已注册的出战卡牌。")
			continue
		var card: Card = AllCards.create_card(reference, Card.CardContext.Selection) # 独立出战实例。
		if card == null:
			continue
		if AdventureSession.owns_battle(Global.game_para) and not AdventureSession.is_stage_preview:
			var build: Dictionary = AdventureSession.get_prechosen_battle_data(index, reference) # 先匹配本卡 UID。
			card.plant_spawn_profile = AdventureBattleAdapter.profile_for(build)
			if card.plant_spawn_profile == null:
				push_error("冒险预选卡 UID 与卡槽模板不匹配，取消本卡绑定。")
				card.free()
				continue
		var slot: Control = battle.append_card(card) # 完整配置已经绑定，此时才能判断是否免槽。
		if slot == null:
			card.free()
			continue
		var container: CardCandidateContainer = _candidate(candidates, card) # 同种多张卡按实际 UID 区分。
		if container != null:
			container.card.visible = false
			container.card.is_choosed_pre_card = true
		place_card.call(card, slot)
		if reference.is_imitater:
			candidates.imitater_be_choosed()

## 为 [param card] 在 [param candidates] 中找回对应身份，不使用同物种的其他冒险卡。
static func _candidate(candidates: CardSlotCandidate, card: Card) -> CardCandidateContainer:
	if AdventureSession.owns_battle(Global.game_para) and not AdventureSession.is_stage_preview:
		return candidates.get_adventure_candidate(str(card.battle_card_data.get("uid", "")))
	return candidates.get_candidate(card.card_reference)
