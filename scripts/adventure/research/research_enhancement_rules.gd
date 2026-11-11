## Enhancement success, protection and failure rules. Battle growth is a separate catalog.
extends RefCounted
class_name AdventureEnhancementRules

const COST := 500
const MAX_STARS := PlantCardInstance.MAX_STARS
const MAX_MATERIAL_CARDS := 3
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

static func protection_count(target_star: int) -> int:
	if target_star < 1 or target_star > MAX_STARS:
		return 0
	return 1 << maxi(0, target_star - 4)

## 校验主卡、耗材与所选的所有消耗道具；保底道具仅适用目标升星等级。
static func validate(state: AdventureState, main_uid: String, material_uids: Array,
		use_pot: bool, fertilizer_id: String, growth_agent_id: String = "") -> String:
	var main: PlantCardInstance = state.cards.get(main_uid)
	if main == null:
		return "请选择主卡。"
	if main.stars < 0 or main.stars >= MAX_STARS:
		return "主卡已达到星级上限。"
	if material_uids.is_empty() or material_uids.size() > MAX_MATERIAL_CARDS:
		return "请选择一至三张耗材卡。"
	var seen: Dictionary = {}
	for uid: Variant in material_uids:
		if typeof(uid) != TYPE_STRING or uid == main_uid or seen.has(uid):
			return "耗材卡不能重复，也不能是主卡。"
		seen[uid] = true
		var card: PlantCardInstance = state.cards.get(uid)
		if card == null:
			return "耗材卡已不存在。"
		if main.stars - card.stars >= 3:
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
		if card == null or card == main or main.stars - card.stars >= 3:
			return null
		var info: Dictionary = CharacterRegistry.PlantInfo.get(card.plant_type, {})
		if not info.has(CharacterRegistry.PlantInfoAttribute.SunCost):
			return null
		var cost: int = int(info[CharacterRegistry.PlantInfoAttribute.SunCost])
		var tier_weight := 1.0
		if cost < 100:
			tier_weight = LOW_COST_MULTIPLIER
		elif cost > 200:
			tier_weight = HIGH_COST_MULTIPLIER
		var star_gap: int = main.stars - card.stars
		var star_weight := 1.0
		if star_gap == 1:
			star_weight = 0.70
		elif star_gap == 2:
			star_weight = 0.35
		elif star_gap < 0:
			star_weight = minf(1.0 + (-star_gap) * HIGHER_STAR_BONUS, HIGHER_STAR_CAP)
		total_weight += tier_weight * star_weight
	# 已验证全部耗材后应用保底；非法耗材不得绕过原概率规则。
	if not growth_agent_id.is_empty():
		return 1.0
	var s: float = float(main.stars)
	var base := BASE_RATE / pow(1.0 + BASE_STAR_COEFFICIENT * s, BASE_EXPONENT)
	var penalty := exp(-HIGH_STAR_PENALTY * pow(maxf(0.0, s - HIGH_STAR_START), BASE_EXPONENT))
	var fodder := FODDER_RATE * penalty * pow(total_weight / MAX_MATERIAL_CARDS, FODDER_EXPONENT)
	return clampf((base + fodder) * multiplier, 0.0, 1.0)

## Invalid fertilizer IDs are rejected, rather than silently treated as no fertilizer.
static func fertilizer_multiplier(fertilizer_id: String) -> float:
	if fertilizer_id.is_empty():
		return 1.0
	var index := FERTILIZERS.find(fertilizer_id)
	return 0.0 if index < 0 else 1.1 + 0.1 * float(index)

static func result_star(before: int, success: bool, protected: bool) -> int:
	if success:
		return mini(MAX_STARS, before + 1)
	if before >= 4 and not protected:
		return before - 1
	return before
