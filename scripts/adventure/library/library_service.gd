## 图书馆资产事务边界；同步重验、一次保存、失败回滚，界面不能直接改金币或背包。
extends RefCounted

## 价格、概率及配方的唯一规则。
const Rules = preload("res://scripts/adventure/library/library_rules.gd")
## 货架状态仅由事务替换。
const Stock = preload("res://scripts/adventure/library/library_stock.gd")
## 跨服务实例防止金币变化信号重入图书馆事务。
static var _committing := false
## 打开窗口时注入的档案对象。
var _state: AdventureState
## 同档库存服务，负责数量上限与道具合法性。
var _inventory: AdventureInventoryService
## 金币持有者，同时用于校验档案身份。
var _wallet: GlobalGameState
## 全局存档服务的同步保存回调。
var _persist: Callable
## 本机自然日回调，沿用日常任务时间口径。
var _clock: Callable
## 本服务专用随机源，不修改全局随机种子。
var _rng := RandomNumberGenerator.new()

## [param state]、[param inventory]、[param wallet] 必须属于同一档案；[param persist] 返回保存是否成功。
## [param clock] 可替换自然日来源，默认与日常任务一致。
func _init(state: AdventureState, inventory: AdventureInventoryService, wallet: GlobalGameState,
		persist: Callable, clock: Callable = AdventureQuestService.today) -> void:
	_state = state
	_inventory = inventory
	_wallet = wallet
	_persist = persist
	_clock = clock
	_rng.randomize()

## 返回当前档案的货架副本，调用者只能凭版本提交操作。
func shelf() -> Dictionary:
	return _state.library.to_dict()

## 首次进入或跨日免费换书，时间倒退保持已有货架；写盘失败不展示未保存结果。
func ensure_today() -> Dictionary:
	return _run("daily")

## 付费刷新 [param revision] 对应货架；旧版本或跨日请求拒绝扣费。
func refresh(revision: int) -> Dictionary:
	return _run("refresh", revision)

## 购买 [param revision] 货架的 [param slot]，每个货位只出售一本。
func buy(revision: int, slot: int) -> Dictionary:
	return _run("buy", revision, slot)

## 按 [param mode] 消耗 [param ids] 并生成一本书；所有数量在执行瞬间重新读取。
func combine(mode: String, ids: Array[String]) -> Dictionary:
	return _run(mode, -1, -1, ids)

## 返回 [param mode]、[param ids] 的实时材料可用性及候选池，不修改资产。
func quote(mode: String, ids: Array[String]) -> Dictionary:
	var result: Dictionary = Rules.quote(mode, ids) # 配方校验和 UI 提示使用相同规则。
	if not result.ready:
		return result
	var counts: Dictionary = _counts(ids) # 同书投入多本必须累计，不逐次检查单本。
	for id: String in counts: # 每个唯一 ID 校验总投入数量。
		if _inventory.get_item_count(id) < int(counts[id]):
			return {"ready": false, "message": "技能书数量不足"}
	return result

## 返回当前库存中可追加到 [param ids] 的书；[param tier] 为零时不限，数量扣除已选材料。
## [param mode] 为合成时自动排除四阶及不同物种。
func available(mode: String, ids: Array[String], tier: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 只读列表携带剩余数量供材料选择区显示。
	var selected: Dictionary = _counts(ids) # 已选材料只预留显示，不提前扣库存。
	var first: Dictionary = Rules.Books.definition(ids[0]) if not ids.is_empty() else {} # 首槽约束后续材料。
	for id: String in _state.items: # 库存中其他物品不会进入技能书选择区。
		var book: Dictionary = Rules.Books.definition(id) # 权威技能定义的副本。
		var remaining: int = _inventory.get_item_count(id) - int(selected.get(id, 0)) # 可追加数量。
		if book.is_empty() or remaining <= 0 or (tier > 0 and int(book.tier) != tier):
			continue
		if mode == "synthesize" and int(book.tier) >= 4:
			continue
		if not first.is_empty() and (book.tier != first.tier or (mode == "synthesize" and book.plant_type != first.plant_type)):
			continue
		book["id"] = id
		book["count"] = remaining
		result.append(book)
	result.sort_custom(_book_before)
	return result

## [param a]、[param b] 按阶、物种、稳定 ID 排序，数量变化不扰动视觉顺序。
static func _book_before(a: Dictionary, b: Dictionary) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	if a.plant_type != b.plant_type:
		return a.plant_type < b.plant_type
	return str(a.id) < str(b.id)

## 将 [param ids] 汇总为每种书的总用量。
static func _counts(ids: Array[String]) -> Dictionary:
	var result: Dictionary = {} # 不保留零数量项。
	for id: String in ids: # 重复 ID 代表同种书多本。
		result[id] = int(result.get(id, 0)) + 1
	return result

## 统一加锁执行 [param action]；[param revision]、[param slot] 限定货位，[param ids] 为材料。
func _run(action: String, revision: int = -1, slot: int = -1, ids: Array[String] = []) -> Dictionary:
	if _committing:
		return _error("操作处理中")
	if _state == null or _state.library == null or _wallet == null or _inventory == null \
			or _wallet.adventure_state != _state or not _inventory.owns_state(_state) \
			or not _persist.is_valid() or not _clock.is_valid():
		return _error("档案已切换，请重新打开图书馆")
	_committing = true
	var result: Dictionary = _execute(action, revision, slot, ids) # 所有提前返回在内部完成，外部始终释放锁。
	_committing = false
	return result

## 在持锁期间校验 [param action] 与参数，构造变更后统一保存；任何失败恢复原资产。
## [param revision]、[param slot] 为货架定位，[param ids] 为完整投入列表。
func _execute(action: String, revision: int, slot: int, ids: Array[String]) -> Dictionary:
	var today: String = _clock.call() # 与窗口显示周期比较使用同一日期口径。
	var current: Stock = _state.library # 本次操作开始时的货架对象。
	var next_stock: Stock = Stock.from_dict(current.to_dict()) # 工作副本，成功提交前不污染真实货架。
	if next_stock == null:
		return _error("书架数据无效")
	var fee := 0 # 仅刷新与购买收费。
	var consume: Dictionary = {} # 完整材料成本先汇总再扣除。
	var gained := "" # 成功后唯一入库的技能书 ID。
	match action:
		"daily", "refresh":
			if action == "daily" and not current.day.is_empty() and current.day >= today:
				return {"ok": true, "changed": false}
			if action == "refresh":
				if revision != current.revision or current.day.is_empty() or current.day < today:
					return _error("书架已更新，请重新选择")
				fee = Rules.REFRESH_COST
			if fee > _wallet.coin_value:
				return _error("金币不足")
			if current.revision >= PlantCardInstance.MAX_JSON_INTEGER:
				return _error("书架刷新次数已达上限")
			next_stock.offers = Rules.draw_shelf(_rng)
			if next_stock.offers.size() != Rules.SHELF_SIZE:
				return _error("书目尚未就绪")
			next_stock.day = today if current.day < today else current.day
			next_stock.revision += 1
		"buy":
			if revision != current.revision or current.day.is_empty() or current.day < today \
					or slot < 0 or slot >= current.offers.size():
				return _error("书架已更新，请重新选择")
			if current.offers[slot].sold:
				return _error("本书已售出")
			gained = str(current.offers[slot].id)
			fee = Rules.PRICES[int(Rules.Books.definition(gained).tier) - 1]
			next_stock.offers[slot].sold = true
		"convert", "synthesize":
			var preview: Dictionary = quote(action, ids) # 先检验配方和总库存，再随机选结果。
			if not preview.ready:
				return _error(str(preview.message))
			consume = _counts(ids)
			gained = str(preview.pool[_rng.randi_range(0, preview.pool.size() - 1)])
		_:
			return _error("未知操作")
	if fee > _wallet.coin_value:
		return _error("金币不足")
	var before_items: Dictionary = _state.items.duplicate() # 资产快照覆盖同书重复投入及入库失败。
	var before_coin: int = _wallet.coin_value # 存档失败恢复原余额。
	var completed := true # 扣材料、入库、扣费与保存必须全部成功。
	for id: String in consume: # 每个 ID 仅扣一次汇总数量。
		if not _inventory.consume_item(id, int(consume[id])):
			completed = false
			break
	if completed and not gained.is_empty():
		completed = _inventory.add_item(gained, 1)
	if completed:
		_state.library = next_stock
		if fee > 0:
			_wallet.coin_value -= fee
		completed = _wallet.adventure_state == _state and _persist.call() == true
	if not completed:
		_state.items.assign(before_items)
		_state.library = current
		# 金币信号可能同步切档；旧事务不能把旧余额写进新档案的钱包。
		if _wallet.adventure_state == _state and _wallet.coin_value != before_coin:
			_wallet.coin_value = before_coin
		return _error("保存未完成，金币与书籍已恢复")
	return {"ok": true, "changed": true, "book": gained}

## 将 [param message] 封装为不修改资产的失败结果。
static func _error(message: String) -> Dictionary:
	return {"ok": false, "changed": false, "message": message}
