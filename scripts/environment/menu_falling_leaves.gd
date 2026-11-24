## Menu falling leaves: capped pool, correlated turbulence, lift, drag and 2D tumbling.
extends Node2D

const POOL_SIZE := 20
const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const LEAF_TEXTURES = [
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_01.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_02.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_03.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_04.png"),
    preload("res://assets/adventure/environment_fx/v3/art/foliage/main_menu/leaf_05.png")
]
const SHAPE_WEIGHTS := [3, 4, 3, 4, 1, 2, 0]

## Injected from the menu composition root. No parent-path traversal or global singleton.
var wind: Node
var particles: Array[Dictionary] = []
var active := false
var spawned_total := 0
var _cooldown := 0.25
var _random := RandomNumberGenerator.new()

func _ready() -> void:
    _random.randomize()
    for i in range(POOL_SIZE):
        var sprite := Sprite2D.new()
        sprite.texture = LEAF_TEXTURES[i % LEAF_TEXTURES.size()]
        sprite.visible = false
        add_child(sprite)
        particles.append({"sprite": sprite, "alive": false})
    set_active(false)

func bind_wind(controller: Node) -> void:
    assert(controller != null and controller.has_signal("gust_started"))
    if wind == controller:
        return
    if wind != null and wind.gust_started.is_connected(_gust_burst):
        wind.gust_started.disconnect(_gust_burst)
    wind = controller
    wind.gust_started.connect(_gust_burst)

func set_active(enabled: bool) -> void:
    if enabled:
        assert(is_instance_valid(wind), "ForegroundLeaves requires a bound wind controller")
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
    var count := 0
    for particle in particles:
        if particle.alive:
            count += 1
    return count

func _gust_burst(_power: float) -> void:
    if not active or not is_visible_in_tree():
        return
    for _i in range(_random.randi_range(3, 6)):
        _spawn()

func _spawn() -> void:
    for particle in particles:
        if particle.alive:
            continue
        var leaf: Sprite2D = particle.sprite
        var shape_index: int = SHAPE_WEIGHTS[_random.randi_range(0, SHAPE_WEIGHTS.size() - 1)]
        var size := _random.randf_range(0.62, 1.15)
        leaf.texture = LEAF_TEXTURES[shape_index]
        leaf.position = Vector2(_random.randf_range(100.0, 755.0), _random.randf_range(25.0, 175.0))
        leaf.rotation = _random.randf_range(-PI, PI)
        leaf.scale = Vector2.ONE * size
        leaf.visible = true
        particle.alive = true
        particle.age = 0.0
        particle.life = _random.randf_range(7.5, 14.0)
        particle.velocity = Vector2(_random.randf_range(-42.0, 135.0), _random.randf_range(-52.0, 83.0))
        particle.wind_factor = _random.randf_range(0.62, 1.42)
        particle.sink = _random.randf_range(17.0, 39.0)
        particle.drag = _random.randf_range(0.7, 1.8)
        particle.phase = _random.randf_range(0.0, TAU)
        particle.frequency = _random.randf_range(1.2, 3.7)
        particle.eddy_timer = _random.randf_range(0.15, 0.65)
        particle.eddy = Vector2.ZERO
        particle.spin = _random.randf_range(-2.4, 2.4)
        particle.tumble_speed = _random.randf_range(2.0, 5.3)
        particle.base_size = size
        particle.alpha = _random.randf_range(0.68, 0.96)
        spawned_total += 1
        return

func _process(delta: float) -> void:
    _cooldown -= delta
    if _cooldown <= 0.0:
        _spawn()
        _cooldown = _random.randf_range(1.6, 3.3)
    for particle in particles:
        if particle.alive:
            _advance(particle, delta)

func _advance(particle: Dictionary, delta: float) -> void:
    particle.age += delta
    var leaf: Sprite2D = particle.sprite
    if particle.age >= particle.life or leaf.position.x < -70.0 or leaf.position.x > CANVAS_SIZE.x + 70.0 or leaf.position.y > CANVAS_SIZE.y + 70.0:
        particle.alive = false
        leaf.visible = false
        return
    var age: float = particle.age
    particle.eddy_timer -= delta
    if particle.eddy_timer <= 0.0:
        # Low-frequency impulses, smoothly damped below. No white-noise jitter.
        particle.eddy = Vector2(_random.randf_range(-110.0, 110.0), _random.randf_range(-100.0, 83.0))
        particle.eddy_timer = _random.randf_range(0.45, 1.35)
    var wave := sin(age * particle.frequency + particle.phase)
    var meander := sin(age * 0.71 + particle.phase * 2.3)
    var shared_x: float = wind.direction * (38.0 + wind.strength * 110.0)
    var destination := Vector2(
        shared_x * particle.wind_factor + particle.eddy.x + 38.0 * wave,
        particle.sink + 25.0 * meander + particle.eddy.y - 16.0 * wind.strength
    )
    # Exponential damping preserves similar motion at 30/60/120 Hz.
    var response: float = 1.0 - exp(-particle.drag * delta)
    particle.velocity = particle.velocity.lerp(destination, response)
    leaf.position += particle.velocity * delta
    leaf.rotation += (particle.spin + 1.1 * wave + 0.55 * meander) * delta
    # Pseudo 3-D flutter: changing width and mirroring while turning.
    var facing := cos(age * particle.tumble_speed + particle.phase)
    leaf.scale.x = particle.base_size * (0.18 + 0.82 * absf(facing)) * (1.0 if facing >= 0.0 else -1.0)
    leaf.scale.y = particle.base_size * (0.91 + 0.09 * sin(age * particle.frequency * 1.4 + particle.phase))
    var fade_in := clampf(age / 0.6, 0.0, 1.0)
    var fade_out := clampf((particle.life - age) / 1.5, 0.0, 1.0)
    leaf.modulate.a = particle.alpha * minf(fade_in, fade_out)
