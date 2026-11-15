## 启动及单卡装配契约；身份查询不应实体化卡面模板。
extends Node

func _ready() -> void:
	get_tree().create_timer(12.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func _run() -> void:
	if not _expect(not AllCards.is_catalog_materialized(), "AllCards was eagerly materialized"):
		return
	var plant_type := CharacterRegistry.PlantType.P001PeaShooterSingle
	var info: Dictionary = CharacterRegistry.PlantInfo[plant_type]
	if not _expect(info[CharacterRegistry.PlantInfoAttribute.PlantScenes] is String, "plant scene not a path"):
		return
	if not _expect(info[CharacterRegistry.PlantInfoAttribute.PlantConditionResource] is String,
			"plant condition not a path"):
		return
	if not _expect(Global.character_registry.get_plant_scene(plant_type) is PackedScene, "plant scene unresolved"):
		return
	if not _expect(Global.character_registry.get_plant_info(plant_type,
			CharacterRegistry.PlantInfoAttribute.PlantConditionResource) is ResourcePlantCondition,
			"planting condition unresolved"):
		return
	if not _expect(Global.character_registry.get_zombie_info(
			CharacterRegistry.ZombieType.Z001Norm, CharacterRegistry.ZombieInfoAttribute.ZombieScenes) is PackedScene,
			"zombie scene unresolved"):
		return
	if not _expect(Global.character_registry.get_zombie_boss_info(
			CharacterRegistry.ZombieBossType.ZB001Doctor,
			CharacterRegistry.ZombieBossInfoAttribute.BossScenes) is PackedScene, "boss scene unresolved"):
		return
	if not _expect(SceneRegistry.SUN is PackedScene, "legacy scene registry API broken"):
		return
	if not _expect(not AllCards.is_catalog_materialized(), "static registries loaded cards"):
		return
	var references: Array[ResourceCardReference] = AllCards.get_references(
		ResourceCardReference.CardType.Plant)
	if not _expect(not references.is_empty(), "lazy catalogue references empty"):
		return
	if not _expect(not AllCards.is_catalog_materialized(), "metadata query materialized card templates"):
		return
	if not _expect(AllCards.get_template(references[0]) != null, "catalogue template absent"):
		return
	if not _expect(AllCards.is_catalog_materialized(), "requested card template not materialized"):
		return
	var card: Card = AllCards.create_card(references[0])
	if not _expect(card != null, "card copy failed"):
		return
	card.free()
	print("PASS: lazy startup resources, legacy registry API and card templates")
	get_tree().quit(0)

func _expect(condition: bool, description: String) -> bool:
	if not condition:
		push_error("FAIL startup architecture: " + description)
		get_tree().quit(1)
	return condition
