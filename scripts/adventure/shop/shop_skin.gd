## 商店视觉原语：深绿货架、暖白品名、金色价格；不访问玩家资产。
extends RefCounted

## 普通道具贴图沿用原项目资源加载器。
const Art = preload("res://scripts/adventure/ui/inventory_skin.gd")
## 普通道具图标从同一背包美术目录解析。
const ItemArt = preload("res://scripts/adventure/ui/inventory_item_art.gd")
## 手写字体只用于店名和戴夫台词。
const FONT = preload("res://assets/fonts/方正少儿_GBK.ttf")
## 商品、导航和说明使用清晰的中文无衬线字体。
static var BODY_FONT: SystemFont = _make_font(false)
## 价格使用独立数字字体，避免手写数字与中文标题争夺注意力。
static var NUMBER_FONT: SystemFont = _make_font(true)
## 全屏画布保持 16:9 的设计坐标。
const DESIGN := Vector2(1440, 810)
## 戴夫浅色气泡内的深棕文字。
const INK := Color("342b20")
## 次要信息与小角标，不与品名竞争。
const MUTED := Color("a5b4a0")
## 商品名与主导航的暖白色。
const CREAM := Color("f4eed9")
## 购买动作的叶绿色。
const GREEN := Color("567d46")
## 金币与选中态独占的金色。
const GOLD := Color("f3cc75")
## 货架背板，保留轻微的绿色环境感。
const SURFACE := Color("1e2c26")
## 普通商品卡底色。
const CARD := Color("2c3e33")
## 卡片和非激活导航的低对比边线。
const LINE := Color("52624b")

## [param numbers] 为 true 时优先使用数字字体；字体缺失时交给系统回退。
static func _make_font(numbers: bool) -> SystemFont:
	var font := SystemFont.new() # 不复制系统字体文件进仓库。
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "sans-serif"] if numbers else ["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.font_weight = 600 if numbers else 500
	font.fallbacks = [FONT]
	return font

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
static func box(fill: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new() # 每个状态独立，避免共享资源被改色。
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.02, 0.05, 0.03, 0.24)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	return style

## 在 [param parent] 的 [param rect] 放置单层面板；[param fill]、[param border]、[param radius] 决定外观。
static func panel(parent: Node, rect: Rect2, fill: Color, border: Color = LINE, radius: int = 14) -> Panel:
	var node := Panel.new() # 面板仅负责背景，输入由具体按钮拥有。
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", box(fill, border, radius))
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

## 在 [param parent] 的 [param rect] 创建文字 [param text]；字号 [param font_size]，颜色 [param color]。
static func label(parent: Node, text: String, rect: Rect2, font_size: int = 24, color: Color = CREAM) -> Label:
	var node := Label.new() # 固定区域内自动折行，避免长中文溢出。
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", BODY_FONT)
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
	node.add_theme_font_override("font", BODY_FONT)
	node.add_theme_font_size_override("font_size", 22)
	node.add_theme_color_override("font_color", CREAM)
	node.add_theme_color_override("font_hover_color", CREAM)
	node.add_theme_color_override("font_pressed_color", CREAM)
	node.add_theme_color_override("font_focus_color", CREAM)
	node.add_theme_color_override("font_disabled_color", Color("8c9b88"))
	node.add_theme_stylebox_override("normal", box(GREEN if primary else SURFACE, Color("8ca568") if primary else LINE))
	node.add_theme_stylebox_override("hover", box(Color("6a9352") if primary else CARD, GOLD))
	node.add_theme_stylebox_override("pressed", box(Color("3b5936"), GOLD))
	node.add_theme_stylebox_override("disabled", box(Color("303d33"), Color("4e5d48")))
	node.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), GOLD))
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if callback.is_valid():
		node.pressed.connect(callback)
	parent.add_child(node)
	node.pivot_offset = rect.size * 0.5
	node.mouse_entered.connect(_button_motion.bind(node, 1.025))
	node.mouse_exited.connect(_button_motion.bind(node, 1.0))
	node.button_down.connect(_button_motion.bind(node, 0.98))
	node.button_up.connect(func() -> void: _button_motion(node, 1.025 if node.is_hovered() else 1.0))
	return node

## 对 [param node] 的表现缩放至 [param factor]，替换旧补间以支持连续快速操作。
static func _button_motion(node: Button, factor: float) -> void:
	if node.disabled:
		factor = 1.0
	var previous: Tween = node.get_meta("shop_motion") if node.has_meta("shop_motion") else null # 每个按钮只拥有自己的补间；首次交互还没有元数据。
	if is_instance_valid(previous):
		previous.kill()
	var motion: Tween = node.create_tween() # 绑定按钮生命周期，退出页面时自动释放。
	motion.tween_property(node, "scale", Vector2.ONE * factor, 0.12).set_trans(Tween.TRANS_SINE)
	node.set_meta("shop_motion", motion)

## 设置 [param node] 的 [param value] 禁用态；锁定时收回悬停缩放，解锁后恢复鼠标反馈。
static func set_button_disabled(node: Button, value: bool) -> void:
	if node.disabled == value:
		return
	node.disabled = value
	_button_motion(node, 1.025 if not value and node.is_hovered() else 1.0)

## 绘制 [param offer] 的低对比商品光晕色，只强化原图，不增加营销标签。
static func product_accent(offer: Dictionary) -> Color:
	if bool(offer.get("unique", false)):
		return Color("ddbd96") if str(offer.id) == "spring_cattail" else Color("ead680")
	return Color("b9d78b") if str(offer.get("kind", "")) == "item" else Color("a6c7bf")

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
