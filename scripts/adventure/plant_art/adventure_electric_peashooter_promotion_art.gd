## 电能豌豆各等阶共用闪电芦苇的换色方法；原版贴图与动画保持独立。
extends RefCounted
class_name AdventureElectricPeashooterPromotionArt

## 电能豌豆在卡片、图鉴和存档中的稳定编号。
const PLANT_TYPE: int = 52
## 唯一的电系色表、渐变着色器、根光与特效材质缓存。
const ReedArt = preload("res://scripts/adventure/plant_art/adventure_lightning_reed_promotion_art.gd")
## 本体根部到头顶的局部参考高度，单位为原版动作坐标像素。
const BODY_HEIGHT: float = 84.0


## 为身体容器 [param body] 应用 [param rank] 转配色；0 恢复原画，1～4 对应二至五阶。
## 返回是否找到完整的原版美术层；保留隐藏部件以支持后续动作切换。
static func apply_to_body(body: Node2D, rank: int) -> bool:
	if body == null:
		return false
	var visual := body.get_node_or_null(^"ElectricPeashooterVisual") as Node2D # 根部对齐的原版动画容器。
	if visual == null:
		return false
	var rig := visual.get_node_or_null(^"Rig") as Node2D # PAM 转换后的分层精灵。
	if rig == null:
		return false
	var sprites: Array[Sprite2D] = [] # 同一植株所有动作部件共享渐变坐标。
	for child: Node in rig.get_children(): # 包括暂时隐藏的眨眼、发射和电光部件。
		if child is Sprite2D:
			sprites.append(child)
	return ReedArt.apply_palette(visual, sprites, rank, BODY_HEIGHT)


## 为静态预览 [param preview] 应用 [param rank] 转配色；返回是否成功找到卡面。
static func apply_to_preview(preview: Node2D, rank: int) -> bool:
	if preview == null:
		return false
	var visual := preview.get_node_or_null(^"ElectricPeashooter") as Node2D # 与场上植株一致的根部锚点。
	if visual == null:
		return false
	var artwork := visual.get_node_or_null(^"Artwork") as Sprite2D # 原版透明种子包插图。
	if artwork == null or artwork.texture == null:
		return false
	var portrait_height: float = maxf(1.0, -artwork.position.y + artwork.texture.get_height() * absf(artwork.scale.y) * 0.5) # 顶边距根部的实际局部高度。
	return ReedArt.apply_palette(visual, [artwork], rank, portrait_height)


## 为电球、电弧或命中特效 [param effect] 应用 [param rank] 转配色；特效须具有原版 Rig 层。
## 原版一阶不挂材质，其他阶级与闪电芦苇共享只读的电弧材质缓存。
static func apply_to_effect(effect: Node2D, rank: int) -> void:
	ReedArt.apply_to_effect(effect, rank)
