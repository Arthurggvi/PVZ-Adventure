## Visual primitives for the reusable PC inventory. All textures are separate, reusable PNGs.
extends RefCounted
const ROOT := "res://assets/adventure/ui/inventory/"

static func texture(path: String) -> Texture2D:
	var uri := ROOT + path
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
	node.position = pos
	node.size = size
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

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
