## 掉落表只保存规则；独立概率、共享加权池、固定发放可明确并列，不负责结算。
extends Resource
class_name DropTable

## 加权抽取必须显式指定是否放回；没有加权条目时保持 UNSET。
enum WeightedSelection { UNSET, WITH_REPLACEMENT, WITHOUT_REPLACEMENT }
## 可跨配置复用的静态掉落表 ID。
@export var table_id: StringName = &""
## 强类型条目列表，禁止空条目和重复 ID。
@export var entries: Array[DropEntryDefinition] = []
## 加权池抽取次数，不影响独立概率和固定发放条目。
@export var weighted_draw_count: int = 0
## 加权池的放回策略，不隐式选择。
@export var weighted_selection: WeightedSelection = WeightedSelection.UNSET

## 返回静态错误；不会调用库存、随机数或文件接口。
func validate() -> PackedStringArray:
	var errors := PackedStringArray() # 表与各条目错误合并返回。
	if str(table_id).strip_edges().is_empty():
		errors.append("掉落表缺少稳定 ID。")
	if entries.is_empty():
		errors.append("掉落表为空。")
	var ids: Dictionary = {} # 条目 ID 在本表内唯一。
	var weighted_count := 0 # 加权池成员数，用于禁止空抽取或无放回超额抽取。
	for entry: DropEntryDefinition in entries: # 只读取子资源，不修正原配置。
		if entry == null:
			errors.append("掉落表包含空条目。")
			continue
		errors.append_array(entry.validate())
		if ids.has(entry.entry_id):
			errors.append("掉落条目 ID 重复：%s。" % entry.entry_id)
		ids[entry.entry_id] = true
		if entry.rule == DropEntryDefinition.Rule.WEIGHTED:
			weighted_count += 1
	if weighted_count > 0:
		if weighted_draw_count < 1 or weighted_selection not in [WeightedSelection.WITH_REPLACEMENT, WeightedSelection.WITHOUT_REPLACEMENT]:
			errors.append("加权池必须显式配置正抽取次数及放回策略。")
		if weighted_selection == WeightedSelection.WITHOUT_REPLACEMENT and weighted_draw_count > weighted_count:
			errors.append("无放回抽取次数超过加权池条目数。")
	elif weighted_draw_count != 0 or weighted_selection != WeightedSelection.UNSET:
		errors.append("空加权池不能配置抽取次数或策略。")
	return errors
