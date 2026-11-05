## Visual primitives for the reusable PC inventory. All textures are separate, reusable PNGs.
extends RefCounted
const ROOT := "res://assets/adventure/ui/inventory/"
## 挖空格子的填色，保留原图边框。
const FRAME_SHADER = preload("res://shaders/adventure/inventory_slot_frame.gdshader")

static func texture(path: String) -> Texture2D:
	var uri: String = path if path.begins_with("res://") else ROOT + path
	return load(uri) as Texture2D if ResourceLoader.exists(uri) else null

static func panel(parent: Node, path: String, pos: Vector2, size: Vector2, margin: int = 31) -> NinePatchRect:
	var node := NinePatchRect.new()
	node.texture = texture(path)
	node.position = pos
	node.size = size
	node.patch_margin_left = margin
	node.patch_margin_right = margin
	node.patch_margin_top = margin
	node.patch_margin_bottom = margin
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func image(parent: Node, path: String, pos: Vector2, size: Vector2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	# Godot applies the texture minimum size on tree insertion; enforce final slot geometry after it.
	node.position = pos
	node.size = size
	return node

## 在 [param parent] 中以 [param pos]、[param size] 绘制原版槽框。
## [param is_plant] 区分原始纹理的内沿尺寸，返回不拦截鼠标的透明边框。
static func slot_frame(parent: Node, pos: Vector2, size: Vector2, is_plant: bool = false) -> TextureRect:
	var path: String = "slots/plant_slot_normal.png" if is_plant else "slots/item_slot_normal.png" # 对应格子的原图。
	var frame: TextureRect = image(parent, path, pos, size) # 在槽位内容之后叠加的边框。
	var frame_material := ShaderMaterial.new() # 仅遮去原图内部填色。
	frame_material.shader = FRAME_SHADER
	frame_material.set_shader_parameter("inset_pixels", Vector2(18, 18) if is_plant else Vector2(13, 13))
	frame.material = frame_material
	return frame

## 在 [param parent] 中绘制右下角对齐 [param corner] 的深底数量角标。
## [param caption] 为完整数量文字，[param color] 为文字颜色，[param font_size] 为字号。
static func count_badge(parent: Node, caption: String, corner: Vector2,
		color: Color = Color("fff4d6"), font_size: int = 18) -> void:
	var badge := Label.new() # 根据文字宽度自动扩展的数量角标。
	badge.text = caption
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 1
	var font := SystemFont.new() # 使用粗体数字，缩放后仍能区分笔画。
	font.font_names = PackedStringArray(["Arial"])
	font.font_weight = 700
	badge.add_theme_font_override("font", font)
	badge.add_theme_font_size_override("font_size", font_size)
	badge.add_theme_color_override("font_color", color)
	badge.add_theme_color_override("font_outline_color", Color("120c08"))
	badge.add_theme_constant_override("outline_size", 2)
	var style := StyleBoxFlat.new() # 深色底和细金边隔开复杂图案。
	style.bg_color = Color("2b1c12")
	style.border_color = Color("d7b477")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("normal", style)
	parent.add_child(badge)
	badge.reset_size()
	badge.position = corner - badge.size

static func label(parent: Node, value: String, pos: Vector2, size: Vector2, font_size: int = 24, color: Color = Color("382719")) -> Label:
	var node := Label.new()
	node.text = value
	node.position = pos
	node.size = size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color("d6ba88"))
	node.add_theme_constant_override("shadow_offset_x", 1)
	node.add_theme_constant_override("shadow_offset_y", 1)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.clip_text = true
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func button(parent: Node, base: String, pos: Vector2, size: Vector2, callback: Callable) -> TextureButton:
	var node := TextureButton.new()
	node.position = pos
	node.size = size
	node.ignore_texture_size = true
	node.stretch_mode = TextureButton.STRETCH_SCALE
	node.texture_normal = texture(base + "_normal.png")
	node.texture_hover = texture(base + "_hover.png")
	node.texture_pressed = texture(base + "_pressed.png")
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.focus_mode = Control.FOCUS_NONE
	if callback.is_valid():
		node.pressed.connect(callback)
	parent.add_child(node)
	return node

## 在 [param parent] 中创建有文字的素材按钮；[param base] 指定现有状态贴图，[param caption] 为标题。
## [param pos]、[param size] 使用父坐标；按 [param callback] 派发点击，禁用及焦点状态同样复用素材。
static func action_button(parent: Node, caption: String, base: String, pos: Vector2, size: Vector2, callback: Callable) -> Button:
	var node := Button.new() # 文字与按钮共用一个控件，禁用后不会遗留可点击的覆盖层。
	node.text = caption
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_size_override("font_size", 25)
	node.add_theme_color_override("font_color", Color("fff0cb"))
	node.add_theme_color_override("font_hover_color", Color("fff8e7"))
	node.add_theme_color_override("font_pressed_color", Color("fff0cb"))
	node.add_theme_color_override("font_focus_color", Color("fff8e7"))
	node.add_theme_color_override("font_disabled_color", Color("b6a58b"))
	node.add_theme_color_override("font_outline_color", Color("302015"))
	node.add_theme_constant_override("outline_size", 2)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]: # 所有可见状态使用同一套资源。
		var style := StyleBoxTexture.new() # 九宫格保留按钮边角，只延展中部。
		style.texture = texture(base + "_%s.png" % ("hover" if state == "focus" else state))
		style.texture_margin_left = 22.0
		style.texture_margin_right = 22.0
		style.texture_margin_top = 16.0
		style.texture_margin_bottom = 16.0
		style.content_margin_left = 16.0
		style.content_margin_right = 16.0
		style.content_margin_top = 8.0
		style.content_margin_bottom = 8.0
		node.add_theme_stylebox_override(state, style)
	if callback.is_valid():
		node.pressed.connect(callback)
	parent.add_child(node)
	node.position = pos
	node.size = size
	return node
