## 基于屏幕轨迹的水膜擦拭模拟；与镜头材质、战斗节点完全解耦。
extends RefCounted
class_name WeatherLensWipe

const CAPACITY: int = 24
const SPACING_PX: float = 17.0

## 按出生时间维护的擦拭采样点。
var _marks: Array[Vector4] = []
## 连续鼠标轨迹最后一次有效的像素位置。
var _previous: Vector2 = Vector2.INF


## 统一采样入口，负坐标或 INF 清除连续轨迹，不清除尚未恢复的水膜。
## [param position] 当前鼠标屏幕像素位置。
## [param seconds] 当前天气时间轴的秒数。
## [param viewport_size] 视口尺寸（像素）。
## [param recovery_seconds] 旧擦痕的指数衰减时间常数。
func advance(position: Vector2, seconds: float, viewport_size: Vector2,
        recovery_seconds: float) -> void:
    if not position.is_finite() or position.x < 0.0 or position.y < 0.0             or position.x >= viewport_size.x or position.y >= viewport_size.y:
        _previous = Vector2.INF
    elif not _previous.is_finite():
        _add_mark(position / viewport_size, seconds)
        _previous = position
    else:
        var travel: float = position.distance_to(_previous)
        if travel >= SPACING_PX:
            var samples: int = mini(CAPACITY, ceili(travel / SPACING_PX))
            for i: int in range(1, samples + 1):
                var px: Vector2 = _previous.lerp(position, float(i) / float(samples))
                _add_mark(px / viewport_size, seconds)
        _previous = position
    _marks = _marks.filter(func(mark: Vector4) -> bool:
        return seconds - mark.z < recovery_seconds * 5.0
    )


## 在固定长度笔刷缓冲区内写入新的清晰区域。
func _add_mark(uv: Vector2, seconds: float) -> void:
    _marks.append(Vector4(uv.x, uv.y, seconds, 1.0))
    if _marks.size() > CAPACITY:
        _marks.pop_front()


## 返回固定容量 Uniform 数据，空槽显式为 0。
func get_uniform_data() -> PackedVector4Array:
    var result: PackedVector4Array = PackedVector4Array()
    for i: int in range(CAPACITY):
        result.append(_marks[i] if i < _marks.size() else Vector4.ZERO)
    return result


## 切换场景时只清理此组件自己的擦拭历史。
func reset() -> void:
    _marks.clear()
    _previous = Vector2.INF
