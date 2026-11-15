## 图书馆每日货架的独立存档协议；不接触库存、金币或文件。
extends RefCounted

## 权威技能书定义，存档不重复保存价格和技能数据。
const Books = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
## 最近一次生成货架的本机自然日，空字符串表示尚未开馆。
var day := ""
## [member day] 当天的付费换书机会是否已用完，生成新一天的货架时重置。
var refresh_used := false
## 货架版本；每次换日或付费刷新递增，拦截旧按钮提交。
var revision := 0
## 五个货位，各保存书 ID 与是否售出。
var offers: Array[Dictionary] = []

## 返回不共享容器的存档数据。
func to_dict() -> Dictionary:
	return {"day": day, "refresh_used": refresh_used, "revision": revision, "offers": offers.duplicate(true)}

## 从 [param data] 恢复独立货架；旧档缺少付费换书标记时默认未用，损坏内容返回 null。
static func from_dict(data: Variant) -> RefCounted:
	if not data is Dictionary:
		return null
	var stock := new() # 返回的状态不会复用原始 JSON 容器。
	if data.is_empty():
		return stock
	var used: Variant = data.get("refresh_used", false) # 旧货架的版本同时包含自动更新，无法从版本推算当天用量。
	if not data.get("day") is String or not data.get("offers") is Array \
			or not used is bool or not PlantCardInstance.is_nonnegative_integer(data.get("revision")):
		return null
	if data.day == "" and not used and data.revision == 0 and data.offers.is_empty():
		return stock
	var parts: PackedStringArray = data.day.split("-") # 严格验证自然日，保证字符串可按时间比较。
	if parts.size() != 3 or data.day.length() != 10:
		return null
	for part: String in parts: # 日期各分量必须是十进制整数。
		if not part.is_valid_int():
			return null
	if int(parts[0]) < 1 or int(parts[1]) < 1 or int(parts[1]) > 12:
		return null
	var leap: bool = int(parts[0]) % 4 == 0 and (int(parts[0]) % 100 != 0 or int(parts[0]) % 400 == 0) # 公历闰年。
	var days: Array[int] = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] # 各月合法天数。
	if int(parts[2]) < 1 or int(parts[2]) > days[int(parts[1]) - 1] \
			or data.day != "%04d-%02d-%02d" % [int(parts[0]), int(parts[1]), int(parts[2])] \
			or data.revision < 1 or data.offers.size() != 5:
		return null
	for offer: Variant in data.offers: # 售出标志只能是布尔值，书目必须仍在统一目录。
		if not offer is Dictionary or not offer.get("id") is String \
				or Books.definition(offer.id).is_empty() or not offer.get("sold") is bool:
			return null
		stock.offers.append({"id": offer.id, "sold": offer.sold})
	stock.day = data.day
	stock.refresh_used = used
	stock.revision = int(data.revision)
	return stock
