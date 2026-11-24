## Enhancement success, protection and failure rules. Battle growth is a separate catalog.
extends RefCounted
class_name AdventureEnhancementRules

const COST := 500
const MAX_STARS := PlantCardInstance.MAX_STARS
const MAX_MATERIAL_CARDS := 3
## 强化后必须至少留一张的植物及其提示，按提示优先级排列。
const PROTECTED_MATERIAL_PLANTS: Dictionary[int, String] = {
	CharacterRegistry.PlantType.P002SunFlower: "请至少保留一个向日葵",
	CharacterRegistry.PlantType.P017LilyPad: "请至少保留一片荷叶",
}
const FERTILIZERS := ["fertilizer_lv1", "fertilizer_lv2", "fertilizer_lv3",
	"fertilizer_lv4", "fertilizer_lv5"]
## 生长剂等级由道具注册表统一维护，不参与肥料倍率计算。
const GROWTH_AGENTS := ItemRegistry.GROWTH_AGENT_IDS
const BASE_RATE := 0.08
const BASE_STAR_COEFFICIENT := 0.65
const BASE_EXPONENT := 1.5
const FODDER_RATE := 0.85
const HIGH_STAR_PENALTY := 0.26
const HIGH_STAR_START := 4
const FODDER_EXPONENT := 2.0
const HIGHER_STAR_BONUS := 0.08
const HIGHER_STAR_CAP := 1.32
const LOW_COST_MULTIPLIER := 0.95
const HIGH_COST_MULTIPLIER := 1.05
## 原始阳光费用落在含端点的区间内时，耗材费用系数为 1。
const STANDARD_SUN_COST_MIN := 100
## 原始阳光费用高于此值的耗材使用高费用系数。
const STANDARD_SUN_COST_MAX := 200
## 耗材最多能比主卡低两星，高星耗材不受此限制。
const MAX_LOWER_STAR_GAP := 2
## 比主卡低一星的耗材系数。
const ONE_STAR_BELOW_MULTIPLIER := 0.70
## 比主卡低两星的耗材系数。
const TWO_STARS_BELOW_MULTIPLIER := 0.35
## 从此主卡星级起，无保护的强化失败会降一星。
const STAR_LOSS_START := 4
## 目标星级从 1 星至此值只需一个保育花盆，此后每提高一星用量翻倍。
const POT_SINGLE_MAX_STAR := 4

static func protection_count(target_star: int) -> int:
	if target_star < 1 or target_star > MAX_STARS:
		return 0
	return 1 << maxi(0, target_star - POT_SINGLE_MAX_STAR)

## 校验 [param state] 中的主卡 [param main_uid] 和本次用作耗材的 [param material_uids]。
## 选为耗材的受保护物种在本次扣除后必须至少剩一张。
## [param use_pot] 表示使用花盆。[param fertilizer_id] 和 [param growth_agent_id] 为空时跳过对应道具。
## 校验通过返回空字符串，否则返回供界面展示的原因。
static func validate(state: AdventureState, main_uid: String, material_uids: Array,
		use_pot: bool, fertilizer_id: String, growth_agent_id: String = "") -> String:
	var main: PlantCardInstance = state.cards.get(main_uid) # 用当前主卡的星级校验可用耗材和保护道具。
	if main == null:
		return "请选择主卡。"
	if main.stars < 0 or main.stars >= MAX_STARS:
		return "主卡已达到星级上限。"
	if material_uids.is_empty() or material_uids.size() > MAX_MATERIAL_CARDS:
		return "请选择一至三张耗材卡。"
	var seen: Dictionary = {} # 已校验的耗材 UID，用于去重并预检耗材被扣除后的库存。
	var consumed_types: Dictionary[int, bool] = {} # 只检查本次选作耗材的物种是否有剩余。
	var invalid_star_gap: bool = false # 保留库存的提示在星差提示之前判断。
	for uid: Variant in material_uids: # 按独立 UID 验证每张选入的耗材卡。
		if typeof(uid) != TYPE_STRING or uid == main_uid or seen.has(uid):
			return "耗材卡不能重复，也不能是主卡。"
		seen[uid] = true
		var card: PlantCardInstance = state.cards.get(uid) # 点击和提交均使用当前背包中的卡实例。
		if card == null:
			return "耗材卡已不存在。"
		consumed_types[card.plant_type] = true
		invalid_star_gap = invalid_star_gap or main.stars - card.stars > MAX_LOWER_STAR_GAP
	for plant_type: int in PROTECTED_MATERIAL_PLANTS: # 同时触发保护时按声明顺序提示。
		if consumed_types.has(plant_type) and not _has_remaining_plant(state, seen, plant_type):
			return PROTECTED_MATERIAL_PLANTS[plant_type]
	if invalid_star_gap:
		return "主卡比耗材卡高三星及以上，该耗材无效。"
	if use_pot and int(state.items.get("seedling_pot", 0)) < protection_count(main.stars + 1):
		return "育苗花盆不足。"
	if not fertilizer_id.is_empty() and not FERTILIZERS.has(fertilizer_id):
		return "肥料种类无效。"
	if not fertilizer_id.is_empty() and int(state.items.get(fertilizer_id, 0)) < 1:
		return "肥料不足。"
	if not growth_agent_id.is_empty():
		if not GROWTH_AGENTS.has(growth_agent_id):
			return "生长剂种类无效。"
		if not growth_agent_matches(main.stars, growth_agent_id):
			return "当前主卡为%d星，生长剂仅适用于对应的0至4星主卡。" % main.stars
		if int(state.items.get(growth_agent_id, 0)) < 1:
			return "生长剂不足。"
	return ""

## 如果 [param state] 中有未列入 [param consumed_uids] 的 [param plant_type] 卡，返回 true。
static func _has_remaining_plant(state: AdventureState, consumed_uids: Dictionary, plant_type: int) -> bool:
	for uid: String in state.cards: # 主卡与未选入耗材槽的卡都属于保留库存。
		var card: PlantCardInstance = state.cards[uid] # 转职和星级不改变卡牌的物种。
		if card != null and card.plant_type == plant_type and not consumed_uids.has(uid):
			return true
	return false

## [param main_star] 为强化前的星级；仅与其相差一级的 [param growth_agent_id] 生效。
static func growth_agent_matches(main_star: int, growth_agent_id: String) -> bool:
	if main_star < 0 or main_star >= GROWTH_AGENTS.size():
		return false
	return GROWTH_AGENTS[main_star] == growth_agent_id

## Same pure probability for display and transaction; null means invalid configuration.
## Always use the plant registry's ORIGINAL sun cost, never battle-time cost modifiers.
static func success_probability(main: PlantCardInstance,
		material_cards: Array[PlantCardInstance], fertilizer_id: String,
		growth_agent_id: String = "") -> Variant:
	if main == null or main.stars < 0 or main.stars >= MAX_STARS \
			or material_cards.is_empty() or material_cards.size() > MAX_MATERIAL_CARDS:
		return null
	var multiplier: float = fertilizer_multiplier(fertilizer_id)
	if multiplier <= 0.0:
		return null
	if not growth_agent_id.is_empty() and not growth_agent_matches(main.stars, growth_agent_id):
		return null
	var total_weight := 0.0
	for card: PlantCardInstance in material_cards:
		if card == null or card == main or main.stars - card.stars > MAX_LOWER_STAR_GAP:
			return null
		var info: Dictionary = CharacterRegistry.PlantInfo.get(card.plant_type, {})
		if not info.has(CharacterRegistry.PlantInfoAttribute.SunCost):
			return null
		var cost: int = int(info[CharacterRegistry.PlantInfoAttribute.SunCost])
		var tier_weight := 1.0
		if cost < STANDARD_SUN_COST_MIN:
			tier_weight = LOW_COST_MULTIPLIER
		elif cost > STANDARD_SUN_COST_MAX:
			tier_weight = HIGH_COST_MULTIPLIER
		var star_gap: int = main.stars - card.stars
		var star_weight := 1.0
		if star_gap == 1:
			star_weight = ONE_STAR_BELOW_MULTIPLIER
		elif star_gap == 2:
			star_weight = TWO_STARS_BELOW_MULTIPLIER
		elif star_gap < 0:
			star_weight = minf(1.0 + (-star_gap) * HIGHER_STAR_BONUS, HIGHER_STAR_CAP)
		total_weight += tier_weight * star_weight
	# 已验证全部耗材后应用保底；非法耗材不得绕过原概率规则。
	if not growth_agent_id.is_empty():
		return 1.0
	return clampf((base_probability(main.stars) + material_bonus(main.stars, total_weight)) * multiplier, 0.0, 1.0)

## 返回当前主卡 [param main_star] 强化时的基础概率，供实际结算和规则表共用。
static func base_probability(main_star: int) -> float:
	return BASE_RATE / pow(1.0 + BASE_STAR_COEFFICIENT * float(main_star), BASE_EXPONENT)

## 返回 [param main_star] 和耗材 [param total_weight] 对应的概率加成，尚未应用肥料倍率。
static func material_bonus(main_star: int, total_weight: float) -> float:
	var excess: float = maxf(0.0, float(main_star) - HIGH_STAR_START) # 仅对超过门槛的星级应用衰减。
	var penalty: float = exp(-HIGH_STAR_PENALTY * pow(excess, BASE_EXPONENT)) # 高星主卡获得较少的耗材加成。
	return FODDER_RATE * penalty * pow(total_weight / MAX_MATERIAL_CARDS, FODDER_EXPONENT)

## Invalid fertilizer IDs are rejected, rather than silently treated as no fertilizer.
static func fertilizer_multiplier(fertilizer_id: String) -> float:
	if fertilizer_id.is_empty():
		return 1.0
	var index := FERTILIZERS.find(fertilizer_id)
	return 0.0 if index < 0 else 1.1 + 0.1 * float(index)

static func result_star(before: int, success: bool, protected: bool) -> int:
	if success:
		return mini(MAX_STARS, before + 1)
	if before >= STAR_LOSS_START and not protected:
		return before - 1
	return before
