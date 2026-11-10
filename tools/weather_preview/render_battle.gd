## Full combat weather preview: instantiate the authoritative battle scene, real cards, plants and zombies.
## Isolated user-data directory is supplied by the launch command; no player save mutations.
extends Node

const STAGE_INDEX: int = 4
const SAMPLE_COUNT: int = 54
const FRAME_STEP_SECONDS: float = 0.18
const WEATHER_SECONDS_PER_FRAME: float = 0.9
const OUTPUT_FOLDER: String = "pvz_weather_battle_preview"

var _game: MainGameManager
var _stage: StageDefinition
var _director: BattleWeatherDirector
var _output_path: String


## Start rendering after the autoloads and scene tree are initialized.
func _ready() -> void:
    call_deferred("_prepare_battle")


## Build a throwaway test battle from real stage definitions, without entering the player's AdventureSession.
func _prepare_battle() -> void:
    _output_path = OS.get_environment("TEMP").path_join(OUTPUT_FOLDER)
    if DirAccess.make_dir_recursive_absolute(_output_path) != OK:
        push_error("BATTLE_PREVIEW_CANNOT_CREATE_DIR")
        get_tree().quit(1)
        return
    _stage = AdventureStageRegistry.resolve(STAGE_INDEX)
    var normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(_stage, StagePhaseDefinition.Kind.NORMAL)
    var nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(_stage, StagePhaseDefinition.Kind.NIGHTMARE)
    if normal == null or nightmare == null or nightmare.weather_sequence == null:
        push_error("BATTLE_PREVIEW_NO_STAGE_WEATHER")
        get_tree().quit(1)
        return
    var level: ResourceLevelData = AdventureBattleEnvironmentAdapter.build(_stage, normal)
    if level == null or level.is_rain or level.weather_lens_profile == null:
        push_error("BATTLE_PREVIEW_LEVEL_INVALID")
        get_tree().quit(1)
        return
    level.look_show_zombie = false
    level.can_choosed_card = false
    level.start_sun = 775
    level.max_choosed_card_num = 7
    level.prechosen_cards.clear()
    for plant_type: int in [
        CharacterRegistry.PlantType.P002SunFlower,
        CharacterRegistry.PlantType.P001PeaShooterSingle,
        CharacterRegistry.PlantType.P006SnowPea,
        CharacterRegistry.PlantType.P004WallNut,
        CharacterRegistry.PlantType.P008PeaShooterDouble,
        CharacterRegistry.PlantType.P005PotatoMine,
        CharacterRegistry.PlantType.P009PuffShroom
    ]:
        level.prechosen_cards.append(ResourceCardReference.create(ResourceCardReference.CardType.Plant, plant_type))
    level.all_pre_plant_data.clear()
    for plant_info: Vector3i in [
        Vector3i(1, 2, CharacterRegistry.PlantType.P002SunFlower),
        Vector3i(2, 2, CharacterRegistry.PlantType.P002SunFlower),
        Vector3i(3, 2, CharacterRegistry.PlantType.P002SunFlower),
        Vector3i(4, 2, CharacterRegistry.PlantType.P002SunFlower),
        Vector3i(5, 2, CharacterRegistry.PlantType.P002SunFlower),
        Vector3i(1, 4, CharacterRegistry.PlantType.P001PeaShooterSingle),
        Vector3i(2, 4, CharacterRegistry.PlantType.P006SnowPea),
        Vector3i(3, 4, CharacterRegistry.PlantType.P008PeaShooterDouble),
        Vector3i(4, 4, CharacterRegistry.PlantType.P001PeaShooterSingle),
        Vector3i(5, 4, CharacterRegistry.PlantType.P009PuffShroom),
        Vector3i(2, 6, CharacterRegistry.PlantType.P004WallNut),
        Vector3i(4, 6, CharacterRegistry.PlantType.P004WallNut)
    ]:
        var preset: PrePlantResource = PrePlantResource.new()
        preset.plant_cell_pos = Vector2i(plant_info.x, plant_info.y)
        preset.plant_type = plant_info.z as CharacterRegistry.PlantType
        level.all_pre_plant_data.append(preset)

    Global.game_para = level
    var battle_path: String = str(Global.main_scene_registry.MainScenesMap.get(level.game_sences, ""))
    if battle_path.is_empty():
        push_error("BATTLE_PREVIEW_SCENE_NOT_REGISTERED")
        get_tree().quit(1)
        return
    _game = load(battle_path).instantiate() as MainGameManager
    if _game == null:
        push_error("BATTLE_PREVIEW_SCENE_INSTANTIATION_FAILED")
        get_tree().quit(1)
        return
    get_tree().root.add_child(_game)
    get_tree().current_scene = _game
    print("BATTLE_PREVIEW_REAL_SCENE ", battle_path)
    var ready_to_fight: bool = false
    for iteration: int in range(750):
        if is_instance_valid(_game) and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
            ready_to_fight = true
            break
        await get_tree().process_frame
    if not ready_to_fight:
        push_error("BATTLE_PREVIEW_GAME_NOT_RUNNING stage=" + str(_game.main_game_progress))
        get_tree().quit(1)
        return
    await get_tree().create_timer(0.3).timeout
    _director = _game.background_manager.weather
    if _director == null or not _director.current_strength().is_zero_approx():
        push_error("BATTLE_PREVIEW_NORMAL_PHASE_HAS_RAIN")
        get_tree().quit(1)
        return
    var spawner = _game.zombie_manager
    var demo_zombies: Array[Vector3i] = [
        Vector3i(CharacterRegistry.ZombieType.Z001Norm, 0, 840),
        Vector3i(CharacterRegistry.ZombieType.Z003Cone, 1, 930),
        Vector3i(CharacterRegistry.ZombieType.Z005Bucket, 2, 1010),
        Vector3i(CharacterRegistry.ZombieType.Z001Norm, 3, 870),
        Vector3i(CharacterRegistry.ZombieType.Z003Cone, 4, 975)
    ]
    var created: int = 0
    for z: Vector3i in demo_zombies:
        if spawner.create_skill_zombie(z.x as CharacterRegistry.ZombieType, z.y, float(z.z)) != null:
            created += 1
    print("BATTLE_PREVIEW_ZOMBIES=", created, " CARDS=", _game.card_manager.card_slot_battle.curr_cards.size(),
        " PREPLANTS=", _game.plant_cell_manager.curr_plant_num)
    if created < 3 or _game.card_manager.card_slot_battle.curr_cards.size() < 5:
        push_error("BATTLE_PREVIEW_MISSING_REAL_GAMEPLAY_ENTITIES")
        get_tree().quit(1)
        return
    await _capture_nightmare(nightmare.weather_sequence)


## Sample full viewport from the same active battle scene, including real UI and characters.
func _capture_nightmare(timeline: WeatherSequence) -> void:
    for index: int in range(SAMPLE_COUNT):
        if index == 6:
            _game.background_manager.transition_weather(timeline)
            _director.set_process(false)
            print("BATTLE_PREVIEW_NIGHTMARE_RAIN_START")
        if index >= 6:
            _director.advance_weather(WEATHER_SECONDS_PER_FRAME)
        await get_tree().create_timer(FRAME_STEP_SECONDS).timeout
        await RenderingServer.frame_post_draw
        var picture: Image = get_viewport().get_texture().get_image()
        var path: String = _output_path.path_join("combat_%02d.png" % index)
        if picture.save_png(path) != OK:
            push_error("BATTLE_PREVIEW_FRAME_FAILED " + path)
            get_tree().quit(1)
            return
        if index in [0, 8, 17, 30, 46, 53]:
            var rain_node: MainGameRain = _director.get("_rain") as MainGameRain
            print("BATTLE_PREVIEW_STATE frame=", index,
                " weather=", _director.current_strength(),
                " rain_node=", is_instance_valid(rain_node),
                " rain_emitting=", rain_node.rain_particles.emitting if is_instance_valid(rain_node) else false,
                " particle_ratio=", rain_node.rain_particles.amount_ratio if is_instance_valid(rain_node) else 0.0)
    print("BATTLE_PREVIEW_COMPLETE ", _output_path)
    get_tree().quit(0)
