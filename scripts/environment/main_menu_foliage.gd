## Menu canopy motion: preserve intact background; displace only leaf interiors.
## The falling-leaf sibling uses the same wind node via explicit menu injection.
extends Node2D

const MOTION_MASK = preload("res://assets/adventure/environment_fx/v5/art/foliage/main_menu/foliage_motion_core.png")
const MOTION_SHADER = preload("res://shaders/adventure/menu_foliage_internal.gdshader")

@onready var wind: Node = $Wind

var _background: TextureRect
var _previous_material: Material
var _motion_material: ShaderMaterial
var _active := true

func _ready() -> void:
    visibility_changed.connect(_refresh)
    _refresh()

func bind_background(target: TextureRect) -> void:
    assert(target != null and target.texture != null)
    if _background == target:
        return
    _restore_background()
    _background = target
    _previous_material = target.material
    _motion_material = ShaderMaterial.new()
    _motion_material.shader = MOTION_SHADER
    _motion_material.set_shader_parameter("motion_core", MOTION_MASK)
    _motion_material.set_shader_parameter("artwork_pixels", target.texture.get_size())
    _motion_material.set_shader_parameter("amplitude_pixels", 7.0)
    target.material = _motion_material
    _refresh()

func set_environment_state(active: bool, _clean_sky: bool) -> void:
    _active = active
    _refresh()

func _refresh() -> void:
    var running := _active and is_visible_in_tree()
    wind.set_active(running)
    set_process(running)
    if _motion_material != null and not running:
        _motion_material.set_shader_parameter("wind_strength", 0.0)

func _process(_delta: float) -> void:
    if _motion_material != null:
        _motion_material.set_shader_parameter("wind_strength", wind.strength)
        _motion_material.set_shader_parameter("wind_time", wind.wind_time)

func _exit_tree() -> void:
    _restore_background()

func _restore_background() -> void:
    if is_instance_valid(_background) and _background.material == _motion_material:
        _background.material = _previous_material
    _background = null
    _motion_material = null
    _previous_material = null
