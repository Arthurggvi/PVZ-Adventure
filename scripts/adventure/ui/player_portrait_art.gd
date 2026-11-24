## 为角色面板和档案解析当前时装，并按档案框尺寸从原图取景。
extends RefCounted

## 未装配时装时，角色面板使用默认角色的完整立绘。
const DEFAULT_PORTRAIT = preload("res://assets/adventure/ui/player/portraits/default_farmer.png")
## 游客和未装配时装的玩家共用默认角色的头肩裁切。
const DEFAULT_AVATAR = preload("res://assets/adventure/ui/player/portraits/default_farmer_avatar.tres")

## 从 [param rows] 的有效装配投影查找当前时装；没有装配时装时返回 null。
static func equipped_outfit(rows: Array[Dictionary]) -> EquipmentDefinition:
	for row: Dictionary in rows: # 装备服务已排除失效、过期的装配。
		var item: EquipmentDefinition = row.definition # 同一份时装定义提供完整立绘与裁切头像。
		if row.equipped and item.slot == EquipmentDefinition.Slot.OUTFIT:
			return item
	return null

## 从 [param rows] 的有效装配投影返回当前时装头像；没有时装时返回默认头像。
static func equipped_avatar(rows: Array[Dictionary]) -> Texture2D:
	var outfit: EquipmentDefinition = equipped_outfit(rows) # 使头像与角色页读取同一件已装配时装。
	return outfit.icon if outfit != null else DEFAULT_AVATAR

## 以 [param avatar] 的头肩裁切为锚点，按 [param extent] 的宽高比向外取景。
## 采样限制在原图内，超出部分留透明边；没有有效裁切信息时返回原头像。
static func framed_avatar(avatar: Texture2D, extent: Vector2) -> Texture2D:
	var headshot := avatar as AtlasTexture # 装备图标的裁切记录了每套时装的构图中心。
	if headshot == null or headshot.atlas == null or not headshot.region.has_area():
		return avatar
	var height: float = headshot.region.size.y # 以原头像高度为单位，保留不同角色的相对缩放。
	var crop_size := Vector2(extent.aspect(), 1.0) * (height * 1.16) # 扩大头肩取景，给帽饰与肩部渐隐留空间。
	var crop_origin := Vector2(headshot.region.get_center().x - crop_size.x * 0.5,
		headshot.region.position.y - height * 0.075) # 向头顶加一点留白，脸部仍居于画面上半部。
	var crop := Rect2(crop_origin, crop_size) # 目标窗口可跨出立绘画布，以保持构图不偏移。
	var available := crop.intersection(Rect2(Vector2.ZERO, headshot.atlas.get_size())) # 原图内可采样的部分。
	if not available.has_area():
		return avatar
	var result := AtlasTexture.new() # 只保存取景信息，直接采样共享原图。
	result.atlas = headshot.atlas
	result.region = available
	result.margin = Rect2(available.position - crop.position, crop.size - available.size)
	result.filter_clip = true
	return result
