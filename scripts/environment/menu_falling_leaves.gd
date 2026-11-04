## Capped reusable sprites: no per-spawn allocations, timers or GPU particles.
extends Node2D

const POOL_SIZE := 20
const LEAF_TEXTURES = [
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_01.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_02.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_03.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_04.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_05.png")
]

@onready var wind: Node = $"../Wind"
var particles: Array[Dictionary] = []
var active := false
var _cooldown := 0.25
var _random := RandomNumberGenerator.new()
var spawned_total := 0

func _ready() -> void:
    _random.randomize()
    for i in range(POOL_SIZE):
        var sprite := Sprite2D.new()
        sprite.visible = false
        sprite.texture = LEAF_TEXTURES[i % LEAF_TEXTURES.size()]
        add_child(sprite)
        particles.append({"sprite": sprite, "alive": false})
    wind.gust_started.connect(_gust_burst)
    set_active(true)

func set_active(enabled: bool) -> void:
    active = enabled
    visible = enabled
    set_process(enabled)
    if enabled:
        _cooldown = minf(_cooldown, 0.4)
    else:
        for particle in particles:
            particle.alive = false
            particle.sprite.visible = false
        _cooldown = 0.25

func live_count() -> int:
    var result := 0
    for particle in particles:
        if particle.alive:
            result += 1
    return result

func _gust_burst(_power: float) -> void:
    if not active or not is_visible_in_tree():
        return
    for i in range(_random.randi_range(3, 6)):
        _spawn()

func _spawn() -> void:
    for particle in particles:
        if particle.alive:
            continue
        var leaf: Sprite2D = particle.sprite
        # Two-lobed silhouettes appear more often than the larger leaf fans.
        var leaf_index: int = [3, 4, 3, 4, 1, 2, 0][_random.randi_range(0, 6)]
        leaf.texture = LEAF_TEXTURES[leaf_index]
        leaf.position = Vector2(_random.randf_range(130.0, 760.0), _random.randf_range(38.0, 185.0))
        leaf.rotation = _random.randf_range(-PI, PI)
        leaf.scale = Vector2.ONE * _random.randf_range(0.65, 1.13)
        leaf.visible = true
        particle.alive = true
        particle.age = 0.0
        particle.life = _random.randf_range(6.0, 10.0)
        particle.velocity = Vector2(_random.randf_range(85.0, 145.0), _random.randf_range(37.0, 80.0))
        particle.spin = _random.randf_range(-1.9, 1.9)
        particle.wave = _random.randf_range(0.0, TAU)
        particle.alpha = _random.randf_range(0.75, 1.0)
        spawned_total += 1
        return

func _process(delta: float) -> void:
    _cooldown -= delta
    if _cooldown <= 0.0:
        _spawn()
        _cooldown = _random.randf_range(1.5, 3.0)
    var force: float = wind.strength
    for particle in particles:
        if not particle.alive:
            continue
        particle.age += delta
        var leaf: Sprite2D = particle.sprite
        if particle.age >= particle.life or leaf.position.x > 1920 or leaf.position.y > 1090:
            particle.alive = false
            leaf.visible = false
            continue
        var side_wobble := sin(particle.age * 2.8 + particle.wave) * 28.0
        leaf.position += (particle.velocity + Vector2(42.0 * force + side_wobble, 0.0)) * delta
        leaf.rotation += particle.spin * delta
        var fade_in := clampf(particle.age / 0.45, 0.0, 1.0)
        var fade_out := clampf((particle.life - particle.age) / 1.1, 0.0, 1.0)
        leaf.modulate.a = particle.alpha * minf(fade_in, fade_out)
