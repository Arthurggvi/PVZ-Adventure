## 商店独立存档协议，记录限购与永久解锁状态。
extends RefCounted

## 槽位边界及商品合法性来自唯一目录。
const Catalog = preload("res://scripts/adventure/shop/shop_catalog.gd")
## 已购数量归属的自然日；设备日期校正时会同步归到当天。
var day := ""
## 当日每种商品已购买数量。
var daily_purchases: Dictionary[String, int] = {}
## 玩家永久可携带卡槽数量。
var card_slots: int = Catalog.BASE_SLOTS
## 一次性购买后永久开放冒险战斗手套；旧档默认为未解锁。
var glove_unlocked := false
## 每笔成功购买递增；确认单只能使用当前版本。
var revision := 0

## 将晚于 [param today] 的限购日期校正到当天，沿用已购数量，并从下一次本地跨日恢复补货。
## 发生校正时返回 true；无效日期或已到期的记录返回 false。
func correct_future_day(today: String) -> bool:
	if today.is_empty() or today >= day or not valid_day(today):
		return false
	day = today
	return true

## 返回不共享容器的序列化数据。
func to_dict() -> Dictionary:
	return {"day": day, "daily_purchases": daily_purchases.duplicate(), "card_slots": card_slots,
		"glove_unlocked": glove_unlocked, "revision": revision}

## 校验 [param data] 并返回独立状态；旧档缺失域使用六槽，损坏域拒绝加载。
static func from_dict(data: Variant) -> RefCounted:
	if not data is Dictionary:
		return null
	var result := new() # 反序列化不修改外部字典。
	if data.is_empty():
		return result
	if not data.get("day") is String or not valid_day(data.day) \
			or not data.get("daily_purchases") is Dictionary \
			or not data.get("glove_unlocked", false) is bool \
			or not PlantCardInstance.is_nonnegative_integer(data.get("revision")) \
			or not PlantCardInstance.is_nonnegative_integer(data.get("card_slots")) \
			or data.card_slots < Catalog.BASE_SLOTS or data.card_slots > Catalog.MAX_SLOTS:
		return null
	for id: Variant in data.daily_purchases: # 只保存目录中有限购的商品；数量不得超过配置。
		if not id is String or not PlantCardInstance.is_positive_integer(data.daily_purchases[id]):
			return null
		var limit: int = Catalog.daily_limit(id) # 校验数量不需要构造带装备资源的商品详情。
		if data.daily_purchases[id] > limit or data.day.is_empty():
			return null
		result.daily_purchases[id] = int(data.daily_purchases[id])
	result.day = data.day
	result.card_slots = int(data.card_slots)
	result.glove_unlocked = data.get("glove_unlocked", false)
	result.revision = int(data.revision)
	return result

## [param value] 为空或规范公历 YYYY-MM-DD 时返回 true，保证日期可直接排序。
static func valid_day(value: String) -> bool:
	if value.is_empty():
		return true
	var parts: PackedStringArray = value.split("-") # 拒绝非规范日期与无效月份。
	if parts.size() != 3 or value.length() != 10:
		return false
	for part: String in parts: # 三个分量均须是十进制整数。
		if not part.is_valid_int():
			return false
	var year: int = int(parts[0]) # 公历年，拒绝零年。
	var month: int = int(parts[1]) # 公历月，范围 1..12。
	var date: int = int(parts[2]) # 月内日期，按闰年上限校验。
	if year < 1 or month < 1 or month > 12 or value != "%04d-%02d-%02d" % [year, month, date]:
		return false
	var leap: bool = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) # 公历闰年规则。
	var days: Array[int] = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] # 各月天数。
	return date >= 1 and date <= days[month - 1]
