## 通用水面视觉资源。矩形以背景贴图像素为单位；空数组供独立泳池精灵使用。
extends Resource
class_name WaterSurfaceProfile

## 背景上允许绘制水面的位置，不包含池壁。
@export var regions: Array[Rect2] = []
## 对水体底色进行染色；白色保留原色。
@export var water_tint: Color = Color.WHITE
## 底色染色的混合系数。
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.0
## 水波推进速度。
@export_range(0.0, 2.0, 0.01) var wave_speed: float = 0.3
## UV 偏移幅度，相对于各水域自身宽高。
@export_range(0.0, 0.02, 0.0001) var ripple_strength: float = 0.0018
## 波纹和焦散的空间频率。
@export_range(0.1, 3.0, 0.01) var wave_density: float = 1.0
## 动态焦散光纹的强度。
@export_range(0.0, 0.25, 0.005) var caustic_strength: float = 0.06
## 焦散颜色。
@export var caustic_tint: Color = Color(0.65, 0.88, 0.9, 1.0)
## 渲染层不透明度。通常为 1，避免静态底图形成重影。
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0

## 校验水域是否在源纹理内；无需逐路硬编码判定。
## [param texture_size] 背景原图的尺寸，返回错误列表。
func validate_regions(texture_size: Vector2) -> PackedStringArray:
	var errors := PackedStringArray() # 所有无效区域提示
	for region: Rect2 in regions:
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			errors.append("水域尺寸必须大于零")
		elif region.position.x < 0.0 or region.position.y < 0.0 or (region.position + region.size).x > texture_size.x or (region.position + region.size).y > texture_size.y:
			errors.append("水域越出背景边界")
	return errors
