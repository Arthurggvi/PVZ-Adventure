## 持久水膜遮罩，每个纹素保存指数衰减的等效时间；静止时由 Shader 恢复。
extends RefCounted
class_name WeatherLensWipe

## 一个遮罩纹素覆盖的视口像素数。
const PIXELS_PER_TEXEL: float = 4.0
## 未擦拭区域的时间哨兵。
const UNTOUCHED_TIME: float = -10000.0
## 单通道浮点时间遮罩。
var _image: Image
## 持续复用、仅在笔画变化时上传的 GPU 纹理。
var _texture: ImageTexture
## 上次有效鼠标位置，离开视口后为 INF。
var _previous: Vector2 = Vector2.INF
## 上次采样的游戏时间。
var _previous_seconds: float = 0.0


## 创建空遮罩，保证首次交互前材质也有有效纹理。
func _init() -> void:
    _image = Image.create(1, 1, false, Image.FORMAT_RF)
    _image.fill(Color(UNTOUCHED_TIME, 0.0, 0.0, 1.0))
    _texture = ImageTexture.create_from_image(_image)


## 按 [param viewport_size] 像素尺寸调整遮罩，保留原 UV 位置的擦痕。
func resize(viewport_size: Vector2) -> void:
    var size := Vector2i(maxi(1, ceili(viewport_size.x / PIXELS_PER_TEXEL)),
        maxi(1, ceili(viewport_size.y / PIXELS_PER_TEXEL))) # 目标纹素尺寸。
    if _image.get_size() != size:
        _image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
        _texture.set_image(_image)
        _previous = Vector2.INF


## 光栅化完整鼠标线段，慢速移动和快速长划共用同一连续笔刷。
## [param position] 视口像素位置，越界或 INF 时断开笔画。
## [param seconds] 游戏时间；[param viewport_size] 视口像素尺寸。
## [param recovery_seconds] 回湿时间常数；[param radius] 笔刷半径，单位像素。
func advance(position: Vector2, seconds: float, viewport_size: Vector2,
        recovery_seconds: float, radius: float = 65.0) -> void:
    resize(viewport_size)
    if not position.is_finite() or not Rect2(Vector2.ZERO, viewport_size).has_point(position):
        _previous = Vector2.INF
        return
    var start: Vector2 = _previous if _previous.is_finite() else position # 笔画起点。
    var start_seconds: float = _previous_seconds if _previous.is_finite() else seconds # 起点时间。
    var moved: bool = not _previous.is_finite() or start != position # 静止时让水膜恢复。
    _previous = position
    _previous_seconds = seconds
    if not moved:
        return
    var scale: Vector2 = Vector2(_image.get_size()) / viewport_size # 像素到纹素比例。
    var lower := Vector2i(((start.min(position) - Vector2.ONE * radius) * scale).floor()) # 包围框左上角。
    var upper := Vector2i(((start.max(position) + Vector2.ONE * radius) * scale).ceil()) # 包围框右下角。
    var segment: Vector2 = position - start # 本帧连续线段。
    var length_squared: float = segment.length_squared() # 投影归一化分母。
    for y: int in range(maxi(0, lower.y), mini(_image.get_height(), upper.y + 1)): # 笔画覆盖行。
        for x: int in range(maxi(0, lower.x), mini(_image.get_width(), upper.x + 1)): # 笔画覆盖列。
            var pixel: Vector2 = (Vector2(x, y) + Vector2.ONE * 0.5) / scale # 纹素中心像素坐标。
            var along: float = clampf((pixel - start).dot(segment) / maxf(length_squared, 0.001), 0.0, 1.0) # 线段投影比例。
            var distance: float = pixel.distance_to(start + segment * along) # 到笔画中心线距离。
            var brush: float = 1.0 - smoothstep(radius * 0.30, radius, distance) # 柔边擦除权重。
            if brush <= 0.001:
                continue
            var stamp: float = lerpf(start_seconds, seconds, along) + maxf(0.2, recovery_seconds) * log(brush) # 等效衰减时间。
            _image.set_pixel(x, y, Color(maxf(stamp, _image.get_pixel(x, y).r), 0.0, 0.0, 1.0))
    _texture.update(_image)


## 返回持续复用的浮点时间纹理。
func get_texture() -> ImageTexture:
    return _texture


## 重开场景或切换预设时清理自己的水膜历史。
func reset() -> void:
    _image.fill(Color(UNTOUCHED_TIME, 0.0, 0.0, 1.0))
    _texture.update(_image)
    _previous = Vector2.INF
    _previous_seconds = 0.0
