## 任务可序列化状态；日常仅保留最近周期，避免记录无限增长。
extends RefCounted
class_name AdventureQuestState

## 已见最大本机日期，回拨时钟不会恢复旧日常。
var day: String = ""
## 按任务 ID 保存周期、状态和计数；未出现的任务表示尚未生效。
var records: Dictionary = {}

## 返回独立 JSON 数据。
func to_dict() -> Dictionary:
	return {"day": day, "records": records.duplicate(true)}

## 校验 [param data] 后恢复状态；缺字段及损坏数据返回 null。
static func from_dict(data: Variant) -> AdventureQuestState:
	if not data is Dictionary or not data.has_all(["day", "records"]):
		return null
	if not _day(data.day) or not data.records is Dictionary:
		return null
	for id: Variant in data.records: # 保留未来被移除任务的合法记录，避免重新发奖。
		if not id is String or id.is_empty() or not data.records[id] is Dictionary:
			return null
		var record: Dictionary = data.records[id] # 每个任务记录具有固定协议。
		if not record.has_all(["period", "status", "progress"]) or not _day(record.period) \
				or record.status not in ["active", "complete", "claimed"] or not _integer(record.progress, 0):
			return null
		if record.has("awarded_experience") and not _integer(record.awarded_experience, 0):
			return null
		if record.has("collected_items"):
			if not record.collected_items is Array:
				return null
			for item_id: Variant in record.collected_items: # 保留合法历史 ID，内容目录调整后仍能读档。
				if not item_id is String or item_id.is_empty():
					return null
	var result := AdventureQuestState.new() # 创建独立状态，避免共享输入容器。
	result.day = data.day
	result.records = data.records.duplicate(true)
	return result

## [param value] 必须是大于等于 [param minimum] 的 JSON 安全整数。
static func _integer(value: Variant, minimum: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(value) \
		and value >= minimum and value <= PlantCardInstance.MAX_JSON_INTEGER and value == floor(value)

## [param value] 为空或标准 ISO 日期，允许首次载入尚无日常周期。
static func _day(value: Variant) -> bool:
	if not value is String:
		return false
	if value.is_empty():
		return true
	var regex := RegEx.new() # 限制周期格式，按字符串比较日期才有意义。
	regex.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
	if regex.search(value) == null:
		return false
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(value + "T00:00:00")) == value
