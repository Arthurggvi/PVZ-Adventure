## 商店共享视觉原语；颜色、字体和商品美术解析集中管理，不访问玩家资产。
extends RefCounted

## 原项目木框与纸张九宫格素材。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 普通道具图标从同一背包美术目录解析。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 中文标题与正文统一字体。
const FONT = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 全屏画布保持 16:9 的设计坐标。
const DESIGN := Vector2(1440, 810)
## 深棕正文颜色。
const INK := Color("493522")
## 次要文字颜色。
const MUTED := Color("876d4b")
## 奶油色高亮文字。
const CREAM := Color("fff2cf")
## 绿色选中态。
const GREEN := Color("456b42")
## 金色边线与价格强调。
const GOLD := Color("e5b65b")

## 格式化 [param value] 为千位分组金币，不使用有精度歧义的缩写。
static func money(value: int) -> String:
	var digits: String = str(value) # 仅用于非负金币展示。
	var result := "" # 从左至右插入千位分隔。
	for index: int in digits.length(): # 保留全部价格数字。
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return result

## 生成 [param fill]、[param border]、[param radius] 指定的独立圆角样式。
static func box(fill: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 每个状态独立，避免共享资源被改色。
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.10, 0.06, 0.02, 0.18)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style

## 在 [param parent] 的 [param rect] 创建文字 [param text]；字号 [param font_size]，颜色 [param color]。
static func label(parent: Node, text: String, rect: Rect2, font_size: int = 24, color: Color = INK) -> Label:
	var node := Label.new() # 固定区域内自动折行，避免长中文溢出。
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

## 创建 [param caption] 按钮；[param primary] 决定绿金强调，[param callback] 仅发送交互意图。
## [param parent] 与 [param rect] 指定展示位置。
static func button(parent: Node, caption: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new() # 真正可聚焦的按钮，支持键盘确认。
	node.text = caption
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", 25)
	node.add_theme_color_override("font_color", CREAM if primary else INK)
	node.add_theme_color_override("font_hover_color", CREAM if primary else INK)
	node.add_theme_color_override("font_pressed_color", CREAM)
	node.add_theme_color_override("font_focus_color", CREAM if primary else INK)
	node.add_theme_color_override("font_disabled_color", Color("aa987a"))
	node.add_theme_stylebox_override("normal", box(GREEN if primary else Color("eddbb2"), GOLD if primary else Color("ae8953")))
	node.add_theme_stylebox_override("hover", box(Color("63864d") if primary else Color("fff0cd"), GOLD))
	node.add_theme_stylebox_override("pressed", box(Color("314f33"), GOLD))
	node.add_theme_stylebox_override("disabled", box(Color("ded0b4"), Color("b6a483")))
	node.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), GOLD))
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if callback.is_valid():
		node.pressed.connect(callback)
	parent.add_child(node)
	return node

## 按 [param offer] 获取已有商品美术；[param portrait] 为时装时使用全身立绘。
static func product_texture(offer: Dictionary, portrait: bool = false) -> Texture2D:
	match str(offer.get("kind", "")):
		"item":
			return Art.texture(ItemArt.icon_uri(str(offer.asset)))
		"equipment":
			var item: EquipmentDefinition = EquipmentCatalog.definition(StringName(offer.asset)) # 视觉配置不复制装备效果。
			if item != null:
				return item.portrait if portrait and item.portrait != null else item.icon
		"slots":
			return preload("res://assets/image/store/Store_PacketUpgrade.png")
	return null

## 在 [param parent] 的 [param rect] 显示 [param texture]，保持图像比例。
static func image(parent: Node, texture: Texture2D, rect: Rect2) -> TextureRect:
	var node := TextureRect.new() # 商品素材保持原始透明度，不烘焙价格文字。
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node
