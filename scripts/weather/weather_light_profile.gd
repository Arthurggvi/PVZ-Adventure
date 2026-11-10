## 地图定义的全部背景光源；最多 8 个，由天气后处理统一采样。
extends Resource
class_name WeatherLightProfile

@export var sources: Array[WeatherLightSource] = []
## 宽光晕的屏幕散射系数。
@export_range(0.0, 2.0, 0.02) var bloom_wide: float = 0.75
## 紧凑光晕的屏幕散射系数。
@export_range(0.0, 2.0, 0.02) var bloom_tight: float = 0.48
## 空气中的局部光散射系数。
@export_range(0.0, 2.0, 0.02) var air_scatter: float = 0.44
## 受光雨线增强系数。
@export_range(0.0, 2.0, 0.02) var rain_response: float = 0.78
## 受光水珠的亮边增强系数。
@export_range(0.0, 2.0, 0.02) var droplet_response: float = 0.6

## 统一校验，避免场景中静态光源超出 Shader 数组大小。
func validate() -> PackedStringArray:
    var result: PackedStringArray = PackedStringArray()
    if sources.size() > 8:
        result.append("天气光场最多支持 8 个静态光源。")
    for source: WeatherLightSource in sources:
        if source == null or not source.background_uv.is_finite() or source.radius_px <= 0.0:
            result.append("天气光源的锚点或半径无效。")
    return result
