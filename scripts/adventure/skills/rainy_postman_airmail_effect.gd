## 雨季邮差从当前玩家背包抽样，把冻结的免费临时卡交给本阶段派送。
extends CharacterSkillEffect

## 每次派送恰好准备三张独立卡片。
const CARD_COUNT: int = 3
## 仅在邮差技能资源被加载时解析表现脚本。
const Delivery = preload("res://scripts/adventure/skills/rainy_postman_delivery.gd")

## [param context] 必须仍属于有效战斗且能容纳卡片派送。
func can_execute(context: CharacterSkillContext) -> bool:
	return context != null and context.is_active() and is_instance_valid(context.game.canvas_layer_ui) \
		and is_instance_valid(context.game.card_manager)

## 用 [param context] 捕获当前背包的三份奖励。空背包或准备失败时保留技能。
func execute(context: CharacterSkillContext) -> bool:
	var source: RepeaterShotContext = context.state_source() # 绑定卡片飞行与本阶段的交互边界。
	if source == null:
		return false
	var pool: Array[Dictionary] = _best_species() # 每票只按物种参与一次，不按同种实例数加权。
	if pool.is_empty():
		return false
	var remaining: Array[Dictionary] = pool.duplicate() # 抽空才开始下一轮，确保先尽量抽不同物种。
	var cards: Array[Card] = [] # 三张都能创建才接纳本次演出。
	var random := RandomNumberGenerator.new() # 选卡与掉落动画独立于自然波次。
	for _index: int in range(CARD_COUNT): # 每次抽到的配方复制为独立卡片实例。
		if remaining.is_empty():
			remaining.assign(pool)
		var snapshot: Dictionary = remaining.pop_at(random.randi_range(0, remaining.size() - 1)) # 采用该物种最高星的首张卡。
		var profile: PlantSpawnProfile = AdventureBattleAdapter.delivery_profile_for(snapshot) # 转职和增星一次冻结。
		var reference: ResourceCardReference = ResourceCardReference.create(ResourceCardReference.CardType.Plant, int(snapshot["plant_type"])) # 真实植物模板。
		var card: Card = AllCards.create_card(reference) if profile != null else null # 飞行期间使用目录态，落地前不会响应种植。
		if card == null:
			for prepared: Card in cards: # 原子撤回尚未入树的半批卡片。
				prepared.free()
			return false
		card.is_free_temporary = true
		card.plant_spawn_profile = profile
		cards.append(card)
	var delivery := Delivery.new() # 一次动画管理三张真实卡及阶段回收。
	delivery.configure(source, cards, random)
	context.game.canvas_layer_ui.add_child(delivery)
	context.game.canvas_layer_ui.move_child(delivery, 0)
	return true

## 返回每种可出战植物的最高星快照；并列时按背包当前顺序确定来源。
func _best_species() -> Array[Dictionary]:
	var best: Dictionary[int, Dictionary] = {} # 只读背包快照，跳过未注册卡面。
	for snapshot: Dictionary in Global.adventure_inventory.list_cards(): # 每个字典与库存实体分离。
		if snapshot.is_empty():
			continue
		var species: int = int(snapshot["plant_type"]) # 以物种而非背包 UID 去重。
		var previous: Dictionary = best.get(species, {}) # 目前保留的最高星同种卡。
		if not previous.is_empty() and int(previous["stars"]) >= int(snapshot["stars"]):
			continue
		var reference: ResourceCardReference = ResourceCardReference.create(ResourceCardReference.CardType.Plant, species) # 资格只查目录索引。
		if AllCards.is_battle_card(reference):
			best[species] = snapshot
	var result: Array[Dictionary] = [] # 类型明确，供施放时复制抽样名单。
	result.assign(best.values())
	return result
