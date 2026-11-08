extends ZB000Base
class_name ZB002BlackGeneral
## Registered Black General battle entity. Visual timeline only until gameplay AI is authored.
## The inherited ZB000Base owns health, damage, death, trophy requests, and registration.

@onready var visual: BlackGeneralVisual = $Body/BlackGeneralVisual

func ready_norm() -> void:
    super.ready_norm()
    visual.player.animation_finished.connect(_on_visual_animation_finished)
    visual.play_action(&"teleport_in")

func ready_show() -> void:
    super.ready_show()
    visual.play_action(&"idle")

func character_death() -> void:
    if is_death:
        return
    super.character_death()
    if is_instance_valid(visual):
        visual.play_action(&"teleport_out")
    else:
        request_trophy()
        queue_free()

func _on_visual_animation_finished(action: StringName) -> void:
    match action:
        &"teleport_in":
            if not is_death:
                visual.play_action(&"idle")
        &"teleport_out":
            if is_death:
                request_trophy()
                queue_free()
