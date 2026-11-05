## 玩家独立植物卡的纯数据身份，不包含场景、冷却或其他运行时对象。
extends RefCounted
class_name PlantCardInstance

## JSON 数值可精确往返的最大整数，也约束 UID 计数和数量溢出。
const MAX_JSON_INTEGER: int = 9007199254740991
## New cards and enhancements are capped at ten stars; historical saves remain readable.
const MAX_STARS: int = 10
## 玩家状态内唯一的规范编号，形如 PC000001。
var uid: String = ""
## 已注册植物物种，排除空物种及模仿者模板。
var plant_type: int = 0
## 独立星级，零星为新卡默认值；不预设升级上限。
var stars: int = 0
## 第一转职标记，空字符串表示尚未转职。
var promotion_1: String = ""
## 第二转职标记，空字符串表示尚未转职。
var promotion_2: String = ""
## 第三、四次转职仅保存对应书的稳定分支 ID。
var promotion_3: String = ""
var promotion_4: String = ""
const PROMOTION_FIELDS := ["promotion_1", "promotion_2", "promotion_3", "promotion_4"]

## 返回独立的 JSON 字典；当前字段无效时返回空字典，不输出对象引用。
func to_dict() -> Dictionary:
	var data: Dictionary = {"uid": uid, "plant_type": plant_type, "stars": stars,
		"promotion_1": promotion_1, "promotion_2": promotion_2,
		"promotion_3": promotion_3, "promotion_4": promotion_4}
	return data if from_dict(data) != null else {}

## 从 [param data] 创建独立卡；非法身份、物种、星级或转职字段返回 null。
static func from_dict(data: Variant) -> PlantCardInstance:
	if not data is Dictionary or uid_number(data.get("uid")) == 0 \
		or not is_plant_type(data.get("plant_type")) or not is_nonnegative_integer(data.get("stars", 0)):
		return null
	for field: String in PROMOTION_FIELDS:
		if typeof(data.get(field, "")) != TYPE_STRING:
			return null
	var card := PlantCardInstance.new() # 仅在所有输入验证通过后创建数据对象。
	card.uid = data.uid
	card.plant_type = int(data.plant_type)
	card.stars = int(data.get("stars", 0))
	card.promotion_1 = data.get("promotion_1", "")
	card.promotion_2 = data.get("promotion_2", "")
	card.promotion_3 = data.get("promotion_3", "")
	card.promotion_4 = data.get("promotion_4", "")
	return card

## Read/write a bounded promotion tier, preserving the card and its stars.
func get_promotion(tier: int) -> String:
	return str(get(PROMOTION_FIELDS[tier - 1])) if tier >= 1 and tier <= 4 else ""

func set_promotion(tier: int, book_id: String) -> bool:
	if tier < 1 or tier > 4 or book_id.is_empty():
		return false
	if not get_promotion(tier).is_empty():
		return false
	set(PROMOTION_FIELDS[tier - 1], book_id)
	return true

## [param value] 接受 JSON 解码的整数浮点表示，但拒绝布尔、小数及不精确大整数。
static func is_positive_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(value) and value > 0 and value <= MAX_JSON_INTEGER and value == floor(value)

## 星级允许零；其他数量与 UID 仍必须使用正整数校验。
static func is_nonnegative_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(value) and value >= 0 and value <= MAX_JSON_INTEGER and value == floor(value)

## [param value] 必须是已注册且非空、非模仿者模板的植物编号。
static func is_plant_type(value: Variant) -> bool:
	return is_positive_integer(value) and int(value) != CharacterRegistry.PlantType.P999Imitater \
		and CharacterRegistry.PlantType.values().has(int(value))

## 返回 [param value] 的规范 UID 数值，非法格式返回 0；六位是最小宽度，不限制六位之后的递增。
static func uid_number(value: Variant) -> int:
	if typeof(value) != TYPE_STRING or not value.begins_with("PC"):
		return 0
	var digits: String = value.substr(2) # 只允许可安全转换的整数文本。
	if digits.length() < 6 or digits.length() > 16 or not digits.is_valid_int():
		return 0
	var number: int = digits.to_int() # 通过规范格式回比排除符号、空格和多余前导零。
	return number if is_positive_integer(number) and value == "PC%06d" % number else 0
