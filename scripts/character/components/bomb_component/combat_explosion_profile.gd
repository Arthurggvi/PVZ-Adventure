## Reusable explosion contract. Geometry, presentation, and damage are independent.
extends Resource
class_name CombatExplosionProfile

@export var shape: Shape2D
@export var hit_offset := Vector2.ZERO
@export_flags_2d_physics var collision_mask: int = 2050
@export_range(-1, 8, 1) var lane_radius: int = 1
@export var visuals: PackedScene
@export var visuals_offset := Vector2.ZERO
@export var visuals_scale := 1.0
@export var sound: StringName = &"explosion"
