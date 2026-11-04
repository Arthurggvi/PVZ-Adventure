## Single-source menu canopy: transparent repair underlay, one leaf layer and shared wind.
extends Node2D

const CLEAN_UNDERLAY = preload("res://assets/adventure/environment_fx/v4/art/foliage/main_menu/tree_underlay_clean_alpha.png")
const ORIGINAL_UNDERLAY = preload("res://assets/adventure/environment_fx/v4/art/foliage/main_menu/tree_underlay_original_alpha.png")
const CLEAN_LEAVES = preload("res://assets/adventure/environment_fx/v2/art/foliage/main_menu/tree_leaves_clean.png")
const ORIGINAL_LEAVES = preload("res://assets/adventure/environment_fx/v2/art/foliage/main_menu/tree_leaves_original.png")

@onready var underlay: Sprite2D = $Underlay
@onready var leaves: Sprite2D = $Leaves
@onready var wind: Node = $Wind

var _active := true
var _clean_sky := true

func _ready() -> void:
    leaves.material = leaves.material.duplicate()
    visibility_changed.connect(_refresh)
    _refresh()

func set_environment_state(active: bool, clean_sky: bool) -> void:
    _active = active
    _clean_sky = clean_sky
    if is_node_ready():
        _refresh()

func _refresh() -> void:
    underlay.texture = CLEAN_UNDERLAY if _clean_sky else ORIGINAL_UNDERLAY
    leaves.texture = CLEAN_LEAVES if _clean_sky else ORIGINAL_LEAVES
    var running := _active and is_visible_in_tree()
    wind.set_active(running)
    set_process(running)
    if not running:
        (leaves.material as ShaderMaterial).set_shader_parameter("wind_strength", 0.0)

func _process(_delta: float) -> void:
    var material := leaves.material as ShaderMaterial
    material.set_shader_parameter("wind_strength", wind.strength)
    material.set_shader_parameter("wind_time", wind.wind_time)
