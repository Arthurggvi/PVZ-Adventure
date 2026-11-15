## Central art resolver for adventure star badges. No gameplay or save-state dependency.
extends RefCounted

## 星章静态图和特效图的唯一路径根目录。
const ROOT := "res://assets/adventure/ui/star_badges/"
## 扫光、闪光和十星虹彩共用的着色器。
const FX_SHADER := preload("res://shaders/adventure/star_badge_fx.gdshader")
## 七星起使用的共享闪光图。
const SPARKLE_PATH := ROOT + "fx/sparkle_shared.png"
## 十星专用光环。
const HALO_PATH := ROOT + "fx/star_10_halo.png"

## 返回 [param rank] 星章实际使用的纹理路径，范围与视图 configure 的 0～10 夹取一致。
## 只解析路径，不读取纹理；五、七、十星逐级加入实际显示的特效。
static func resource_paths(rank: int) -> PackedStringArray:
	var clamped: int = clampi(rank, 0, 10) # 与星章视图使用同一合法星级范围。
	var result := PackedStringArray() # 零星没有星章，也不准备隐藏特效。
	if clamped == 0:
		return result
	result.append(_body_uri(clamped))
	if clamped >= 5:
		result.append(_mask_uri(clamped, "sweep_mask"))
		result.append(_mask_uri(clamped, "number_guard"))
	if clamped >= 7:
		result.append(SPARKLE_PATH)
	if clamped == 10:
		result.append(_mask_uri(clamped, "color_mask"))
		result.append(HALO_PATH)
	return result

## 返回合法 [param rank] 的静态星章路径，供准备与实际读取共用。
static func _body_uri(rank: int) -> String:
	return ROOT + "static/256/star_%02d.png" % rank

## 返回 [param rank] 的 [param suffix] 遮罩路径，保持同一文件命名权威。
static func _mask_uri(rank: int, suffix: String) -> String:
	return ROOT + "masks/star_%02d_%s.png" % [rank, suffix]

## 读取 [param rank] 的静态星章；范围之外不显示。
static func body(rank: int) -> Texture2D:
	if rank < 1 or rank > 10:
		return null
	var uri: String = _body_uri(rank) # 与准备清单使用完全相同的路径。
	return load(uri) as Texture2D if ResourceLoader.exists(uri) else null

## 读取 [param rank] 的 [param suffix] 特效遮罩；低于五星不使用。
static func mask(rank: int, suffix: String) -> Texture2D:
	if rank < 5 or rank > 10:
		return null
	var uri: String = _mask_uri(rank, suffix) # 缺少可选遮罩时保留原有回退。
	return load(uri) as Texture2D if ResourceLoader.exists(uri) else null

## 读取七星起复用的闪光纹理。
static func sparkle() -> Texture2D:
	return load(SPARKLE_PATH) as Texture2D

## 读取十星专用光环。
static func halo() -> Texture2D:
	return load(HALO_PATH) as Texture2D
