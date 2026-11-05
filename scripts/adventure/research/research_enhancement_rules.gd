## Enhancement contracts. Probability and star-derived battle bonuses intentionally unimplemented.
extends RefCounted
class_name AdventureEnhancementRules

const COST := 500
const MAX_STARS := PlantCardInstance.MAX_STARS
const MAX_MATERIAL_CARDS := 3
const FERTILIZERS := ["fertilizer_lv1", "fertilizer_lv2", "fertilizer_lv3",
	"fertilizer_lv4", "fertilizer_lv5"]

static func protection_count(target_star: int) -> int:
	if target_star < 1 or target_star > MAX_STARS:
		return 0
	return 1 << maxi(0, target_star - 4)

static func validate(state: AdventureState, main_uid: String, material_uids: Array,
		use_pot: bool, fertilizer_id: String) -> String:
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
	return ""

## Future RNG implementation must supply one computed probability to both UI and settlement.
static func success_probability(_main: PlantCardInstance, _consumed: Array,
		_fertilizer_id: String) -> Variant:
	return null

static func result_star(before: int, success: bool, protected: bool) -> int:
	if success:
		return mini(MAX_STARS, before + 1)
	if before >= 4 and not protected:
		return before - 1
	return before

## Future per-star battle attributes are intentionally absent, not fabricated.
static func stat_modifiers(_stars: int) -> Dictionary:
	return {}
