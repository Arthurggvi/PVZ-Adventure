extends ZB000Base
class_name ZB003WhiteDuke
## Visual-only Boss scaffold. Combat skills and action-tree are NOT designed yet.
## Reuse the generic boss HP/phase/HUD pipeline and Jackson native show loop.
@onready var visual: WhiteDukeVisual = $Body/WhiteDukeVisual

func _apply_boss_visual_phase(phase: int, _animated: bool) -> void:
	visual.set_phase2(phase >= 2)

func character_death() -> void:
	if is_death:
		return
	super.character_death()
	# No made-up death action; use the existing Boss reward and fade pipeline.
	request_trophy()
	_fade_and_remove()

## Visual hooks for the later behaviour tree. No summons or lane logic are fabricated.
func play_summon_visual() -> void:
	visual.play_summon()

func play_teleport_arrive_visual() -> void:
	visual.play_teleport_in()

func play_teleport_depart_visual() -> void:
	visual.play_teleport_out()
