## Main-menu-only foliage layer. The underlay and leaf sprites come from the same background.
## No custom physics, particle spawner or per-frame CPU updates.
extends Node2D

const CLEAN_UNDERLAY = preload("res://assets/adventure/environment_fx/v2/art/foliage/main_menu/tree_underlay_clean.png")
const ORIGINAL_UNDERLAY = preload("res://assets/adventure/environment_fx/v2/art/foliage/main_menu/tree_underlay_original.png")
const CLEAN_LEAVES = preload("res://assets/adventure/environment_fx/v2/art/foliage/main_menu/tree_leaves_clean.png")
const ORIGINAL_LEAVES = preload("res://assets/adventure/environment_fx/v2/art/foliage/main_menu/tree_leaves_original.png")

@onready var underlay: Sprite2D = $Underlay
@onready var leaves: Sprite2D = $Leaves

var _active := true
var _clean_sky := true

func _ready() -> void:
    # Each menu instance owns its shader parameters; no shared material state.
    leaves.material = leaves.material.duplicate()
    visibility_changed.connect(_refresh)
    _refresh()

## The overlay is always present at rest, so turning FX off restores the original artwork.
func set_environment_state(active: bool, clean_sky: bool) -> void:
    _active = active
    _clean_sky = clean_sky
    if is_node_ready():
        _refresh()

func _refresh() -> void:
    underlay.texture = CLEAN_UNDERLAY if _clean_sky else ORIGINAL_UNDERLAY
    leaves.texture = CLEAN_LEAVES if _clean_sky else ORIGINAL_LEAVES
    var wind_material := leaves.material as ShaderMaterial
    wind_material.set_shader_parameter("wind_enabled", _active and is_visible_in_tree())
