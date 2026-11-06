extends Zombie000Base
## Adventure-only rear flag; torso Sprite2D owns animation transform.
## Invisible for legacy/base. The tier binder replaces the single transparent
## source texture before the zombie enters the scene tree.
@onready var _adventure_backflag: Sprite2D = $Body/BodyCorrect/Zombie_football_upperbody/AdventureTierFlag

func _ready() -> void:
	super._ready()
	_adventure_backflag.visible = adventure_tier_id in [
		&"veteran", &"elite", &"tier4", &"tier5"
	]
	$AnimationPlayer.animation_started.connect(_on_native_animation_started)

## Native action boundary, not a per-frame visibility workaround.
## Once the original death animation begins, the attached backflag retires.
func _on_native_animation_started(animation_name: StringName) -> void:
	if animation_name == &"Zombie_football_death":
		_adventure_backflag.visible = false
