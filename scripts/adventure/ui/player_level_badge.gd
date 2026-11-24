## 美食大战老鼠原版等级角标；素材含数字，成长算法不依赖素材数量。
extends Control
class_name PlayerLevelBadge

## 现有原图覆盖 1–80 级，更高等级使用明确的文字显示。
const LAST_ART_LEVEL: int = 80
## 超出素材范围时的字号，窄画框可以在入树前指定更小的值以容纳完整等级。
var fallback_font_size: int = 35
## 原图角标，不拉伸改变长宽比例。
var _image: TextureRect
## 超出素材范围时的真实等级文字。
var _fallback: Label

## 创建纯表现控件，不读取全局玩家。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback = Label.new()
	_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback.add_theme_font_size_override("font_size", fallback_font_size)
	_fallback.add_theme_color_override("font_color", Color("ffe6a0"))
	_fallback.add_theme_color_override("font_outline_color", Color("493422"))
	_fallback.add_theme_constant_override("outline_size", 7)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fallback)
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## 按 [param level] 选择原图；不截断玩家真实等级，也不在已含数字的图片上重叠数字。
func present(level: int) -> void:
	var has_art: bool = level >= 1 and level <= LAST_ART_LEVEL # 图片范围只影响表现。
	_image.visible = has_art
	_fallback.visible = not has_art
	_image.texture = load("res://assets/adventure/ui/player/levels/%02d.png" % level) as Texture2D if has_art else null
	_fallback.text = "Lv.%d" % level
	tooltip_text = "等级 %d" % level
