## 镜头水珠的纯游戏时间状态模拟，不依赖战场、节点或 Shader。
extends RefCounted
class_name WeatherLensDroplets

## 统一的 GPU 水滴容量。
const CAPACITY: int = 20

## 单颗水珠的位置、半径、保持时间和滑落速度。
var _drops: Array[Dictionary] = []
## 可重复的水滴状态随机源。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 上次有效鼠标采样，供连续线段擦除水珠；离开视口后为 INF。
var _previous_mouse: Vector2 = Vector2.INF


## 重置动态水珠；[param seed_value] 决定可重复的预览序列。
func reset(seed_value: int = 20261110) -> void:
    _rng.seed = seed_value
    _drops.clear()
    _previous_mouse = Vector2.INF
    for index: int in range(CAPACITY):
        _respawn(index)


## 推进附着、增长、滑落、被擦除、合并。
## [param delta] 模拟时间（秒）。
## [param speed_factor] 预设的水珠速度倍率。
## [param mouse_position] 鼠标视口像素坐标，INF 表示没有交互。
## [param wipe_radius] 鼠标清除半径（像素）。
## [param viewport_size] 当前视口尺寸（像素）。
func advance(delta: float, speed_factor: float, mouse_position: Vector2, wipe_radius: float, viewport_size: Vector2) -> void:
    var mouse_valid: bool = mouse_position.is_finite() and Rect2(Vector2.ZERO, viewport_size).has_point(mouse_position) # 有效交互范围。
    var wipe_start: Vector2 = _previous_mouse if _previous_mouse.is_finite() else mouse_position # 当前笔画起点。
    var wiping: bool = mouse_valid and (not _previous_mouse.is_finite() or mouse_position != _previous_mouse) # 停止移动时允许重新附着水珠。
    _previous_mouse = mouse_position if mouse_valid else Vector2.INF
    for index: int in range(_drops.size()):
        var drop: Dictionary = _drops[index] # 单水珠物理状态。
        var hold: float = float(drop["hold"]) - delta # 剩余附着时间。
        drop["hold"] = hold
        if hold <= 0.0:
            var speed: float = minf(0.27, float(drop["speed"]) + 0.11 * delta * speed_factor)
            var position: Vector2 = drop["position"]
            position += Vector2(float(drop["drift"]) * delta, speed * delta)
            drop["speed"] = speed
            drop["position"] = position
            drop["radius"] = minf(11.0, float(drop["radius"]) + 0.24 * delta)
        _drops[index] = drop
        var uv: Vector2 = drop["position"]
        if uv.y > 1.04 or uv.x < -0.05 or uv.x > 1.05:
            _respawn(index)
            continue
        if wiping:
            var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(uv * viewport_size, wipe_start, mouse_position) # 水珠到笔画的最近点。
            if (uv * viewport_size).distance_to(nearest) < wipe_radius * 0.67:
                _respawn(index)

    # 水珠接触后按二维截面积合并，促使较大水珠提前失稳。
    for i: int in range(_drops.size()):
        for j: int in range(i + 1, _drops.size()):
            var a: Dictionary = _drops[i]
            var other: Dictionary = _drops[j]
            var pa: Vector2 = a["position"]
            var pb: Vector2 = other["position"]
            var ra: float = float(a["radius"])
            var rb: float = float(other["radius"])
            if (pa * viewport_size).distance_to(pb * viewport_size) < (ra + rb) * 0.45:
                a["radius"] = minf(12.0, sqrt(ra * ra + rb * rb))
                a["hold"] = -0.01
                _drops[i] = a
                _respawn(j)


## 将当前水珠变为固定容量的 Shader 状态，缺少的槽位填零。
## 返回每颗水珠的 UV(x,y)、半径(像素)和当前滑落系数。
func get_uniform_data() -> PackedVector4Array:
    var buffer: PackedVector4Array = PackedVector4Array() # GPU 数据序列。
    for index: int in range(CAPACITY):
        if index >= _drops.size():
            buffer.append(Vector4.ZERO)
            continue
        var droplet: Dictionary = _drops[index]
        var uv: Vector2 = droplet["position"]
        buffer.append(Vector4(uv.x, uv.y, float(droplet["radius"]),
            clampf(float(droplet["speed"]) / 0.22, 0.0, 1.0)))
    return buffer


## 重新生成水珠的状态，排除外部依赖。
## [param index] 当前被替换的水珠索引。
func _respawn(index: int) -> void:
    var droplet: Dictionary = {
        "position": Vector2(_rng.randf_range(0.02, 0.98), _rng.randf_range(0.03, 0.92)),
        "radius": _rng.randf_range(3.3, 9.6),
        "hold": _rng.randf_range(0.4, 3.4),
        "speed": 0.0,
        "drift": _rng.randf_range(-0.02, 0.02)
    } # 以 UV 存坐标、以屏幕像素存半径。
    if index < _drops.size():
        _drops[index] = droplet
    else:
        _drops.append(droplet)
