## 使用正式镜头组件和正式雨幕，输出墓地下游地图的动画验收帧。
extends SceneTree

## 演示背景与关卡绑定互不干涉：这里仅选择墓地下游的正式夜景素材。
const BACKGROUND_PATH: String = "res://assets/adventure/environments/battle_backgrounds/04_graveyard_downstream_night.jpg"
## 原工程的权威雨幕场景。
const RAIN_PATH: String = "res://scenes/main_game_bg/rain.tscn"
## 已在游戏中接入的独立天气镜头场景。
const LENS_PATH: String = "res://scenes/weather/weather_lens.tscn"
## 第二关使用的正式湿镜头预设。
const PROFILE_PATH: String = "res://resources/weather/fallen_camp_wet_lens.tres"
## 帧输出目录位于系统临时区，避免污染 Godot 游戏仓库。
var _output_root: String = OS.get_environment("TEMP").path_join("pvz_weather_preview")


## 延迟渲染直到游戏树已初始化。
func _initialize() -> void:
    call_deferred("_render_frames")


## 构造与游戏共享的雨幕、镜头组件，并输出连续擦拭与闪电样本。
func _render_frames() -> void:
    var dir_result: Error = DirAccess.make_dir_recursive_absolute(_output_root) # 输出目录状态。
    if dir_result != OK:
        push_error("WEATHER_OUTPUT_DIRECTORY_FAILED " + str(dir_result))
        quit(1)
        return

    var background: TextureRect = TextureRect.new() # 正式背景纹理节点。
    background.texture = load(BACKGROUND_PATH)
    background.position = Vector2(-185.0, 0.0)
    background.size = background.texture.get_size()
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(background)

    var rain: Node = load(RAIN_PATH).instantiate() # 原工程雨幕。
    root.add_child(rain)

    var lens: WeatherLensController = load(LENS_PATH).instantiate() # 游戏使用的同款效果控制器。
    lens.profile = load(PROFILE_PATH)
    root.add_child(lens)
    lens.set_process(false)
    lens.reset_effect()

    for index: int in range(32):
        var mouse_position: Vector2 = Vector2.INF # 默认无交互。
        if index >= 7 and index <= 21:
            var t: float = float(index - 7) / 14.0 # 擦拭轨迹的归一化进度。
            mouse_position = Vector2(145.0 + t * 760.0, 400.0 - sin(t * PI) * 170.0)
        if index == 25:
            lens.trigger_lightning()
        lens.advance_effect(0.19, mouse_position)
        await process_frame
        await RenderingServer.frame_post_draw
        var screenshot: Image = root.get_viewport().get_texture().get_image() # 当帧 GPU 图像。
        var path: String = _output_root.path_join("grave_%02d.png" % index) # 当前序号对应的 PNG。
        var result: Error = screenshot.save_png(path)
        if result != OK:
            push_error("WEATHER_FRAME_FAILED " + path + " " + str(result))
            quit(1)
            return
        if index in [0, 10, 17, 25, 31]:
            print("WEATHER_KEYFRAME " + path)

    print("WEATHER_PREVIEW_FINISHED " + _output_root)
    quit(0)
