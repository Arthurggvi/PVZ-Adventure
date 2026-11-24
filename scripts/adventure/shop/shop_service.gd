## 商店交易边界：真实报价、重验、一次保存与完整回滚；不创建界面或播放动画。
extends RefCounted

## 唯一商品规则。
const Catalog = preload("res://scripts/adventure/shop/shop_catalog.gd")
## 持久化限购与槽位状态。
const Stock = preload("res://scripts/adventure/shop/shop_state.gd")
## 跨窗口防重入，避免金币变化信号触发同一商店的第二笔事务。
static var _committing := false
## 打开商店时绑定的档案身份。
var _state: AdventureState
## 当前档案的普通物品服务。
var _inventory: AdventureInventoryService
## 金币与当前档案的权威持有者。
var _wallet: GlobalGameState
## 同步持久化回调，成功时返回 true。
var _persist: Callable
## 当前加载档案及战斗状态校验回调。
var _guard: Callable
## 本机自然日来源，与日常任务一致。
var _clock: Callable

## 注入同档 [param state]、[param inventory]、[param wallet]；[param persist] 保存完整档案。
## [param guard] 校验当前档案仍可交易，[param clock] 返回 YYYY-MM-DD。
func _init(state: AdventureState, inventory: AdventureInventoryService, wallet: GlobalGameState,
		persist: Callable, guard: Callable, clock: Callable = AdventureQuestService.today) -> void:
	_state = state
	_inventory = inventory
	_wallet = wallet
	_persist = persist
	_guard = guard
	_clock = clock

## 返回是否仍持有当前有效档案，不信任窗口缓存。
func is_current() -> bool:
	return _state != null and _state.shop != null and _wallet != null and _wallet.adventure_state == _state \
		and _inventory != null and _inventory.owns_state(_state) and _persist.is_valid() \
		and _clock.is_valid() and _guard.is_valid() and _guard.call() == true \
		and AdventureQuestService.feature_unlocked(_state, "shop")

## 返回与限购共用的有效货架日期；档案校正前沿用已保存的限购日期，无效档案或日期返回空串。
func stock_day() -> String:
	if not is_current():
		return ""
	var today: String = str(_clock.call()) # 日期错误时不生成可交易的报价。
	if today.is_empty() or not Stock.valid_day(today):
		return ""
	return today if today > _state.shop.day else _state.shop.day

## 按单个货架日期查询 [param category] 下的报价；浏览不写档。
func offers(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 展示顺序与当日货架一致。
	var day: String = stock_day() # 一次渲染共用同一个日期，避免跨日时混用两批商品。
	if day.is_empty():
		return result
	for id: String in Catalog.ids(category, day): # 只为当前分类加载商品定义。
		var offer: Dictionary = _quote(id, day) # 配置失效的商品不生成可购买按钮。
		if not offer.is_empty():
			result.append(offer)
	return result

## 返回 [param id] 的实时只读报价；未上架时装返回空字典。
func quote(id: String) -> Dictionary:
	var day: String = stock_day() # 确认和提交都使用最新货架日期。
	if day.is_empty() or (id in Catalog.OUTFIT_POOL and id not in Catalog.ids(Catalog.OUTFIT_CATEGORY, day)):
		return {}
	return _quote(id, day)

## 为当前已上架的 [param id] 生成 [param day] 的报价；跨日计数在下一次成交时提交。
func _quote(id: String, day: String) -> Dictionary:
	var result: Dictionary = Catalog.product(id) # 从目录重新生成价格、权益和期限。
	if result.is_empty():
		return {}
	var limit: int = int(result.get("daily_limit", 0)) # 零表示不限次数。
	var used: int = int(_state.shop.daily_purchases.get(id, 0)) if day == _state.shop.day else 0 # 跨日展示新额度。
	var sold: bool = limit > 0 and used >= limit # 已售罄商品仍可选择查看说明。
	var status := "" # 简短按钮状态与业务失败原因共用。
	if result.kind == "slots":
		result.price = Catalog.slot_price(_state.shop.card_slots)
		sold = _state.shop.card_slots >= Catalog.MAX_SLOTS
		status = "已达11槽" if sold else "当前 %d 槽 → %d 槽" % [_state.shop.card_slots, _state.shop.card_slots + 1]
	elif result.kind == "glove":
		sold = _state.shop.glove_unlocked
		status = "已拥有" if sold else "永久解锁"
	elif bool(result.get("unique", false)):
		sold = _state.equipment.owned.values().has(str(result.asset))
		status = "已拥有" if sold else "永久解锁"
	elif limit > 0:
		status = "今日售罄" if sold else "今日剩余 %d / %d" % [maxi(0, limit - used), limit]
	else:
		status = "购买起7天 · 角色页装备"
	result["remaining"] = maxi(0, limit - used) if limit > 0 else -1
	result["sold"] = sold
	result["status"] = status
	result["can_buy"] = not sold and _wallet.coin_value >= int(result.price)
	result["message"] = status if sold else ("金币不足" if not result.can_buy else "")
	# 绑定限购记录的日期，时钟校正后回到原日期也要重新确认。
	result["token"] = {"id": id, "day": day, "quota_day": _state.shop.day,
		"revision": _state.shop.revision, "price": result.price}
	return result

## 购买 [param token] 对应的已确认报价；任何陈旧价格、跨日或重复提交都先拒绝，不扣款。
func buy(token: Dictionary) -> Dictionary:
	if _committing:
		return _error("交易正在保存，请稍候。")
	if not is_current():
		return _error("档案已变化，请重新打开商店。")
	_committing = true
	var result: Dictionary = _commit(token) # 所有分支在内部结束，外层始终释放锁。
	_committing = false
	return result

## 持锁处理 [param token]；扣款、发货与永久升级必须作为同一事务保存。
func _commit(token: Dictionary) -> Dictionary:
	var offer: Dictionary = quote(str(token.get("id", ""))) # 不能使用 UI 传入的任意价格或目标物品。
	if offer.is_empty() or offer.token != token:
		return _error("商品状态已更新，请重新确认。")
	if not offer.can_buy:
		return _error(str(offer.message))
	if _state.shop.revision >= PlantCardInstance.MAX_JSON_INTEGER:
		return _error("购买记录已达上限。")
	var old_stock: Stock = _state.shop # 保留原对象，失败时恢复身份和所有计数。
	var next_stock: Stock = Stock.from_dict(old_stock.to_dict()) # 变更在独立副本上生成。
	var old_items: Dictionary = _state.items.duplicate() # 普通物品数量快照。
	var old_equipment: Dictionary = _state.equipment.to_dict() # UID、持有记录、装配与期限一起回滚。
	var old_coins: int = _wallet.coin_value # 发货或保存失败不得丢失金币。
	var granted := true # 所有发货类型共用提交逻辑。
	var equipment_uid := "" # 成交结果可用于后续展示，不自动替换玩家现有装备。
	if next_stock == null:
		return _error("商店状态无效。")
	if next_stock.day != str(token.day):
		next_stock.day = str(token.day)
		next_stock.daily_purchases.clear()
	match str(offer.kind):
		"item":
			granted = _inventory.add_item(str(offer.asset), 1)
		"equipment":
			equipment_uid = PlayerEquipmentService.new(_state.equipment).grant(StringName(offer.asset))
			granted = not equipment_uid.is_empty()
		"slots":
			next_stock.card_slots += 1
		"glove":
			next_stock.glove_unlocked = true
		_:
			granted = false
	if granted:
		if int(offer.get("daily_limit", 0)) > 0:
			next_stock.daily_purchases[str(offer.id)] = int(next_stock.daily_purchases.get(str(offer.id), 0)) + 1
		next_stock.revision += 1
		_state.shop = next_stock
		_wallet.coin_value -= int(offer.price)
		granted = is_current() and _persist.call() == true
	if not granted:
		_state.items.assign(old_items)
		_state.shop = old_stock
		_state.equipment.owned.assign(old_equipment.owned)
		_state.equipment.equipped.assign(old_equipment.equipped)
		_state.equipment.expires_at.assign(old_equipment.expires_at)
		_state.equipment.next_id = int(old_equipment.next_id)
		if _wallet.adventure_state == _state and _wallet.coin_value != old_coins:
			_wallet.coin_value = old_coins
		return _error("购买未完成，金币和商品已恢复，请重试。")
	return {"ok": true, "id": offer.id, "title": offer.title, "equipment_uid": equipment_uid}

## 将 [param message] 封装成明确的业务失败结果。
static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
