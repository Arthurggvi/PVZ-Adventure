## 胆小菇词条的唯一合成规则；不同来源同类取较强值，不传播其他光环或星级属性。
extends RefCounted
class_name AdventureScaredyTraitRules

## 只有自身一至三转可供共生传播；四转选择互斥，也不能再次传播共生。
const SHAREABLE: Array[String] = [
	"scaredy_day_awake", "scaredy_cost", "scaredy_attack_rate",
	"scaredy_close_damage", "scaredy_colony", "scaredy_armor_damage",
]
## 原生来源额外允许自己的四转规则。
const NATIVE_ONLY: Array[String] = ["scaredy_solar", "scaredy_symbiosis"]

## 将已验证的冻结 [param events] 转为单株原生规则，不从最终属性反推技能。
static func from_events(events: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {} # 独立副本不允许运行组件改写转职目录。
	for event: Dictionary in events: # 一个合法阶级只会提供其已选书目的事件。
		var kind: String = str(event.get("kind", "")) # 数值属性由既有出生修饰器处理。
		if SHAREABLE.has(kind) or NATIVE_ONLY.has(kind):
			result[kind] = event.duplicate(true)
	return result

## 仅保留 [param rules] 中可共享的自身低阶词条；异常输入也不能携带四转或未知规则。
static func shareable(rules: Dictionary) -> Dictionary:
	var result: Dictionary = {} # 共享输出始终与输入独立。
	for kind: String in SHAREABLE: # 固定白名单阻断再次传播与最终属性复制。
		if rules.get(kind) is Dictionary:
			result[kind] = rules[kind].duplicate(true)
	return result

## 合成 [param native_rules] 和 [param sources]；同类数值取最大，不同词条可同时存在。
static func merge(native_rules: Dictionary, sources: Dictionary) -> Dictionary:
	var result: Dictionary = native_rules.duplicate(true) # 自有规则不会因共生离场被丢失。
	for source_rules: Dictionary in sources.values(): # 每个独立来源先通过同一共享白名单。
		for kind: String in shareable(source_rules): # 仅合并可共享词条，忽略外部四转数据。
			var incoming: Dictionary = source_rules[kind] # 当前来源的冻结参数。
			if not result.has(kind):
				result[kind] = incoming.duplicate(true)
				continue
			var retained: Dictionary = result[kind] # 同类效果只保留一份，布尔规则由存在性表达。
			for field: String in incoming: # 数值采用较强参数，字符串标识不参与运算。
				var value: Variant = incoming[field] # 现有参数均为非负增益或文字kind。
				if value is int or value is float:
					retained[field] = maxf(float(retained.get(field, 0.0)), float(value))
	return result
