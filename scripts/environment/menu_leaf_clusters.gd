## Separate hand-painted foliage clusters pivoted around their own branch attachment.
extends Node2D

const CLEAN = [
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_a_clean.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_b_clean.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_c_clean.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_d_clean.png")
]
const ORIGINAL = [
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_a_original.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_b_original.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_c_original.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/cluster_d_original.png")
]
## Positions match the artist-approved PNG manifest and the 1920x1080 design canvas.
const REGIONS = [
    {"anchor": Vector2(208, 33), "top_left": Vector2(115, 0), "period": 2.0},
    {"anchor": Vector2(340, 34), "top_left": Vector2(272, 0), "period": 2.37},
    {"anchor": Vector2(687, 67), "top_left": Vector2(575, 0), "period": 2.74},
    {"anchor": Vector2(568, 143), "top_left": Vector2(480, 85), "period": 3.11}
]

@onready var wind: Node = $"../Wind"
var pivots: Array[Node2D] = []
var sprites: Array[Sprite2D] = []

func _ready() -> void:
    for i in range(REGIONS.size()):
        var pivot := Node2D.new()
        pivot.position = REGIONS[i].anchor
        var art := Sprite2D.new()
        art.texture = CLEAN[i]
        art.centered = false
        art.position = REGIONS[i].top_left - REGIONS[i].anchor
        art.modulate.a = 0.84
        pivot.add_child(art)
        add_child(pivot)
        pivots.append(pivot)
        sprites.append(art)

func configure(enabled: bool, clean_sky: bool) -> void:
    visible = enabled
    set_process(enabled)
    for i in range(sprites.size()):
        sprites[i].texture = CLEAN[i] if clean_sky else ORIGINAL[i]
        if not enabled:
            pivots[i].position = REGIONS[i].anchor
            pivots[i].rotation = 0.0

func _process(_delta: float) -> void:
    var t: float = wind.wind_time
    var force: float = wind.strength
    for i in range(pivots.size()):
        var phase := float(i) * 1.63
        var period: float = REGIONS[i].period
        pivots[i].rotation = deg_to_rad(1.5 + i * 0.45) * force * sin(t * TAU / period + phase)
        pivots[i].position = REGIONS[i].anchor + force * Vector2(
            3.4 * sin(t * TAU / (period * 1.35) + phase),
            1.2 * cos(t * TAU / (period * 0.95) + phase)
        )
