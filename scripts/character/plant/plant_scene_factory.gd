## One construction boundary for every registered plant species.
## The registry owns species identity; inherited scenes only provide behavior/art.
extends RefCounted
class_name PlantSceneFactory

static func create(plant_type: int) -> Plant000Base:
	# The registry resolves scenes at runtime; static preload dependencies here
	# would create a cycle: registry -> condition resource -> plant cell -> factory.
	var scene: PackedScene = Global.character_registry.get_plant_scene(plant_type)
	if scene == null:
		push_error("PlantSceneFactory: missing plant scene for species %s" % plant_type)
		return null
	var instance: Node = scene.instantiate()
	var plant: Plant000Base = instance as Plant000Base
	if plant == null:
		push_error("PlantSceneFactory: registered scene is not a plant: %s" % plant_type)
		if instance != null:
			instance.free()
		return null
	# Explicitly override inherited scene metadata before init_plant/_ready.
	plant.plant_type = plant_type
	return plant
