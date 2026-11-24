## 明灯共用的贴图、青蓝色光晕和气泡绘制。
extends RefCounted
class_name MingLanternArt

## 兼容渲染器使用的双色径向衰减贴图。
const BLOOM: Texture2D = preload("res://assets/adventure/zombies/ming_lantern/bloom.png")
## 折射边缘与两处高光已经烘入透明气泡。
const BUBBLE: Texture2D = preload("res://assets/adventure/zombies/ming_lantern/bubble.png")
## 近白色光芯之外的主色。
const CYAN := Color("1cdafa")
## 黑暗形态的裂纹与折射光。
const VIOLET := Color("9274ff")

## 在 [param parent] 的同一坐标系创建加色层；[param paint] 接收此绘制层。
static func light_layer(parent: Node2D, paint: Callable) -> Node2D:
	var layer := Node2D.new() # 亮部单独合成，避免给原画加色导致暗部消失。
	var blend := CanvasItemMaterial.new() # 兼容模式下也能叠加可见发光。
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	layer.material = blend
	layer.draw.connect(paint.bind(layer))
	parent.add_child(layer)
	return layer

## 在 [param canvas] 的 [param point] 绘制尺寸为 [param size] 的软光，[param tint] 的透明度为强度。
static func glow(canvas: Node2D, point: Vector2, size: Vector2, tint: Color) -> void:
	canvas.draw_texture_rect(BLOOM, Rect2(point - size * 0.5, size), false, tint)
