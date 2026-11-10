## 演示专用真实 Godot 场景：使用权威第四关阶段资源和正式天气导演烘焙视频帧。
extends Node2D

## 墓地下游正式战斗场景背景；仅用于烘焙演示。
const BACKGROUND_PATH: String = "res://assets/adventure/environments/battle_backgrounds/04_graveyard_downstream_night.jpg"
## 系统临时目录，避免二进制帧进入源码仓库。
var _output_root: String = OS.get_environment("TEMP").path_join("pvz_weather_preview")


## 正常场景启动包含工程自动加载单例，避免命令行 --script 跳过完整游戏环境。
func _ready() -> void:
    call_deferred("_render_frames")


## 解析真正的普通与噩梦阶段，并使用游戏内相同的天气导演绘制阶段渐变。
func _render_frames() -> void:
    var directory_error: Error = DirAccess.make_dir_recursive_absolute(_output_root) # 输出目录。
    if directory_error != OK:
        push_error("WEATHER_OUTPUT_DIR_ERROR " + str(directory_error))
        get_tree().quit(1)
        return

    var stage: StageDefinition = AdventureStageRegistry.resolve(4) # 第四关最终环境数据。
    if stage == null or stage.environment == null:
        push_error("GRAVE_DOWNSTREAM_STAGE_MISSING")
        get_tree().quit(1)
        return
    var normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(
        stage, StagePhaseDefinition.Kind.NORMAL) # 普通阶段。
    var nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(
        stage, StagePhaseDefinition.Kind.NIGHTMARE) # 噩梦阶段。
    if normal == null or nightmare == null or normal.weather_sequence != null \
            or nightmare.weather_sequence == null or stage.environment.rain \
            or stage.environment.weather_lens_profile == null:
        push_error("WEATHER_STAGE_CONFIG_INVALID")
        get_tree().quit(1)
        return
    print("WEATHER_NORMAL_DRY_NIGHTMARE_TRANSITION_READY")

    var background: TextureRect = TextureRect.new() # 正式战斗地面图。
    background.texture = load(BACKGROUND_PATH)
    background.position = Vector2(-185.0, 0.0)
    background.size = background.texture.get_size()
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    var foreground: Node2D = Node2D.new() # 原版雨幕承载容器。
    add_child(foreground)
    var director: BattleWeatherDirector = BattleWeatherDirector.new() # 复用同一游戏天气导演。
    director.setup(foreground, self, stage.environment.weather_lens_profile, stage.environment.rain)
    add_child(director)
    director.set_process(false)
    if not director.current_strength().is_zero_approx():
        push_error("WEATHER_NORMAL_NOT_DRY")
        get_tree().quit(1)
        return

    for index: int in range(48):
        if index == 5:
            director.play_sequence(nightmare.weather_sequence)
            director.set_process(false)
        var cursor: Vector2 = Vector2.INF # 演示擦拭坐标。
        if index >= 24 and index <= 38:
            var t: float = float(index - 24) / 14.0 # 鼠标轨迹进度。
            cursor = Vector2(145.0 + t * 760.0, 405.0 - sin(t * PI) * 160.0)
        director.advance_weather(1.0) # GIF 中 1 帧表示关卡 1 秒。
        var lens: WeatherLensController = get_node_or_null(^"WeatherLens") as WeatherLensController
        if lens != null:
            lens.set_process(false)
            lens.advance_effect(1.0, cursor)
        await get_tree().process_frame
        await RenderingServer.frame_post_draw
        var screenshot: Image = get_viewport().get_texture().get_image() # GPU 真实画面。
        var filename: String = _output_root.path_join("phase_%02d.png" % index) # 当前帧路径。
        if screenshot.save_png(filename) != OK:
            push_error("WEATHER_FRAME_EXPORT_ERROR " + filename)
            get_tree().quit(1)
            return
        if index in [0, 5, 12, 20, 32, 41, 47]:
            print("WEATHER_STATE ", index, ": ", director.current_strength())
    print("WEATHER_PHASE_PREVIEW_OK")
    get_tree().quit(0)
