extends AnimComponentBase
class_name BlackGeneralAnimationComponent
## Adapter from the existing character speed signal to the approved visual player.
@onready var player: AnimationPlayer = $"../Body/BlackGeneralVisual/AnimationPlayer"

func _ready() -> void:
    animation_origin_speed = player.speed_scale
    player.animation_finished.connect(_on_animation_finished)

func owner_update_speed(speed_factor_product: float) -> void:
    player.speed_scale = animation_origin_speed * maxf(0.0, speed_factor_product)

func update_anim_speed_scale(speed_scale: float) -> void:
    player.speed_scale = maxf(0.0, speed_scale)

func stop_anim() -> void:
    player.pause()
