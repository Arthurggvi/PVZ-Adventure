extends EnemyStructureBase
class_name PvZ2TombstoneTarget

## Combat entity notifies the tile owner through signals; no dependency on its scene.
signal health_changed(current_hp: int)
signal destroyed

func ready_norm() -> void:
	super.ready_norm()
	add_to_group(&"lobber_secondary_targets")
	hp_component.signal_hp_loss.connect(_on_hp_loss)

func _on_hp_loss(hp: int, _drop: bool) -> void:
	health_changed.emit(hp)

func character_death() -> void:
	if is_death:
		return
	super.character_death()
	destroyed.emit()
