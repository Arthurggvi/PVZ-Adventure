## 任何关卡、阶段或演出均可使用的天气过渡时间轴，结束后保持末帧状态。
extends Resource
class_name WeatherSequence

## 按 time_seconds 升序排列的天气关键帧。
@export var frames: Array[WeatherKeyframe] = []
## 满雨势时的实际 GPU 雨粒子发射比例；旧雨场景原值约 0.162。
@export_range(0.01, 1.0, 0.01) var rain_particle_ratio_at_full: float = 0.162
## 可选分层雨幕配置。其它雨关未配置时继续沿用中雨预设。
@export var rain_visual_profile: RainVisualProfile
## 可选降雨混音预设，与雨幕使用同一时间轴强度；空值只播放原版雨声。
@export var rain_audio_profile: RainAudioProfile
## 可选风沙预设；沙强度大于零时未指定则使用通用参数。
@export var sand_visual_profile: SandVisualProfile
## 沙暴对指针的最大顺风漂移速度，视口像素/秒；0 不影响指针，普通天气默认关闭。
@export_range(0.0, 40.0, 0.5) var sand_cursor_speed: float = 0.0

## 校验持续时间、顺序及数值是否合法，不依赖具体关卡。
func validate() -> PackedStringArray:
    var errors: PackedStringArray = PackedStringArray() # 全部关键帧错误。
    if not is_finite(sand_cursor_speed) or sand_cursor_speed < 0.0 or sand_cursor_speed > 40.0:
        errors.append("风沙指针漂移速度必须处于 0..40。")
    if not is_finite(rain_particle_ratio_at_full) or rain_particle_ratio_at_full <= 0.0 or rain_particle_ratio_at_full > 1.0:
        errors.append("满雨势粒子发射比例必须处于 (0, 1]。")
    if frames.is_empty():
        errors.append("天气过渡至少需要一个关键帧。")
        return errors
    var last_time: float = -1.0 # 上一关键帧秒数。
    for frame: WeatherKeyframe in frames: # 同时校验各个独立天气通道。
        if frame == null or not is_finite(frame.time_seconds) or not is_finite(frame.rain) or not is_finite(frame.lens) or not is_finite(frame.sand):
            errors.append("天气关键帧存在无效值。")
            continue
        if frame.time_seconds <= last_time or frame.rain < 0.0 or frame.rain > 1.0 or frame.lens < 0.0 or frame.lens > 1.0 or frame.sand < 0.0 or frame.sand > 1.0:
            errors.append("天气关键帧时间未递增或强度超出 0..1。")
        last_time = frame.time_seconds
    if frames[0] != null and not is_zero_approx(frames[0].time_seconds):
        errors.append("天气时间轴第一个关键帧必须从 0 秒开始。")
    return errors


## 返回指定阶段经过时间的雨势与镜头强度。
## [param elapsed_seconds] 从时间轴触发开始计数的秒数。
## 返回 Vector2(x=雨强度, y=湿镜头强度)；最后关键帧之后恒定保持。
func sample(elapsed_seconds: float) -> Vector2:
    var values: Vector3 = sample_channels(elapsed_seconds) # 保留既有雨景调用者的 Vector2 接口。
    return Vector2(values.x, values.y)


## 在 [param elapsed_seconds] 秒处采样雨、湿镜头、风沙，返回 Vector3(x=雨, y=镜头, z=沙)。
## 三个通道使用同一插值与末帧保持规则，旧资源缺少 sand 时默认为零。
func sample_channels(elapsed_seconds: float) -> Vector3:
    if frames.is_empty():
        return Vector3.ZERO
    var t: float = maxf(elapsed_seconds, 0.0) # 非负查询时刻。
    var first: WeatherKeyframe = frames[0] # 时间轴起始状态。
    if t <= first.time_seconds:
        return Vector3(first.rain, first.lens, first.sand)
    for index: int in range(1, frames.size()): # 定位查询时刻所处的相邻关键帧。
        var next_frame: WeatherKeyframe = frames[index] # 右侧关键帧。
        if t > next_frame.time_seconds:
            continue
        var previous: WeatherKeyframe = frames[index - 1] # 左侧关键帧。
        # 当前区间的归一化进度。
        var fraction: float = clampf((t - previous.time_seconds) /
            maxf(0.001, next_frame.time_seconds - previous.time_seconds), 0.0, 1.0)
        var eased: float = fraction * fraction * (3.0 - 2.0 * fraction) # smoothstep 插值。
        return Vector3(lerpf(previous.rain, next_frame.rain, eased),
            lerpf(previous.lens, next_frame.lens, eased), lerpf(previous.sand, next_frame.sand, eased))
    var last: WeatherKeyframe = frames[frames.size() - 1] # 持续天气，永不自动回晴。
    return Vector3(last.rain, last.lens, last.sand)


## 返回本次天气变化的总时间，单位为秒。
func get_duration() -> float:
    return 0.0 if frames.is_empty() else frames[frames.size() - 1].time_seconds
