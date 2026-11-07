## Reusable, non-interactive corner badge: one rank input, no save/gameplay access.
## Rank >= 5: sweep; rank >= 7: glints; rank 10: halo and iridescent body.
extends Control

const Art = preload("res://scripts/adventure/ui/star_badge_art.gd")
const CORNER_SIZE := Vector2(31, 31)
const CORNER_OFFSET := Vector2(-3, -4)
const GLINT_SIZE := Vector2(15, 15)
const HALO_SIZE := Vector2(45, 45)

var _image: TextureRect
var _halo: TextureRect
var _glints: Array[TextureRect] = []

func _init() -> void:
	name = "AdventureStarBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = CORNER_SIZE
	position = CORNER_OFFSET
	z_index = 4
	_image = _new_texture_rect(null, Vector2.ZERO, CORNER_SIZE, "Body")
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _new_texture_rect(texture: Texture2D, origin: Vector2, dimensions: Vector2,
		name_hint: String) -> TextureRect:
	var image := TextureRect.new()
	image.name = name_hint
	image.texture = texture
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(image)
	image.position = origin
	image.size = dimensions
	return image

func _effect_material(mode: int, rank: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Art.FX_SHADER
	material.set_shader_parameter("effect_mode", mode)
	material.set_shader_parameter("rank", float(rank))
	return material

func configure(rank: int) -> void:
	var clamped: int = clampi(rank, 0, 10)
	visible = clamped > 0
	if not visible:
		return
	_image.texture = Art.body(clamped)
	if _image.texture == null:
		push_warning("Missing adventure star badge texture for rank %d" % clamped)
		visible = false
		return
	_image.material = null
	if clamped >= 5:
		var material := _effect_material(0, clamped)
		var sweep := Art.mask(clamped, "sweep_mask")
		var guard := Art.mask(clamped, "number_guard")
		if sweep != null:
			material.set_shader_parameter("sweep_mask", sweep)
		if guard != null:
			material.set_shader_parameter("number_guard", guard)
		if clamped == 10:
			var color_mask := Art.mask(10, "color_mask")
			if color_mask != null:
				material.set_shader_parameter("rainbow_mask", color_mask)
		_image.material = material
	_configure_glints(clamped)
	_configure_halo(clamped)

func _configure_glints(rank: int) -> void:
	var target: int = 0 if rank < 7 else (1 if rank == 7 else 2)
	while _glints.size() < target:
		var origin: Vector2 = (Vector2(0.22, 0.30) if _glints.is_empty()
			else Vector2(0.79, 0.33)) * CORNER_SIZE - GLINT_SIZE * 0.5
		var glint := _new_texture_rect(Art.sparkle(), origin, GLINT_SIZE, "Glint%d" % (_glints.size() + 1))
		glint.material = _effect_material(1, 7)
		_glints.append(glint)
	for index: int in range(_glints.size()):
		_glints[index].visible = index < target

func _configure_halo(rank: int) -> void:
	if rank != 10:
		if is_instance_valid(_halo):
			_halo.visible = false
		return
	if not is_instance_valid(_halo):
		_halo = _new_texture_rect(Art.halo(), (CORNER_SIZE - HALO_SIZE) * 0.5,
			HALO_SIZE, "CrownHalo")
		_halo.material = _effect_material(2, 10)
		move_child(_halo, 0)
	_halo.visible = true
