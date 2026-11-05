## One construction boundary for every registered plant species.
## The registry owns species identity; inherited scenes only provide behavior/art.
extends RefCounted
class_name PlantSceneFactory

static func create(plant_type: CharacterRegistry.PlantType) -> Plant000Base:
	if not CharacterRegistry.PlantInfo.has(plant_type):
		push_error("PlantSceneFactory: unregistered species %s" % plant_type)
		return null
	var entry: Dictionary = CharacterRegistry.PlantInfo[plant_type]
	var scene: PackedScene = entry.get(CharacterRegistry.PlantInfoAttribute.PlantScenes)
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
