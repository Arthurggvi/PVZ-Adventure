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
## 回旋镖书目由单次投掷快照约束成长、回收补投与反向分裂。
const BloomerangBooks = preload("res://scripts/adventure/research/research_bloomerang_promotion_books.gd")
## 双发书目声明互斥弹种，额外发数由原株私有动画轨道统一派发。
const RepeaterBooks = preload("res://scripts/adventure/research/research_repeater_promotion_books.gd")
## 寒冰射手的命中与派生规则由单株出战配置冻结。
const SnowPeaBooks = preload("res://scripts/adventure/research/research_snow_pea_promotion_books.gd")
## 电能豌豆书目由原生离手入口和单株光环共用。
const ElectricPeaBooks = preload("res://scripts/adventure/research/research_electric_pea_promotion_books.gd")
## 火爆辣椒的费用与引爆分支使用同一份转职定义。
const JalapenoBooks = preload("res://scripts/adventure/research/research_jalapeno_promotion_books.gd")
## 寒冰菇书目共用原版冰冻与自然波次调度。
const IceShroomBooks = preload("res://scripts/adventure/research/research_ice_shroom_promotion_books.gd")
## 缠绕海草书目复用种植事务和原生拖拽完成时点。
const TanglekelpBooks = preload("res://scripts/adventure/research/research_tanglekelp_promotion_books.gd")
## 魅惑菇书目由实际魅惑来源向友军转交战斗词条。
const HypnoBooks = preload("res://scripts/adventure/research/research_hypno_promotion_books.gd")
## 毁灭菇爆炸、弹坑与连锁均使用同一份转职书目。
const DoomBooks = preload("res://scripts/adventure/research/research_doom_promotion_books.gd")
## 窝瓜书目随种植事务冻结，原生落地和窝瓜王共用结算。
const SquashBooks = preload("res://scripts/adventure/research/research_squash_promotion_books.gd")
## 三线射手四阶与跨阶路线约束。
const ThreePeaterBooks = preload("res://scripts/adventure/research/research_threepeater_promotion_books.gd")
## 高坚果的护甲、代伤与爆炸防护按单株冻结。
const TallNutBooks = preload("res://scripts/adventure/research/research_tallnut_promotion_books.gd")
## 仙人掌升降、弹道及命中词条。
const CactusBooks = preload("res://scripts/adventure/research/research_cactus_promotion_books.gd")
## 杨桃流光需要先选贯穿。
const StarFruitBooks = preload("res://scripts/adventure/research/research_starfruit_promotion_books.gd")
## 卷心菜的投掷批次与彩色落点。
const CabbageBooks = preload("res://scripts/adventure/research/research_cabbage_promotion_books.gd")
## 玉米投手的粒弹、黄油及出手时钟。
const CornBooks = preload("res://scripts/adventure/research/research_corn_promotion_books.gd")
## 西瓜投手的齐射、命中和列阵词条。
const MelonBooks = preload("res://scripts/adventure/research/research_melon_promotion_books.gd")
## 全书目只在类初始化时汇总一次；消费者仍使用原有BOOKS入口。
static var BOOKS: Dictionary = _build_books()

## 返回全部合法书目的深副本；重复ID报错，不覆盖已有定义。
static func _build_books() -> Dictionary:
	var books: Dictionary = ExistingBooks.BOOKS.duplicate(true) # 汇总结果不共享定义模块内部字典。
	for module: Dictionary in [PuffBooks.BOOKS, SunShroomBooks.BOOKS, ScaredyBooks.BOOKS, FumeBooks.BOOKS, LilyBooks.BOOKS, CoffeeBooks.BOOKS, BloomerangBooks.BOOKS, RepeaterBooks.BOOKS, SnowPeaBooks.BOOKS, ElectricPeaBooks.BOOKS, JalapenoBooks.BOOKS, IceShroomBooks.BOOKS, TanglekelpBooks.BOOKS, HypnoBooks.BOOKS, DoomBooks.BOOKS, SquashBooks.BOOKS, ThreePeaterBooks.BOOKS, TallNutBooks.BOOKS, CactusBooks.BOOKS, StarFruitBooks.BOOKS, CabbageBooks.BOOKS, CornBooks.BOOKS, MelonBooks.BOOKS]: # 新物种沿用统一的重复ID检查。
		for id: String in module: # 稳定技能书ID也是存档中的选择值。
			if books.has(id):
				push_error("重复的转职书ID：%s" % id)
				continue
			books[id] = module[id].duplicate(true)
	return books

## 返回 [param id] 对应的现行书目 ID；旧阳光菇续种分支归入代谢强化。
static func canonical_book_id(id: String) -> String:
	return "promotion_sunshroom_metabolism" if id == "promotion_sunshroom_buy_one" else id

## 返回 [param id] 的定义副本；未知ID返回空字典。
static func definition(id: String) -> Dictionary:
	return BOOKS.get(canonical_book_id(id), {}).duplicate(true)

## 检查下一阶或历史选择 [param book] 与 [param card] 较早的转职是否兼容。
static func is_compatible(card: PlantCardInstance, book: Dictionary) -> bool:
	var excluded: String = str(book.get("excludes", "")) # 声明后排斥较早选择的一个书目。
	var required: String = str(book.get("requires", "")) # 声明后必须已选择这一较早书目。
	if excluded.is_empty() and required.is_empty():
		return true
	var meets_requirement: bool = required.is_empty() # 无前置要求的旧书直接满足。
	for tier: int in range(1, int(book.tier)): # 兼容性只依赖先选的技能。
		var chosen: String = canonical_book_id(card.get_promotion(tier)) # 存档可能保留旧的别名。
		if not excluded.is_empty() and chosen == excluded:
			return false
		meets_requirement = meets_requirement or chosen == required
	return meets_requirement

## 验证 [param card] 的历史转职选择连续、物种正确且彼此兼容；不检查当前星级。
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
				or int(book.get("plant_type", 0)) != card.plant_type or not is_compatible(card, book):
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
		if int(book.tier) == tier and int(book.plant_type) == card.plant_type and is_compatible(card, book):
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
		var id: String = canonical_book_id(card.get_promotion(tier)) # 冻结快照中的旧分支也使用现行效果。
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
