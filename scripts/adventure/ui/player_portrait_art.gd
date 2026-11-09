## 角色面板和战外头像共用时装立绘，头像只读取原图的头肩区域。
extends RefCounted

## 未装备时装时使用的角色立绘。
const DEFAULT_PORTRAIT = preload("res://assets/adventure/ui/player/portraits/default_farmer.png")
## 当前立绘共用的头肩裁切区，按原图宽高归一化。
const HEAD_REGION := Rect2(0.035, 0.012, 0.86, 0.39)

## 从 [param rows] 的有效装配投影选择立绘；空时装槽使用默认角色。
static func resolve(rows: Array[Dictionary]) -> Texture2D:
	for row: Dictionary in rows: # 装备服务已排除失效的装配。
		var item: EquipmentDefinition = row.definition # 装备定义提供角色面板所用的原图。
		if row.equipped and item.slot == EquipmentDefinition.Slot.OUTFIT:
			return item.portrait
	return DEFAULT_PORTRAIT

## 对 [param portrait] 建立只读裁切贴图，保留原始立绘和透明边缘。
static func head_crop(portrait: Texture2D) -> AtlasTexture:
	var crop := AtlasTexture.new() # 图集区域只用于头像，角色面板仍显示全身立绘。
	var source_size := portrait.get_size() # 归一化坐标转为原始像素。
	crop.atlas = portrait
	crop.region = Rect2(HEAD_REGION.position * source_size, HEAD_REGION.size * source_size)
	crop.filter_clip = true
	return crop
