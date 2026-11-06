extends Zombie001Norm
## Death transition: atomically retire the held-flag arm before showing the
## death-only inner arm. Keeps two-arm topology; never per-frame visibility hacks.
func anim_death_start() -> void:
    var flag_hand: CanvasItem = get_node("Body/BodyCorrect/Zombie_flaghand") as CanvasItem
    var holding_arm: CanvasItem = get_node("Body/BodyCorrect/Zombie_innerarm_screendoor") as CanvasItem
    flag_hand.visible = false
    holding_arm.visible = false
    super.anim_death_start()
