## 单株寒冰射手的冻结书目；只从出战配置读取技能参数。
extends RefCounted
class_name SnowPeaLoadout

## 按技能名索引的选项副本；出战期间不再查询研究目录。
var _rules: Dictionary[StringName, Dictionary] = {}

## 将 [param events] 冻结为本株共享给根弹、加射弹及派生效果的配置。
func _init(events: Array[Dictionary]) -> void:
	for event: Dictionary in events: # 派发器只传入寒冰射手事件。
		_rules[StringName(str(event.kind).trim_prefix("snow_pea_"))] = event.duplicate(true)

## 返回是否选择了 [param kind]。
func has(kind: StringName) -> bool:
	return _rules.has(kind)

## 返回 [param kind] 的数值字段 [param field]；缺省字段使用 [param fallback]。
func number(kind: StringName, field: StringName, fallback: float = 0.0) -> float:
	var rule: Dictionary = _rules.get(kind, {}) # 只读取冻结书目参数。
	return float(rule.get(String(field), fallback))
