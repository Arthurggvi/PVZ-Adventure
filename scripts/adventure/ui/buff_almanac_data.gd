## Buff 图鉴的只读目录门面：按实际状态合并不同技能来源，不读写发现记录或战斗实例。
## type_id 仅为本次目录固定顺序的一基索引，不具有存档或角色物种含义。
extends RefCounted

## 原生及抗火寒冷共用的展示分组。
const Cold: GDScript = preload("res://scripts/adventure/ui/buff_almanac_cold.gd")
## 经统一入口施加的行动控制分组。
const ControlStates: GDScript = preload("res://scripts/adventure/ui/buff_almanac_control.gd")
## 原生睡眠、怯战和强制位移分组。
const NativeStates: GDScript = preload("res://scripts/adventure/ui/buff_almanac_native.gd")
## 持续伤害、数值削弱与目标累积标记分组。
const Periodic: GDScript = preload("res://scripts/adventure/ui/buff_almanac_periodic.gd")
## 格挡、减伤、护甲和免疫的防护分组。
const Defense: GDScript = preload("res://scripts/adventure/ui/buff_almanac_defense.gd")
## 攻速、增伤与行为豁免的正向战斗分组。
const Boons: GDScript = preload("res://scripts/adventure/ui/buff_almanac_boons.gd")
## 生产、恢复及战场时钟状态分组。
const Production: GDScript = preload("res://scripts/adventure/ui/buff_almanac_production.gd")

## 返回供左侧列表使用的全部状态；[param search] 按名称、分类、说明及来源匹配。
## 不依赖物种发现或存档；搜索过滤后仍保留全量目录中的 type_id。
static func rows(search: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 列表只接收身份和卡片绘制字段，不暴露目录原字典。
	var entries: Array[Dictionary] = _catalog() # 所有类别共享同一固定顺序。
	var needle: String = search.strip_edges().to_lower() # 中英文标识均支持不区分大小写查找。
	for index: int in range(entries.size()): # 全量索引在过滤前生成，切换搜索不改变预览身份。
		var data: Dictionary = entries[index] # 仅读取定义，不修改常量容器。
		var searchable: String = ("%s %s %s %s %s %s %s" % [
			data["title"], data["category"], data["summary"], data["sources"],
			data["buff_id"], data["stats"], data["effects"]]).to_lower() # 规则中的关键词也可用于查阅。
		if not needle.is_empty() and not searchable.contains(needle):
			continue
		result.append({
			"kind": "buff", "type_id": index + 1, "buff_id": data["buff_id"],
			"preview_id": data["buff_id"], "title": data["title"],
			"category": data["category"], "color": data["color"], "symbol": data["symbol"],
		})
	return result

## 返回 [param type_id] 所指状态的独立详情副本；0 或越界编号返回空字典。
## 预览只消费字典中的示意参数，不通过该接口创建真实角色或改动战斗状态。
static func profile(type_id: int) -> Dictionary:
	var entries: Array[Dictionary] = _catalog() # 索引来自 rows 的全量顺序。
	if type_id <= 0 or type_id > entries.size():
		return {}
	return _with_identity(entries[type_id - 1], type_id)

## 按稳定字符串 [param buff_id] 查询状态；未知标识返回空字典，调用方可安全修改返回副本。
static func entry(buff_id: StringName) -> Dictionary:
	var entries: Array[Dictionary] = _catalog() # 字符串标识不依赖列表筛选条件。
	for index: int in range(entries.size()): # 当前目录很小，顺序查找避免另建可变索引状态。
		if StringName(entries[index]["buff_id"]) == buff_id:
			return _with_identity(entries[index], index + 1)
	return {}

## 合并展示分组；仅供本脚本内部读取，不将常量容器直接交给界面。
static func _catalog() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [] # 新数组只复制条目引用，最终详情再做深复制。
	entries.append_array(Cold.ENTRIES)
	entries.append_array(ControlStates.ENTRIES)
	entries.append_array(NativeStates.ENTRIES)
	entries.append_array(Periodic.ENTRIES)
	entries.append_array(Defense.ENTRIES)
	entries.append_array(Boons.ENTRIES)
	entries.append_array(Production.ENTRIES)
	return entries

## 为 [param source] 的深副本补全 [param type_id]、类别身份及稳定预览标识。
## 不复制运行时对象；所有条目只包含文字、数值、颜色和字典。
static func _with_identity(source: Dictionary, type_id: int) -> Dictionary:
	var result: Dictionary = source.duplicate(true) # 详情与预览不能反写共享目录。
	result["kind"] = "buff"
	result["type_id"] = type_id
	result["preview_id"] = StringName(source["buff_id"])
	return result
