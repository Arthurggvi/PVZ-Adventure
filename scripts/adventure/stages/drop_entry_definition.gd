## 独立掉落条目；概率、加权与固定发放是互斥的静态规则，不执行发奖。
extends Resource
class_name DropEntryDefinition

## CHANCE 为逐条独立概率，WEIGHTED 进入共享抽取池，GUARANTEED 固定数量。
enum Rule { UNSET, CHANCE, WEIGHTED, GUARANTEED }
## 奖励引用种类，植物卡和普通物品/钥匙使用不同参数。
enum AssetKind { UNSET, ITEM, KEY }
## 条目稳定 ID。
@export var entry_id: StringName = &""
## 未配置不能默认为某一种掉落规则。
@export var rule: Rule = Rule.UNSET
## 奖励引用类型，未配置时校验失败。
@export var asset_kind: AssetKind = AssetKind.UNSET
## 普通物品或钥匙的静态 ID；植物卡不使用此字段。
@export var asset_id: StringName = &""
## 最少数量，必须为正整数。
@export var quantity_min: int = 0
## 最多数量，不得小于最少数量；固定发放必须与最少数量相等。
@export var quantity_max: int = 0
## 仅 CHANCE 使用 0–1；-1 表示该参数不适用于当前规则。
@export var chance: float = -1.0
## 仅 WEIGHTED 使用正整数；不是概率，不要求总和为 1。
@export var weight: int = 0

## 返回配置错误，不读取资产服务或执行随机抽取。
func validate() -> PackedStringArray:
	var errors := PackedStringArray() # 条目校验结果。
	if str(entry_id).strip_edges().is_empty():
		errors.append("掉落条目缺少稳定 ID。")
	if not Rule.values().has(rule) or rule == Rule.UNSET:
		errors.append("掉落规则未配置或无效。")
	if not AssetKind.values().has(asset_kind) or asset_kind == AssetKind.UNSET:
		errors.append("掉落资产类型未配置或无效。")
	if asset_kind in [AssetKind.ITEM, AssetKind.KEY]:
		var id: String = str(asset_id)
		if id.strip_edges().is_empty() or not ItemRegistry.has_item(id):
			errors.append("物品或钥匙必须引用已注册的静态道具 ID。")
		else:
			var is_key: bool = str(ItemRegistry.get_item_definition(id).get("category", "")) == "key"
			if (asset_kind == AssetKind.KEY) != is_key:
				errors.append("掉落资产类别与道具注册类别不一致：" + id)
	if quantity_min < 1 or quantity_max < quantity_min or quantity_max > PlantCardInstance.MAX_JSON_INTEGER:
		errors.append("掉落数量区间无效。")
	if rule == Rule.CHANCE:
		if not is_finite(chance) or chance < 0.0 or chance > 1.0:
			errors.append("独立掉落概率必须在 0–1 之间。")
	elif chance != -1.0:
		errors.append("非概率条目不能填写 chance。")
	if rule == Rule.WEIGHTED:
		if weight <= 0:
			errors.append("加权掉落必须使用正整数权重。")
	elif weight != 0:
		errors.append("非加权条目不能填写 weight。")
	if rule == Rule.GUARANTEED and quantity_min != quantity_max:
		errors.append("固定发放必须指定唯一数量。")
	return errors
