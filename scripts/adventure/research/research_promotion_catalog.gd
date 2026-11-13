## 转职书的唯一查询与效果解析入口；每阶二选一，已有选择不可逆。
extends RefCounted
class_name AdventurePromotionCatalog

## 所有转职统一收取的金币费用。
const COST := 5000
## 一至四转所需的最低星级；已有转职不会随星级降低而丢失。
const REQUIREMENTS := [5, 7, 9, 10]
## 已有物种的定义模块，不改变既有稳定ID及技能数值。
const ExistingBooks = preload("res://scripts/adventure/research/research_existing_promotion_books.gd")
## 小喷菇的定义模块，与既有书目共同组成同一查询目录。
const PuffBooks = preload("res://scripts/adventure/research/research_puff_promotion_books.gd")
## 阳光菇的定义模块，沿用相同的转职校验与物品展示入口。
const SunShroomBooks = preload("res://scripts/adventure/research/research_sunshroom_promotion_books.gd")
## 胆小菇的定义模块，共享与原生词条均从相同冻结选择解析。
const ScaredyBooks = preload("res://scripts/adventure/research/research_scaredy_promotion_books.gd")
## 大喷菇的定义模块，状态效果由统一负面入口登记。
const FumeBooks = preload("res://scripts/adventure/research/research_fume_promotion_books.gd")
## 睡莲书目由承托与选卡容量共用冻结属性。
const LilyBooks = preload("res://scripts/adventure/research/research_lily_promotion_books.gd")
## 咖啡豆书目由种植事务冻结目标并结算使用结果。
const CoffeeBooks = preload("res://scripts/adventure/research/research_coffee_promotion_books.gd")
## 全书目只在类初始化时汇总一次；消费者仍使用原有BOOKS入口。
static var BOOKS: Dictionary = _build_books()

## 返回全部合法书目的深副本；重复ID报错，不覆盖已有定义。
static func _build_books() -> Dictionary:
	var books: Dictionary = ExistingBooks.BOOKS.duplicate(true) # 汇总结果不共享定义模块内部字典。
	for module: Dictionary in [PuffBooks.BOOKS, SunShroomBooks.BOOKS, ScaredyBooks.BOOKS, FumeBooks.BOOKS, LilyBooks.BOOKS, CoffeeBooks.BOOKS]: # 新物种沿用统一的重复ID检查。
		for id: String in module: # 稳定技能书ID也是存档中的选择值。
			if books.has(id):
				push_error("重复的转职书ID：%s" % id)
				continue
			books[id] = module[id].duplicate(true)
	return books

## 返回 [param id] 的定义副本；未知ID返回空字典。
static func definition(id: String) -> Dictionary:
	return BOOKS.get(id, {}).duplicate(true)

## 验证 [param card] 的历史转职选择是否连续且属于本物种；不检查当前星级。
static func is_valid_chain(card: PlantCardInstance) -> bool:
	if card == null:
		return false
	var gap := false # 已出现空阶后，不允许再出现更高阶的选择。
	for tier: int in range(1, 5): # 按一至四转验证冻结选择。
		var book_id := card.get_promotion(tier) # 当前阶的稳定技能书ID。
		if book_id.is_empty():
			gap = true
			continue
		var book: Dictionary = definition(book_id) # 未注册或物种错误的书不能进入战斗。
		if gap or book.is_empty() or int(book.get("tier", 0)) != tier \
				or int(book.get("plant_type", 0)) != card.plant_type:
			return false
	return true

## 返回 [param card] 的下一转阶数；无效卡牌或已完成四转时返回0。
static func next_tier(card: PlantCardInstance) -> int:
	if not is_valid_chain(card):
		return 0
	for tier: int in range(1, 5): # 第一处尚未选择的合法阶数。
		if card.get_promotion(tier).is_empty():
			return tier
	return 0

## 返回 [param card] 下一阶可用书目的副本，供研究室展示和事务校验共用。
static func options(card: PlantCardInstance) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 返回独立副本，避免UI改写权威配置。
	var tier := next_tier(card) # 仅展示当前可选择的阶数。
	if tier == 0:
		return result
	for id: String in BOOKS: # 所有物种统一从同一目录取选项。
		var book: Dictionary = BOOKS[id] # 当前候选书的只读定义。
		if int(book.tier) == tier and int(book.plant_type) == card.plant_type:
			var entry := definition(id) # 补入ID供研究事务提交。
			entry["id"] = id
			result.append(entry)
	return result

## 汇总 [param card] 已选技能：基础加成先加算，再应用最终倍率或固定值。
static func effects(card: PlantCardInstance) -> Dictionary:
	var stats: Dictionary = {} # 按属性名称聚合固定值与百分比。
	var events: Array[Dictionary] = [] # 非数值技能保留完整参数及选择顺序。
	if not is_valid_chain(card):
		return {"stats": stats, "events": events}
	for tier: int in range(1, 5): # 每阶最多消费一个合法技能。
		var id := card.get_promotion(tier) # 当前阶的已选书目。
		if not BOOKS.has(id):
			continue
		for effect: Dictionary in BOOKS[id].effects: # 单本书可同时授予属性与事件。
			if effect.kind != "stat":
				events.append(effect.duplicate(true))
				continue
			var stat: String = effect.stat # 属性键与出生修饰器保持一致。
			var aggregate: Dictionary = stats.get(stat, {"flat": 0.0, "percent": 0.0}) # 同属性累计值。
			aggregate.flat += float(effect.get("flat", 0.0))
			aggregate.percent += float(effect.get("percent", 0.0))
			if effect.has("final_multiplier"):
				aggregate["final_multiplier"] = float(aggregate.get("final_multiplier", 1.0)) * maxf(0.0, float(effect.final_multiplier))
			if effect.has("fixed"):
				aggregate["fixed"] = float(effect.fixed)
			stats[stat] = aggregate
	return {"stats": stats, "events": events}

## 用 [param modifier] 调整 [param base]：先加算、后乘最终倍率，固定值覆盖结果；最低为0。
static func resolve_stat(base: float, modifier: Dictionary) -> float:
	if modifier.has("fixed"):
		return maxf(0.0, float(modifier.fixed))
	var scaled: float = base * (1.0 + float(modifier.get("percent", 0.0))) + float(modifier.get("flat", 0.0)) # 保留旧属性的加算顺序。
	return maxf(0.0, scaled * float(modifier.get("final_multiplier", 1.0)))
