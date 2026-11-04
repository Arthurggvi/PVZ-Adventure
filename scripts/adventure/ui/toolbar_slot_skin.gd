## Toolbar-only visual component factory. Emits gestures through injected callbacks.
extends RefCounted

const ART := "res://assets/adventure/ui/bottom_bar/"

static func asset(relative_path: String) -> Texture2D:
	var path := ART + relative_path
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

static func make_slot(parent: Control, entry: Dictionary, index: int,
		on_hover: Callable, on_leave: Callable, on_press: Callable) -> Dictionary:
	var feature_id: String = entry.id
	var pos := Vector2(45.0 + float(index) * 141.0, 22.0)
	var icon := TextureRect.new()
	icon.name = feature_id + "_Icon"
	icon.position = pos
	icon.size = Vector2(132.0, 132.0)
	icon.pivot_offset = icon.size * 0.5
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = asset("slots/slot_empty.png" if feature_id == "empty" else "icons/" + str(entry.asset))
	parent.add_child(icon)
	if icon.texture == null:
		var fallback := Label.new()
		fallback.text = str(entry.label).left(1)
		fallback.size = icon.size
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 54)
		fallback.add_theme_color_override("font_color", Color("d7b16c"))
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(fallback)
	var hitbox := Button.new()
	hitbox.name = feature_id + "_Hitbox"
	hitbox.position = pos
	hitbox.size = icon.size
	hitbox.focus_mode = Control.FOCUS_NONE
	hitbox.flat = true
	hitbox.mouse_entered.connect(on_hover.bind(feature_id, index))
	hitbox.mouse_exited.connect(on_leave.bind(feature_id))
	hitbox.pressed.connect(on_press.bind(feature_id))
	parent.add_child(hitbox)
	return {"icon": icon, "button": hitbox}
