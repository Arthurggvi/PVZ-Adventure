## Toolbar-only visual component factory. Emits gestures through injected callbacks.
extends RefCounted

const ART := "res://assets/adventure/ui/bottom_bar/"
## 设置原图内嵌旧底盘，绘制齿轮时只保留金属部分。
const GEAR_FACE = preload("res://shaders/adventure/toolbar_gear_face.gdshader")
## 以原图齿轮为中心，四周保留少量抗锯齿边缘。
const GEAR_REGION := Rect2(55, 54, 168, 168)

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
	if feature_id == "settings" and icon.texture != null:
		_add_gear_face(icon)
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

## 给设置 [param icon] 换上通用槽框，并在相同设计中心绘制齿轮。
static func _add_gear_face(icon: TextureRect) -> void:
	var face_texture := AtlasTexture.new() # 只采样原图中偏离画布中心的齿轮区域。
	face_texture.atlas = icon.texture
	face_texture.region = GEAR_REGION
	icon.texture = asset("slots/slot_normal.png")
	var face := TextureRect.new() # 前景随同槽框一起缩放和定位。
	face.texture = face_texture
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size = Vector2(92, 92)
	face.position = (icon.size - face.size) * 0.5
	var face_material := ShaderMaterial.new() # 保留齿轮纹理，露出共享槽框的底面。
	face_material.shader = GEAR_FACE
	face.material = face_material
	icon.add_child(face)
