extends Zombie001Norm
## Screendoor owns its held-arm transition into the inherited death pose.
## Release the held-arm configuration in one callback, without per-frame
## animation patches or touching the normal-zombie arm scene.
func anim_death_start() -> void:
	var held_nodes: Array[CanvasItem] = [
		$Body/BodyCorrect/Zombie_innerarm_screendoor,
		$Body/BodyCorrect/Zombie_innerarm_screendoor_hand,
		$Body/BodyCorrect/Zombie_outerarm_screendoor,
	]
	for held: CanvasItem in held_nodes:
		held.visible = false
	super.anim_death_start()
