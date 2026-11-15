## 图书馆纯规则：概率、价格、材料限制与候选书目，不修改玩家资产。
extends RefCounted

## 转职技能书唯一来源。
const Books = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
## 四阶售价，索引为等阶减一。
const PRICES: Array[int] = [10000, 30000, 60000, 100000]
## 千分位整数权重，避免浮点概率边界误差。
const WEIGHTS: Array[int] = [395, 276, 194, 135]
## 每批固定书籍数。
const SHELF_SIZE := 5
## 整批换书金币费用。
const REFRESH_COST := 3000

## 返回 [param tier] 等阶的候选 ID；[param plant] 为零时不限物种，[param excluded] 排除投入书。
static func pool(tier: int, plant: int = 0, excluded: Array[String] = []) -> Array[String]:
	var result: Array[String] = [] # 从权威目录投影，未来新增物种无需登记第二份表。
	for id: String in Books.BOOKS: # 每个技能书 ID 在同阶内等概率。
		var book: Dictionary = Books.BOOKS[id] # 只读技能定义。
		if int(book.tier) == tier and (plant == 0 or int(book.plant_type) == plant) and id not in excluded:
			result.append(id)
	return result

## 将 [param roll] 的 0..999 均匀整数映射到一至四阶；范围外返回零。
static func tier_for_roll(roll: int) -> int:
	if roll < 0 or roll >= 1000:
		return 0
	var boundary := 0 # 当前累积权重上界，不包含边界本身。
	for index: int in WEIGHTS.size(): # 各阶区间互斥并完整覆盖一千种取值。
		boundary += WEIGHTS[index]
		if roll < boundary:
			return index + 1
	return 0

## 使用 [param rng] 独立抽取五个货位；目录缺阶时返回空列表，不能收取刷新费。
static func draw_shelf(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 同一种书允许出现在不同货位，各自限购一本。
	for slot: int in SHELF_SIZE: # 每个货位独立抽阶与技能。
		var candidates: Array[String] = pool(tier_for_roll(rng.randi_range(0, 999))) # 先抽阶，再在该阶均匀抽书。
		if candidates.is_empty():
			return []
		result.append({"id": candidates[rng.randi_range(0, candidates.size() - 1)], "sold": false})
	return result

## 校验 [param mode] 和完整材料 [param ids]；返回候选池或简短原因，不检查库存数量。
static func quote(mode: String, ids: Array[String]) -> Dictionary:
	if mode not in ["convert", "synthesize"]:
		return {"ready": false, "message": "未知操作"}
	var required: int = 2 if mode == "convert" else 3 # 转换两本，升阶三本。
	if ids.size() != required:
		return {"ready": false, "message": "选择 %d 本技能书" % required}
	var first: Dictionary = Books.definition(ids[0]) # 首本确定等阶与升阶时的物种。
	if first.is_empty():
		return {"ready": false, "message": "技能书已失效"}
	if mode == "synthesize" and int(first.tier) >= 4:
		return {"ready": false, "message": "四阶书无法合成"}
	for id: String in ids: # 同名书可重复投入，数量由服务统一累加校验。
		var book: Dictionary = Books.definition(id) # 拒绝未知、混阶及合成混物种。
		if book.is_empty() or book.tier != first.tier:
			return {"ready": false, "message": "请选择同等阶技能书"}
		if mode == "synthesize" and book.plant_type != first.plant_type:
			return {"ready": false, "message": "请选择同物种技能书"}
	var candidates: Array[String] = pool(int(first.tier), 0, ids) if mode == "convert" \
		else pool(int(first.tier) + 1, int(first.plant_type)) # 转换排除所有投入 ID，合成保留物种。
	return {"ready": not candidates.is_empty(), "message": "" if not candidates.is_empty() else "暂无可生成的技能书", "pool": candidates}
